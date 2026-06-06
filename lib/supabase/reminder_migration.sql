-- Lembrete automático de agendamentos via WhatsApp.
-- Adiciona a flag que evita enviar o mesmo lembrete duas vezes.
-- Rode no SQL Editor do Supabase.

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_sent boolean NOT NULL DEFAULT false;

-- (Opcional) índice para a busca do script de lembrete ficar rápida.
CREATE INDEX IF NOT EXISTS idx_appointments_reminder
  ON public.appointments (appointment_date, reminder_sent);

-- (Opcional) Template da mensagem de lembrete — você pode editar o texto.
-- Placeholders disponíveis: {{cliente}} {{data}} {{hora}} {{servico}} {{barbeiro}}
INSERT INTO public.app_settings (key, value)
VALUES (
  'wa_reminder_template',
  E'⏰ Lembrete do seu horário!\n\nOlá {{cliente}}! Seu horário é hoje às {{hora}}.\n✂️ Serviço: {{servico}}\n💈 Profissional: {{barbeiro}}\n\nTe esperamos! 👋'
)
ON CONFLICT (key) DO NOTHING;
