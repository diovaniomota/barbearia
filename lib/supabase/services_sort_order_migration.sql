-- ============================================================================
-- Ordenação manual dos serviços (arrastar para reordenar no admin).
-- Rode este script no Supabase → SQL Editor do projeto uebvtbgvsyzbyzdilren.
-- É seguro rodar mais de uma vez (idempotente).
-- ============================================================================

-- 1. Cria a coluna de ordem (se ainda não existir).
alter table public.services
  add column if not exists sort_order integer not null default 0;

-- 2. Backfill: define a ordem inicial pela ordem alfabética atual (por nome).
--    Assim os serviços já existentes começam numa ordem previsível.
with ranked as (
  select id, (row_number() over (order by name) - 1) as rn
  from public.services
)
update public.services s
set sort_order = ranked.rn
from ranked
where s.id = ranked.id;

-- 3. Índice para acelerar a ordenação.
create index if not exists services_sort_order_idx
  on public.services (sort_order);

-- 4. Recarrega o cache de schema do PostgREST (senão o novo campo é
--    ignorado nas gravações até reiniciar o projeto).
notify pgrst, 'reload schema';
