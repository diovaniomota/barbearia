-- =============================================================================
-- Agendamentos recorrentes (clientes do plano) + lembretes configuráveis
-- Rodar no Supabase SQL Editor
-- =============================================================================

-- 1. Tabela de schedules recorrentes -------------------------------------------
CREATE TABLE IF NOT EXISTS public.recurring_schedules (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  plan_client_id  uuid        NOT NULL REFERENCES public.plan_clients(id) ON DELETE CASCADE,
  barber_id       uuid        NOT NULL REFERENCES public.barbers(id)      ON DELETE CASCADE,
  service_id      uuid        REFERENCES public.services(id)              ON DELETE SET NULL,
  day_of_week     smallint    NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=dom … 6=sáb
  appointment_time time       NOT NULL,
  is_active       boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.recurring_schedules ENABLE ROW LEVEL SECURITY;

-- Admins autenticados podem gerenciar
CREATE POLICY "authenticated_all" ON public.recurring_schedules
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2. Coluna de lembrete de 24h nos agendamentos --------------------------------
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_24h_sent boolean NOT NULL DEFAULT false;

-- 3. Configurações de lembretes em app_settings --------------------------------
-- Só insere se a chave ainda não existir
INSERT INTO public.app_settings (key, value) VALUES
  ('reminder_normal_hours', '1'),
  ('wa_plan_reminder_template_24h',
   E'📅 Lembrete do seu plano!\n\nOlá {{cliente}}! Seu horário é amanhã às {{hora}}.\n✂️ Serviço: {{servico}}\n💈 Profissional: {{barbeiro}}\n\nTe esperamos amanhã! 👋'),
  ('wa_plan_reminder_template_1h',
   E'⏰ Quase na hora!\n\nOlá {{cliente}}! Seu horário de plano é hoje às {{hora}}.\n✂️ Serviço: {{servico}}\n💈 Profissional: {{barbeiro}}\n\nTe esperamos daqui a pouco! 🙌')
ON CONFLICT (key) DO NOTHING;

-- 4. Avisar o PostgREST sobre a nova tabela / coluna ---------------------------
NOTIFY pgrst, 'reload schema';
