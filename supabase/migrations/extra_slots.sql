-- =============================================================================
-- Horários extras avulsos: o barbeiro abre um horário fora da escala semanal
-- para um dia específico, e ele fica disponível para o cliente agendar.
-- Rodar no Supabase SQL Editor.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.extra_slots (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  barber_id   uuid        NOT NULL REFERENCES public.barbers(id) ON DELETE CASCADE,
  slot_date   date        NOT NULL,
  slot_time   time        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (barber_id, slot_date, slot_time)
);

CREATE INDEX IF NOT EXISTS idx_extra_slots_barber_date
  ON public.extra_slots (barber_id, slot_date);

ALTER TABLE public.extra_slots ENABLE ROW LEVEL SECURITY;

-- Leitura pública: o cliente (anon) precisa ver o horário extra para agendar.
CREATE POLICY "extra_slots_public_read" ON public.extra_slots
  FOR SELECT USING (true);

-- Escrita só para admins autenticados.
CREATE POLICY "extra_slots_admin_all" ON public.extra_slots
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
