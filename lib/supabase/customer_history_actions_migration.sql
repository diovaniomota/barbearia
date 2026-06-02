-- Customer history helpers.
-- Run this once in Supabase SQL Editor after public_booking_migration.sql.

CREATE OR REPLACE FUNCTION public._normalize_phone(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(coalesce(value, ''), '\D', '', 'g');
$$;

CREATE OR REPLACE FUNCTION public.set_customer_appointment_status(
  p_appointment_id uuid,
  p_phone text,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count integer;
BEGIN
  IF p_status NOT IN ('confirmed', 'cancelled') THEN
    RAISE EXCEPTION 'Invalid appointment status: %', p_status;
  END IF;

  UPDATE public.appointments
     SET status = p_status,
         updated_at = now()
   WHERE id = p_appointment_id
     AND public._normalize_phone(customer_phone) = public._normalize_phone(p_phone)
     AND status IN ('scheduled', 'pending', 'confirmed');

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  IF updated_count = 0 THEN
    RAISE EXCEPTION 'Appointment not found for this phone';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_customer_appointment_status(uuid, text, text)
TO anon, authenticated;
