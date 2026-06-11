# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter **Web** PWA for **TD Barbearia** (Toni Dinis). Stack: Flutter → Cloudflare Workers (static SPA), Supabase (database + auth), WhatsApp reminder server on a VPS.

- Live site: `https://tonidinisbarbearia.dartsistemas.com`
- Client booking: `/agendamentocliente` · Admin login: `/admin`

## Commands

```bash
# Dev server
flutter run -d chrome

# Production build + deploy (use PowerShell on Windows — bash breaks --base-href)
flutter build web --release --base-href "/"
npx wrangler deploy
```

> **Warning:** On Linux/bash, the `--base-href "/"` flag is misinterpreted as a git path. Run the build from PowerShell or wrap the value in single quotes.

```bash
# Lint / analyze
flutter analyze
```

> **No tests exist yet.** If you add tests: `flutter test` (single file: `flutter test test/<file>.dart`).

## Architecture

### Routing (`lib/router.dart`)
`go_router`; `usePathUrlStrategy()` is called in `main.dart` (not the router) for clean URLs without `#`. Unknown routes fall back to `RoleChoiceScreen` via `errorBuilder`. Four top-level routes:
- `/` → `RoleChoiceScreen` (landing, choose client or admin)
- `/agendamentocliente` → `MainNavigation` (client flow)
- `/admin` → `LoginScreen`
- `/admin/dashboard` → `AdminNavigation`

### Two distinct UI surfaces

**Client (`lib/screens/`):** `MainNavigation` hosts Home, Appointments, Profile tabs. Booking flow is in `book_appointment_screen.dart` (multi-service selection → time slot → WhatsApp confirmation). Uses the global `lightTheme`/`darkTheme` from `lib/theme.dart` (Inter font, Material 3, brown palette).

**Admin (`lib/screens/admin/`):** `AdminNavigation` is a self-contained widget with its own `_adminTheme` defined inline — dark background `#080808`, gold accent `#F5C200`. Bottom nav + side drawer. Main screens: Dashboard, Agenda, Caixa (financial), WhatsApp config. Secondary screens (Services, Barbers, Plan Clients, Remarcar, Inactive Clients) pushed via `Navigator.push` wrapped in the admin theme.

### Auth model
Admin = **any logged-in Supabase user**. Create admins via Supabase Dashboard → Authentication → Users → Add user (check Auto Confirm). **Do not** create admins via raw SQL — NULL token fields break GoTrue login.

**Two admin roles** are resolved at login by `AdminSession` (`lib/utils/admin_session.dart`), which looks up the logged-in `user_id` in the `barbers` table:
- **Super-admin / owner** — no matching `barbers` row (`barberId == null`). Sees all barbers' data.
- **Barber-admin** — has a `barbers` row (`barberId != null`). Scoped to their own data.

`AdminSession.loadFromCurrentUser()` must run right after login and on app reopen with an active session. Admin screens branch on `AdminSession.isSuperAdmin` / `isBarber` to filter what they show.

### Supabase (`lib/supabase/supabase_config.dart`)
Active project: `uebvtbgvsyzbyzdilren.supabase.co`. The anon key is public and committed intentionally.

**Critical gotcha — schema cache:** After any `ALTER TABLE ... ADD COLUMN`, run:
```sql
NOTIFY pgrst, 'reload schema';
```
Without this, PostgREST silently drops the new field on writes. If it persists: Supabase Dashboard → Settings → General → Restart project.

`ensureUserRow()` in `lib/utils/user_bootstrap.dart` upserts the current user into the `users` table on app start.

### Data model
All DB access goes directly through `Supabase.instance.client` — no repository layer. Models (`lib/models/`) contain both the data class and static fetch methods.

**Core tables:**
| Table | Purpose |
|-------|---------|
| `users` | Extends `auth.users`; upserted on app start |
| `barbers` | Barber profiles; `phone` for WhatsApp notifications; `user_id` links a barber-admin login |
| `services` | Services with `price`, `duration_blocks` (1 block = 30 min), `sort_order` (drag-to-reorder in admin), `image_url` (bucket `service-images`) |
| `appointments` | One row per 30-min block; multiple services = consecutive rows. Key fields: `source` (client/admin/recurring), `is_plan_client`, `reminder_sent`, `reminder_24h_sent` |
| `barber_availability` | Weekly schedule per barber (days + hours) |
| `barber_blocked_days` | Full-day blocks for a barber (vacation, day off) |
| `blocked_slots` | Individual 30-min slot blocks per barber |
| `plan_clients` | Clients on the recurring monthly plan (lookup by `phone`) |
| `recurring_schedules` | Active weekly recurring appointments linked to a `plan_client_id` |
| `app_settings` | Key/value config: WhatsApp URL, API key, reminder templates, `wa_enabled`, `reminder_normal_hours` |

**Multi-service booking:** each service with `duration_blocks > 1` occupies consecutive 30-min `appointments` rows at booking time. `splitRuns()` in `reminder.js` re-groups them for sending a single WhatsApp message.

### Color-coded agenda (`agenda_dia_view.dart`)
Each 30-min slot is typed via `_SlotState` enum, driven by the `source` field in `appointments` and availability tables:
- `free` — empty slot (dark gray)
- `client` — normal booking (`source = 'client'`)
- `newClient` — first-time customer (detected by history lookup)
- `admin` — manual walk-in entry (`source = 'admin'`, purple)
- `blocked` — slot blocked via `blocked_slots` table (red)

Full-day blocks come from `barber_blocked_days`; individual slot blocks come from `blocked_slots`.

### WhatsApp notifications (`lib/services/whatsapp_service.dart`)
Config (URL, API key, templates, enabled flag) lives in the `app_settings` Supabase table. The send server runs at `https://wa.tonidinisbarbearia.dartsistemas.com` (HTTPS required — mixed content is blocked). Endpoint: `POST {url}/send`, header `x-api-key`, body `{phone, message}`.

Three separate pieces back this feature:
- **`whatsapp-server/`** — Node.js WhatsApp API server (Docker/Procfile) that the app calls directly at `/send`.
- **`server/wa-reminder/reminder.js`** — Node.js cron on the VPS (`ubuntu@151.247.210.134`) running every 5 min. Sends reminders and marks `reminder_sent`. Plan clients get **two** reminders: 24h before (`reminder_24h_sent`) + N hours before (configurable via `reminder_normal_hours` in `app_settings`), each with a distinct template. Normal clients get only the N-hour reminder.
- **`server/wa-reminder/generate-recurring.js`** — Node.js cron running once daily (`0 2 * * *`). For each active `recurring_schedules` row, creates `appointments` with `is_plan_client = true` and `source = 'recurring'` for the next 30 days (sliding window).
- **`supabase/functions/send-whatsapp/`** — Supabase Edge Function alternative for sending.

**Required migration for plan reminders:** `supabase/migrations/recurring_schedules_and_reminders.sql` adds `reminder_24h_sent` column, creates `recurring_schedules` table, and inserts plan templates into `app_settings`. Run it if plan reminders are not working.

### Design tokens
- Admin theme: bg `#080808`, card `#111111`, border `#222222`, gold `#F5C200`, text `#F0EDE8`
- Client theme: defined in `lib/theme.dart` and `lib/constants/colors.dart`
- Font: Inter via `google_fonts`
- Text scale clamped to 0.8–1.0 in `main.dart` to prevent layout breaks on large-font devices

## Key files

| File | Purpose |
|------|---------|
| `lib/screens/book_appointment_screen.dart` | Client booking flow + WhatsApp send + plan client detection |
| `lib/screens/admin/agenda_dia_view.dart` | Day agenda: color-coded 30-min slots, full-day blocks, manual walk-in entry |
| `lib/screens/admin/appointments_admin_screen.dart` | Admin agenda list view (hosts `AgendaDiaView`) |
| `lib/screens/admin/dashboard_screen.dart` | Admin dashboard (summary stats) |
| `lib/screens/admin/financial_admin_screen.dart` | Caixa — revenue view; excludes `is_plan_client` rows from revenue |
| `lib/screens/admin/plan_clients_admin_screen.dart` | Plan client CRUD |
| `lib/screens/admin/recurring_schedule_screen.dart` | Recurring schedule config per plan client |
| `lib/screens/admin/remarcar_admin_screen.dart` | Groups appointments by phone for rebooking |
| `lib/screens/admin/inactive_clients_screen.dart` | Lists clients with no recent appointments |
| `lib/screens/customer_history_screen.dart` | Customer lookup/history by phone |
| `lib/screens/admin/barbers_admin_screen.dart` | Barber CRUD (`phone`, `user_id`) |
| `lib/utils/admin_session.dart` | Resolves super-admin vs barber-admin role for the session |
| `lib/services/whatsapp_service.dart` | WhatsApp API calls |
| `server/wa-reminder/reminder.js` | VPS reminder cron (every 5 min) |
| `server/wa-reminder/generate-recurring.js` | VPS recurring appointment generator (daily) |
| `supabase/migrations/` | All DB migrations to run on Supabase SQL Editor |
| `wrangler.jsonc` | Cloudflare Workers deploy config (SPA fallback) |
