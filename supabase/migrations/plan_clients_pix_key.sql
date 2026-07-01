-- Chave Pix individual por cliente de plano + placeholder {{pix}} nos
-- templates de lembrete de plano (24h e 1h antes).

ALTER TABLE public.plan_clients
  ADD COLUMN IF NOT EXISTS pix_key text;

UPDATE public.app_settings
SET value = E'📅 Lembrete do seu plano!\n\nOlá {{cliente}}! Seu horário de plano é amanhã às {{hora}}.\n✂️ Serviço: {{servico}}\n💈 Profissional: {{barbeiro}}\n{{pix}}\nTe esperamos amanhã! 👋'
WHERE key = 'wa_plan_reminder_template_24h'
  AND value NOT LIKE '%{{pix}}%';

UPDATE public.app_settings
SET value = E'⏰ Quase na hora!\n\nOlá {{cliente}}! Seu horário de plano é hoje às {{hora}}.\n✂️ Serviço: {{servico}}\n💈 Profissional: {{barbeiro}}\n{{pix}}\nTe esperamos daqui a pouco! 🙌'
WHERE key = 'wa_plan_reminder_template_1h'
  AND value NOT LIKE '%{{pix}}%';

NOTIFY pgrst, 'reload schema';
