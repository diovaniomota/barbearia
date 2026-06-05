-- Tabela de clientes que pagam plano mensal
CREATE TABLE IF NOT EXISTS public.plan_clients (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  phone      text NOT NULL,           -- armazenado apenas dígitos (ex: 11987654321)
  plan_name  text,
  notes      text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_plan_clients_phone
  ON public.plan_clients(phone);

-- RLS: permite operações para usuários autenticados (admin)
ALTER TABLE public.plan_clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plan_clients_all" ON public.plan_clients
  FOR ALL USING (true) WITH CHECK (true);

-- Coluna na tabela de agendamentos para marcar clientes plano
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS is_plan_client boolean DEFAULT false;
