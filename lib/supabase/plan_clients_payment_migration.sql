-- Adiciona forma de pagamento e dia de vencimento nos clientes plano.
-- Rode no Supabase SQL Editor do projeto uebvtbgvsyzbyzdilren.
-- Seguro rodar mais de uma vez (idempotente).

ALTER TABLE public.plan_clients
  ADD COLUMN IF NOT EXISTS payment_method text,
  ADD COLUMN IF NOT EXISTS due_day        integer CHECK (due_day BETWEEN 1 AND 31);
