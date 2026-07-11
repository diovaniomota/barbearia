-- =============================================================================
-- TD Barbearia — roles, agenda (source/created_by), blocked slots, WA outbox
-- Rode no SQL Editor do Supabase (projeto ativo). Depois:
--   NOTIFY pgrst, 'reload schema';
-- =============================================================================

-- ── users.role / is_admin ────────────────────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS role text DEFAULT 'client';

-- Promote existing staff: anyone already in public.users is treated as admin
-- (clients book as anon / without login in this app).
UPDATE public.users
SET is_admin = true,
    role = CASE
      WHEN role IS NULL OR role = '' OR role = 'client' THEN 'admin'
      ELSE role
    END
WHERE COALESCE(is_admin, false) = false;

-- Barbeiros linkados: role barber (ainda acessam o painel)
UPDATE public.users u
SET role = 'barber',
    is_admin = true
WHERE EXISTS (
  SELECT 1 FROM public.barbers b WHERE b.user_id = u.id
);

-- ── appointments.source / created_by ─────────────────────────────────────────
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS source text DEFAULT 'client';

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS customer_name text;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS customer_phone text;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS is_plan_client boolean DEFAULT false;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_sent boolean DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'appointments_source_check'
  ) THEN
    ALTER TABLE public.appointments
      ADD CONSTRAINT appointments_source_check
      CHECK (source IS NULL OR source IN ('client', 'admin', 'recurring', 'walk_in'));
  END IF;
EXCEPTION WHEN others THEN
  NULL; -- ignore if table/constraint edge cases
END $$;

CREATE INDEX IF NOT EXISTS idx_appointments_source
  ON public.appointments(source);

CREATE INDEX IF NOT EXISTS idx_appointments_customer_phone
  ON public.appointments(customer_phone);

-- ── barbers.user_id / phone ──────────────────────────────────────────────────
ALTER TABLE public.barbers
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.barbers
  ADD COLUMN IF NOT EXISTS phone text;

CREATE INDEX IF NOT EXISTS idx_barbers_user_id ON public.barbers(user_id);

-- ── blocked_slots ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.blocked_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id uuid NOT NULL REFERENCES public.barbers(id) ON DELETE CASCADE,
  date date NOT NULL,
  time time NOT NULL,
  reason text,
  created_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE (barber_id, date, time)
);

CREATE INDEX IF NOT EXISTS idx_blocked_slots_barber_date
  ON public.blocked_slots(barber_id, date);

-- ── barber_blocked_days ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.barber_blocked_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id uuid NOT NULL REFERENCES public.barbers(id) ON DELETE CASCADE,
  date_from date NOT NULL,
  date_to date NOT NULL,
  reason text,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_barber_blocked_days_barber
  ON public.barber_blocked_days(barber_id, date_from, date_to);

-- ── extra_slots ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.extra_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  barber_id uuid NOT NULL REFERENCES public.barbers(id) ON DELETE CASCADE,
  slot_date date NOT NULL,
  slot_time time NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE (barber_id, slot_date, slot_time)
);

-- ── whatsapp_outbox (log + retry) ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whatsapp_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone text NOT NULL,
  message text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed')),
  error text,
  attempts int NOT NULL DEFAULT 0,
  last_attempt_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_outbox_status
  ON public.whatsapp_outbox(status, created_at DESC);

-- ── helper: is staff (admin or linked barber) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid()
      AND COALESCE(u.is_admin, false) = true
  )
  OR EXISTS (
    SELECT 1 FROM public.barbers b
    WHERE b.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid()
      AND COALESCE(u.is_admin, false) = true
      AND NOT EXISTS (
        SELECT 1 FROM public.barbers b WHERE b.user_id = auth.uid()
      )
  );
$$;

-- ── RLS: blocked_slots ───────────────────────────────────────────────────────
ALTER TABLE public.blocked_slots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS blocked_slots_select ON public.blocked_slots;
CREATE POLICY blocked_slots_select ON public.blocked_slots
  FOR SELECT USING (true);

DROP POLICY IF EXISTS blocked_slots_staff_write ON public.blocked_slots;
CREATE POLICY blocked_slots_staff_write ON public.blocked_slots
  FOR ALL
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- ── RLS: barber_blocked_days ─────────────────────────────────────────────────
ALTER TABLE public.barber_blocked_days ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS barber_blocked_days_select ON public.barber_blocked_days;
CREATE POLICY barber_blocked_days_select ON public.barber_blocked_days
  FOR SELECT USING (true);

DROP POLICY IF EXISTS barber_blocked_days_staff_write ON public.barber_blocked_days;
CREATE POLICY barber_blocked_days_staff_write ON public.barber_blocked_days
  FOR ALL
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- ── RLS: extra_slots ─────────────────────────────────────────────────────────
ALTER TABLE public.extra_slots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS extra_slots_select ON public.extra_slots;
CREATE POLICY extra_slots_select ON public.extra_slots
  FOR SELECT USING (true);

DROP POLICY IF EXISTS extra_slots_staff_write ON public.extra_slots;
CREATE POLICY extra_slots_staff_write ON public.extra_slots
  FOR ALL
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- ── RLS: whatsapp_outbox (só staff) ──────────────────────────────────────────
ALTER TABLE public.whatsapp_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_outbox_staff ON public.whatsapp_outbox;
CREATE POLICY whatsapp_outbox_staff ON public.whatsapp_outbox
  FOR ALL
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

-- ── Realtime (agenda admin) ──────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.appointments;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.blocked_slots;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.extra_slots;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

NOTIFY pgrst, 'reload schema';
