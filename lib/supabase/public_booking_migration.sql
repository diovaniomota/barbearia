-- Allow customers to book without any login.
-- Run this once in Supabase SQL Editor.

ALTER TABLE public.appointments
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS customer_phone text;

ALTER TABLE public.appointments
  DROP CONSTRAINT IF EXISTS appointments_customer_name_required,
  ADD CONSTRAINT appointments_customer_name_required
    CHECK (user_id IS NOT NULL OR NULLIF(trim(customer_name), '') IS NOT NULL);

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can create their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can update their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can delete their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Public can view booked slots" ON public.appointments;
DROP POLICY IF EXISTS "Public can create customer appointments" ON public.appointments;
DROP POLICY IF EXISTS "Admins can manage appointments" ON public.appointments;

CREATE POLICY "Public can view booked slots" ON public.appointments
  FOR SELECT
  USING (true);

CREATE POLICY "Public can create customer appointments" ON public.appointments
  FOR INSERT
  WITH CHECK (
    user_id IS NULL
    AND NULLIF(trim(customer_name), '') IS NOT NULL
    AND NULLIF(trim(customer_phone), '') IS NOT NULL
    AND status = 'scheduled'
  );

CREATE POLICY "Admins can manage appointments" ON public.appointments
  FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
