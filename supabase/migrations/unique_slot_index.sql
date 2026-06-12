-- =============================================================================
-- Impede agendamento duplo no mesmo slot (mesmo barbeiro, data e horário).
-- Rodar no Supabase SQL Editor.
--
-- A verificação no app (consulta antes do insert) tem uma janela de corrida:
-- dois clientes consultando ao mesmo tempo viam o slot livre e ambos inseriam.
-- Este índice único parcial garante no banco que só um agendamento ativo
-- existe por slot — o segundo insert falha com erro 23505, que o app traduz
-- para "Este horário acabou de ser ocupado por outra pessoa."
--
-- ATENÇÃO: se este CREATE falhar com "could not create unique index", existem
-- agendamentos ativos duplicados no banco. Encontre-os com:
--
--   SELECT barber_id, appointment_date, appointment_time, count(*)
--   FROM appointments
--   WHERE status NOT IN ('cancelled', 'no_show')
--   GROUP BY 1, 2, 3 HAVING count(*) > 1;
--
-- e cancele os duplicados antes de rodar de novo.
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uniq_active_appointment_slot
  ON public.appointments (barber_id, appointment_date, appointment_time)
  WHERE status NOT IN ('cancelled', 'no_show');

NOTIFY pgrst, 'reload schema';
