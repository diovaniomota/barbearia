-- Supabase Database Reset Script
-- Use this script to clean up the database if you need to start fresh
-- WARNING: This will delete ALL data in the barbershop tables

-- Drop all policies first to avoid dependency issues
DROP POLICY IF EXISTS "Users can view their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can delete their own profile" ON public.users;

DROP POLICY IF EXISTS "Anyone can view barbers" ON public.barbers;
DROP POLICY IF EXISTS "Authenticated users can manage barbers" ON public.barbers;
DROP POLICY IF EXISTS "Authenticated users can update barbers" ON public.barbers;
DROP POLICY IF EXISTS "Authenticated users can delete barbers" ON public.barbers;

DROP POLICY IF EXISTS "Anyone can view services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can manage services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can update services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can delete services" ON public.services;

DROP POLICY IF EXISTS "Users can view their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can create their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can update their own appointments" ON public.appointments;
DROP POLICY IF EXISTS "Users can delete their own appointments" ON public.appointments;

DROP POLICY IF EXISTS "Anyone can view barber availability" ON public.barber_availability;
DROP POLICY IF EXISTS "Authenticated users can manage availability" ON public.barber_availability;
DROP POLICY IF EXISTS "Authenticated users can update availability" ON public.barber_availability;
DROP POLICY IF EXISTS "Authenticated users can delete availability" ON public.barber_availability;

DROP POLICY IF EXISTS "Anyone can view reviews" ON public.reviews;
DROP POLICY IF EXISTS "Users can create their own reviews" ON public.reviews;
DROP POLICY IF EXISTS "Users can update their own reviews" ON public.reviews;
DROP POLICY IF EXISTS "Users can delete their own reviews" ON public.reviews;

-- Drop triggers
DROP TRIGGER IF EXISTS handle_updated_at ON public.users;
DROP TRIGGER IF EXISTS handle_updated_at ON public.barbers;
DROP TRIGGER IF EXISTS handle_updated_at ON public.services;
DROP TRIGGER IF EXISTS handle_updated_at ON public.appointments;
DROP TRIGGER IF EXISTS handle_updated_at ON public.barber_availability;
DROP TRIGGER IF EXISTS handle_updated_at ON public.reviews;

-- Drop tables in correct order (dependencies first)
DROP TABLE IF EXISTS public.reviews CASCADE;
DROP TABLE IF EXISTS public.appointments CASCADE;
DROP TABLE IF EXISTS public.barber_availability CASCADE;
DROP TABLE IF EXISTS public.services CASCADE;
DROP TABLE IF EXISTS public.barbers CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_updated_at() CASCADE;