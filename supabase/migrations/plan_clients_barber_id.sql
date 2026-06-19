-- Vincula cada cliente plano a um barbeiro específico (nullable)
ALTER TABLE plan_clients
  ADD COLUMN IF NOT EXISTS barber_id UUID REFERENCES barbers(id) ON DELETE SET NULL;

-- Recarregar cache do PostgREST para o novo campo aparecer
NOTIFY pgrst, 'reload schema';
