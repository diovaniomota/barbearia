# TD Barbearia — Contexto do Projeto (handoff)

> Cole este arquivo no início de um novo chat para o assistente entender o projeto sem reexplicação.

## Resumo
App de agendamento da **Toni Dinis Barbearia (TD Barbearia)**. Flutter **Web**, hospedado na **Cloudflare**, banco **Supabase**, lembretes/notificações via **servidor WhatsApp numa VPS**.

- Código: `d:\barbearia` (Flutter Web)
- Site: `https://tonidinisbarbearia.dartsistemas.com`
- Rota do cliente: `/agendamentocliente` · Login admin: `/admin`

## Build & Deploy (SEMPRE via PowerShell)
```powershell
flutter build web --release --base-href "/"
npx wrangler deploy
```
- No **Bash** o `--base-href "/"` quebra (vira caminho do Git). Use **PowerShell**.
- Deploy: Cloudflare Workers, projeto `barbearia` (assets-only, SPA fallback no `wrangler.jsonc`).

## Supabase (ATENÇÃO — causa-raiz de vários bugs)
- Projeto **ATIVO**: `uebvtbgvsyzbyzdilren.supabase.co`
- O antigo `frigugklxvoawbmvbaft` foi **abandonado** (NXDOMAIN). Já corrigido em `lib/main.dart` (`Supabase.initialize`) e `lib/supabase/supabase_config.dart`.
- **Anon key (pública):** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVlYnZ0Ymd2c3l6Ynl6ZGlscmVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNzM4MTMsImV4cCI6MjA5NTc0OTgxM30.KilnvJtRntdp3LO_mrTKBxpVcaEgOoJSPNEjBGXsrC4`
- **service_role key:** secreta (guardada à parte; só na VPS p/ o lembrete).
- ⚠️ **GOTCHA do schema cache:** ao adicionar coluna com `ALTER TABLE`, rode também `NOTIFY pgrst, 'reload schema';`. Senão o PostgREST **descarta o campo em silêncio** nas gravações (causou os bugs da foto do serviço e do telefone do barbeiro). Se teimar: Settings → General → **Restart project**.

## WhatsApp
- Servidor Node na VPS **`ubuntu@151.247.210.134`**, rodando em `localhost:3001`.
- Exposto por HTTPS: **`https://wa.tonidinisbarbearia.dartsistemas.com`** (nginx + cert Let's Encrypt/certbot; DNS na Cloudflare como **"Somente DNS" / cinza**).
- ⚠️ O app é HTTPS → a URL do servidor na config **DEVE ser HTTPS** (a do subdomínio). HTTP cru dá **"Mixed Content" / "Failed to fetch"**.
- Config (URL, API key, enabled, templates) fica na tabela **`app_settings`** do Supabase.
- Endpoint: `POST {url}/send`, header `x-api-key`, body `{phone, message}`.

## Lembrete automático (1h antes) — JÁ NO AR
- Script Node em `server/wa-reminder/` (repo) e em `/opt/wa-reminder/` (VPS).
- **Cron** a cada 5 min: `*/5 * * * * /opt/wa-reminder/run.sh >> /var/log/wa-reminder.log 2>&1`
- Lê `app_settings` + `appointments`, envia e marca `reminder_sent`. Agrupa múltiplos serviços num único lembrete.
- Migration: `lib/supabase/reminder_migration.sql`.

## Admin / Login
- Admin = **qualquer** usuário com login email/senha no Supabase Auth (NÃO há níveis/role; checa só `não-anônimo` em `login_screen.dart`).
- Criar admin: Supabase → **Authentication → Users → Add user** (marcar **Auto Confirm**).
- ⚠️ **Não** criar admin por SQL cru: campos NULL quebram o login do GoTrue (erro genérico "Verifique suas credenciais"). Conserta setando os tokens para `''` ou recriando pelo painel.

## Gotchas gerais
- **Cache** do navegador (Flutter web/service worker) é agressivo: testar com **Ctrl+Shift+R** ou aba anônima.
- Logo: `assets/images/logo.png` (logo TD preta+dourada). Favicon e ícones PWA gerados dela.
- Paleta: bg `#080808`, dourado `#F5C200`, texto `#F0EDE8`.
- Rotas: `go_router` + `usePathUrlStrategy()` (URLs limpas).
- PWA ativo (instalável, `standalone`, tema escuro).

## Já feito (recente)
- Logo TD + tema escuro dourado em todas as telas
- Múltiplos serviços = horários consecutivos (2 serviços às 9h bloqueiam 9h e 9h30)
- Lembrete WhatsApp 1h antes (cron VPS)
- Notificação pro **barbeiro** no agendamento (telefone do barbeiro escolhido; `barbers.phone`)
- Edição de barbeiro (lápis / toque na linha)
- Botão **"Voltar"** (era "Cancelar") no agendamento
- Fix do campo de telefone (máscara não some mais — criada 1x, não no build)
- Selo **"Cliente Mensalista"** (era "Cliente Plano — não contabilizado no caixa")
- Foto do serviço funcionando (bucket `service-images` público + coluna `image_url`)
- Favicon + ícones PWA com a logo TD; PWA ativado

## Feito (2026-07 — pacote de melhorias)
1. **Dashboard de clientes** — menu Admin → Clientes (`clients_admin_screen.dart`): nome, telefone, visitas, última visita, busca, WhatsApp.
2. **Agenda colorida** — já em `agenda_dia_view.dart` + schema `source` / `created_by` / `blocked_slots` / encaixe admin (roxo).
3. **Auth + guards** — GoRouter protege `/admin/dashboard`; acesso exige `users.is_admin` ou barbeiro linkado (`AdminSession`).
4. **Repositories** — `lib/repositories/` (clients, appointments, agenda) + `slot_logic.dart`.
5. **Realtime** — agenda do dia escuta `appointments` / `blocked_slots` / `extra_slots`.
6. **WhatsApp outbox** — log em `whatsapp_outbox` (sent/failed).
7. **Testes** — `test/slot_logic_test.dart`; deploy script `scripts/deploy.ps1`.
8. **Tema** — `ThemeMode.dark` forçado (marca TD).

## Migration obrigatória (SQL Editor Supabase)
Arquivo: `supabase/migrations/20260711_roles_agenda_outbox.sql`  
(cópia em `lib/supabase/20260711_roles_agenda_outbox.sql`)  
Depois: `NOTIFY pgrst, 'reload schema';`

## Arquivos-chave
- `lib/screens/book_appointment_screen.dart` — fluxo de agendamento (cliente) + envio WhatsApp
- `lib/screens/home_screen.dart` — home do cliente (lista de serviços)
- `lib/screens/admin/admin_navigation.dart` — navegação admin + tema escuro
- `lib/screens/admin/appointments_admin_screen.dart` — agenda admin
- `lib/screens/admin/agenda_dia_view.dart` — agenda do dia colorida + bloqueio + encaixe
- `lib/screens/admin/clients_admin_screen.dart` — dashboard de clientes
- `lib/screens/admin/barbers_admin_screen.dart` — CRUD barbeiros (tem `phone`)
- `lib/screens/admin/services_admin_screen.dart` — CRUD serviços
- `lib/screens/admin/remarcar_admin_screen.dart` — clientes inativos / reativação
- `lib/repositories/` — camada de dados
- `lib/router.dart` — rotas + redirect auth
- `lib/utils/admin_session.dart` — papel super-admin / barbeiro
- `lib/services/whatsapp_service.dart` — WhatsApp + outbox
- `lib/main.dart` + `lib/supabase/supabase_config.dart` — config Supabase
- `server/wa-reminder/` — script do lembrete (VPS)
- `scripts/deploy.ps1` — build web + wrangler
