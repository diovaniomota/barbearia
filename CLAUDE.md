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

> **No tests exist yet** — there is no `test/` directory. If you add tests, run all with `flutter test` (single file: `flutter test test/<file>.dart`).

## Architecture

### Routing (`lib/router.dart`)
`go_router`; `usePathUrlStrategy()` is called in `main.dart` (not the router) for clean URLs without `#`. Unknown routes fall back to `RoleChoiceScreen` via `errorBuilder`. Four top-level routes:
- `/` → `RoleChoiceScreen` (landing, choose client or admin)
- `/agendamentocliente` → `MainNavigation` (client flow)
- `/admin` → `LoginScreen`
- `/admin/dashboard` → `AdminNavigation`

### Two distinct UI surfaces

**Client (`lib/screens/`):** `MainNavigation` hosts Home, Appointments, Profile tabs. Booking flow is in `book_appointment_screen.dart` (multi-service selection → time slot → WhatsApp confirmation). Uses the global `lightTheme`/`darkTheme` from `lib/theme.dart` (Inter font, Material 3, brown palette).

**Admin (`lib/screens/admin/`):** `AdminNavigation` is a self-contained widget with its own `_adminTheme` defined inline — dark background `#080808`, gold accent `#F5C200`. Bottom nav + side drawer. Main screens: Dashboard, Agenda (appointments), Caixa (financial), WhatsApp config. Secondary screens (Services, Barbers, Plan Clients, Remarcar) pushed via `Navigator.push` wrapped in the admin theme.

### Auth model
Admin = **any logged-in Supabase user**. Create admins via Supabase Dashboard → Authentication → Users → Add user (check Auto Confirm). **Do not** create admins via raw SQL — NULL token fields break GoTrue login.

**Two admin roles** are resolved at login by `AdminSession` (`lib/utils/admin_session.dart`), which looks up the logged-in `user_id` in the `barbers` table:
- **Super-admin / owner** — no matching `barbers` row (`barberId == null`). Sees all barbers' data.
- **Barber-admin** — has a `barbers` row (`barberId != null`). Scoped to their own data.

`AdminSession.loadFromCurrentUser()` must run right after login and on app reopen with an active session. Admin screens (dashboard, agenda, caixa, etc.) branch on `AdminSession.isSuperAdmin` / `isBarber` to filter what they show.

### Supabase (`lib/supabase/supabase_config.dart`)
Active project: `uebvtbgvsyzbyzdilren.supabase.co`. The anon key is public and committed intentionally.

**Critical gotcha — schema cache:** After any `ALTER TABLE ... ADD COLUMN`, run:
```sql
NOTIFY pgrst, 'reload schema';
```
Without this, PostgREST silently drops the new field on writes. If it persists: Supabase Dashboard → Settings → General → Restart project.

`ensureUserRow()` in `lib/utils/user_bootstrap.dart` upserts the current user into the `users` table on app start.

### Data model
All DB access goes directly through `Supabase.instance.client` — no repository layer. Models (`lib/models/`) contain both the data class and static fetch methods. Multiple services in one appointment occupy consecutive 30-min slots.

### WhatsApp notifications (`lib/services/whatsapp_service.dart`)
Config (URL, API key, templates, enabled flag) lives in the `app_settings` Supabase table. The send server runs at `https://wa.tonidinisbarbearia.dartsistemas.com` (HTTPS required — the app is HTTPS and mixed content is blocked). Endpoint: `POST {url}/send`, header `x-api-key`, body `{phone, message}`.

Three separate pieces back this feature:
- **`whatsapp-server/`** — the Node.js WhatsApp API server (Docker/Procfile) that the app calls directly at `/send`.
- **`server/wa-reminder/`** — Node.js cron on the VPS (`ubuntu@151.247.210.134`) that sends 1-hour-before reminders, checking every 5 min and setting `reminder_sent` on processed appointments.
- **`supabase/functions/send-whatsapp/`** — a Supabase Edge Function alternative for sending.

### Design tokens
- Admin theme: bg `#080808`, card `#111111`, border `#222222`, gold `#F5C200`, text `#F0EDE8`
- Client theme: defined in `lib/theme.dart` and `lib/constants/colors.dart`
- Font: Inter via `google_fonts`
- Text scale clamped to 0.8–1.0 in `main.dart` to prevent layout breaks on large-font devices

## Key files

| File | Purpose |
|------|---------|
| `lib/screens/book_appointment_screen.dart` | Client booking flow + WhatsApp send |
| `lib/screens/admin/appointments_admin_screen.dart` | Admin agenda view |
| `lib/screens/admin/agenda_dia_view.dart` | Day agenda with color-coded 30-min slots (`_SlotState`: free/client/newClient/admin/blocked) + `blocked_slots` blocking |
| `lib/screens/admin/remarcar_admin_screen.dart` | Groups appointments by phone (rebooking) |
| `lib/screens/customer_history_screen.dart` | Customer lookup/history by phone |
| `lib/screens/admin/barbers_admin_screen.dart` | Barber CRUD (`phone` for notifications; `user_id` links a barber-admin login) |
| `lib/utils/admin_session.dart` | Resolves super-admin vs barber-admin role for the session |
| `lib/services/auth_service.dart` | Supabase auth wrapper (sign in/up, session) |
| `lib/services/whatsapp_service.dart` | WhatsApp API calls |
| `whatsapp-server/` | Node.js WhatsApp send server (Docker) |
| `server/wa-reminder/` | VPS reminder cron script |
| `supabase/functions/send-whatsapp/` | Supabase Edge Function for sending WhatsApp |
| `wrangler.jsonc` | Cloudflare Workers deploy config (SPA fallback) |

## Feature notes

- **Customer dashboard / history** — implemented in `customer_history_screen.dart` (lookup by phone). `remarcar_admin_screen.dart` shows the appointments-grouped-by-phone pattern.
- **Color-coded agenda** — implemented in `agenda_dia_view.dart`. Each 30-min slot has a `_SlotState`: `free` (empty), `client` (normal booking), `newClient` (first-time), `admin` (manual walk-in), `blocked`. Blocking persists to the `blocked_slots` table (also referenced in `book_appointment_screen.dart` and `barbers_admin_screen.dart`).
