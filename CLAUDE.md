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

# Tests
flutter test
flutter test test/widget_test.dart   # single test file
```

## Architecture

### Routing (`lib/router.dart`)
`go_router` with `usePathUrlStrategy()` (clean URLs, no `#`). Four top-level routes:
- `/` → `RoleChoiceScreen` (landing, choose client or admin)
- `/agendamentocliente` → `MainNavigation` (client flow)
- `/admin` → `LoginScreen`
- `/admin/dashboard` → `AdminNavigation`

### Two distinct UI surfaces

**Client (`lib/screens/`):** `MainNavigation` hosts Home, Appointments, Profile tabs. Booking flow is in `book_appointment_screen.dart` (multi-service selection → time slot → WhatsApp confirmation). Uses the global `lightTheme`/`darkTheme` from `lib/theme.dart` (Inter font, Material 3, brown palette).

**Admin (`lib/screens/admin/`):** `AdminNavigation` is a self-contained widget with its own `_adminTheme` defined inline — dark background `#080808`, gold accent `#F5C200`. Bottom nav + side drawer. Main screens: Dashboard, Agenda (appointments), Caixa (financial), WhatsApp config. Secondary screens (Services, Barbers, Plan Clients, Remarcar) pushed via `Navigator.push` wrapped in the admin theme.

### Auth model
Admin = **any non-anonymous Supabase user** (`!user.isAnonymous`). There are no roles or permission levels. Create admins via Supabase Dashboard → Authentication → Users → Add user (check Auto Confirm). **Do not** create admins via raw SQL — NULL token fields break GoTrue login.

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
Config (URL, API key, templates, enabled flag) lives in the `app_settings` Supabase table. The server runs at `https://wa.tonidinisbarbearia.dartsistemas.com` (HTTPS required — the app is HTTPS and mixed content is blocked). Endpoint: `POST {url}/send`, header `x-api-key`, body `{phone, message}`.

Automated 1-hour-before reminders run as a Node.js cron (`server/wa-reminder/`) on the VPS at `ubuntu@151.247.210.134`, checking every 5 minutes and setting `reminder_sent` on processed appointments.

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
| `lib/screens/admin/remarcar_admin_screen.dart` | Groups appointments by phone (basis for customer dashboard) |
| `lib/screens/admin/barbers_admin_screen.dart` | Barber CRUD (includes `phone` field for notifications) |
| `lib/services/whatsapp_service.dart` | WhatsApp API calls |
| `server/wa-reminder/` | VPS reminder cron script |
| `supabase/` | SQL migrations |
| `wrangler.jsonc` | Cloudflare Workers deploy config (SPA fallback) |

## Pending features (client requests)

1. **Customer dashboard** — list all clients (name, phone, visit count, last visit) from `appointments` grouped by `customer_phone`. See `remarcar_admin_screen.dart` for the grouping pattern.
2. **Color-coded agenda** — requires new `source`/`created_by` field and a slot-blocking feature. Color scheme: gray = normal booking, red = blocked, dark gray = empty, purple = manual walk-in, blue = first-time client.
