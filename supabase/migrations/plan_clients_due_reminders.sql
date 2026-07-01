-- Lembrete de vencimento da mensalidade do plano (separado do lembrete de
-- agendamento): 1 semana antes do dia de vencimento (due_day) e no próprio dia.

ALTER TABLE public.plan_clients
  ADD COLUMN IF NOT EXISTS plan_week_reminder_sent_for date,
  ADD COLUMN IF NOT EXISTS plan_due_reminder_sent_for date;

INSERT INTO public.app_settings (key, value) VALUES
  ('wa_plan_due_week_template',
   E'⏳ Resta uma semana para o vencimento do seu plano {{plano}}, {{cliente}}!\n\nBarbearia Toni Dinis 💈'),
  ('wa_plan_due_today_template',
   E'📌 Olá {{cliente}}! Seu plano {{plano}} na Barbearia Toni Dinis venceu hoje.\n{{pix}}\nObrigado pela confiança! 💈')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
