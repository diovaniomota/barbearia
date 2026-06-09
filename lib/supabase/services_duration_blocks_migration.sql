-- Adiciona duração em blocos de 30 min para cada serviço.
-- Rode no Supabase SQL Editor do projeto uebvtbgvsyzbyzdilren.
-- Seguro rodar mais de uma vez (idempotente).

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS duration_blocks integer NOT NULL DEFAULT 1
    CHECK (duration_blocks BETWEEN 1 AND 6);

-- Força o PostgREST a recarregar o schema
NOTIFY pgrst, 'reload schema';
