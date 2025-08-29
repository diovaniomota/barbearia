-- Barbershop App Row Level Security Policies - Safe Migration
-- This file contains all security policies for the barbershop appointment system
-- Uses safe policy creation to avoid conflicts

-- Enable Row Level Security on all tables (safe)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barbers') THEN
        ALTER TABLE public.barbers ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'services') THEN
        ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
        ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barber_availability') THEN
        ALTER TABLE public.barber_availability ENABLE ROW LEVEL SECURITY;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reviews') THEN
        ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
    END IF;
END$$;

-- Users table policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Users can view their own profile" ON public.users;
        DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
        DROP POLICY IF EXISTS "Users can insert their own profile" ON public.users;
        DROP POLICY IF EXISTS "Users can delete their own profile" ON public.users;
        
        -- Create new policies
        CREATE POLICY "Users can view their own profile" ON public.users
            FOR SELECT USING (auth.uid() = id);

        CREATE POLICY "Users can update their own profile" ON public.users
            FOR UPDATE USING (auth.uid() = id);

        CREATE POLICY "Users can insert their own profile" ON public.users
            FOR INSERT WITH CHECK (true);

        CREATE POLICY "Users can delete their own profile" ON public.users
            FOR DELETE USING (auth.uid() = id);
    END IF;
END$$;

-- Barbers table policies (publicly readable, admin managed)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barbers') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Anyone can view barbers" ON public.barbers;
        DROP POLICY IF EXISTS "Authenticated users can manage barbers" ON public.barbers;
        DROP POLICY IF EXISTS "Authenticated users can update barbers" ON public.barbers;
        DROP POLICY IF EXISTS "Authenticated users can delete barbers" ON public.barbers;
        
        -- Create new policies
        CREATE POLICY "Anyone can view barbers" ON public.barbers
            FOR SELECT USING (true);

        CREATE POLICY "Authenticated users can manage barbers" ON public.barbers
            FOR INSERT WITH CHECK (true);

        CREATE POLICY "Authenticated users can update barbers" ON public.barbers
            FOR UPDATE USING (true);

        CREATE POLICY "Authenticated users can delete barbers" ON public.barbers
            FOR DELETE USING (true);
    END IF;
END$$;

-- Services table policies (publicly readable, admin managed)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'services') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Anyone can view services" ON public.services;
        DROP POLICY IF EXISTS "Authenticated users can manage services" ON public.services;
        DROP POLICY IF EXISTS "Authenticated users can update services" ON public.services;
        DROP POLICY IF EXISTS "Authenticated users can delete services" ON public.services;
        
        -- Create new policies
        CREATE POLICY "Anyone can view services" ON public.services
            FOR SELECT USING (true);

        CREATE POLICY "Authenticated users can manage services" ON public.services
            FOR INSERT WITH CHECK (true);

        CREATE POLICY "Authenticated users can update services" ON public.services
            FOR UPDATE USING (true);

        CREATE POLICY "Authenticated users can delete services" ON public.services
            FOR DELETE USING (true);
    END IF;
END$$;

-- Appointments table policies (users can manage their own appointments)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'appointments') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Users can view their own appointments" ON public.appointments;
        DROP POLICY IF EXISTS "Users can create their own appointments" ON public.appointments;
        DROP POLICY IF EXISTS "Users can update their own appointments" ON public.appointments;
        DROP POLICY IF EXISTS "Users can delete their own appointments" ON public.appointments;
        
        -- Create new policies
        CREATE POLICY "Users can view their own appointments" ON public.appointments
            FOR SELECT USING (auth.uid() = user_id);

        CREATE POLICY "Users can create their own appointments" ON public.appointments
            FOR INSERT WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Users can update their own appointments" ON public.appointments
            FOR UPDATE USING (auth.uid() = user_id);

        CREATE POLICY "Users can delete their own appointments" ON public.appointments
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END$$;

-- Barber availability table policies (publicly readable for booking, admin managed)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'barber_availability') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Anyone can view barber availability" ON public.barber_availability;
        DROP POLICY IF EXISTS "Authenticated users can manage availability" ON public.barber_availability;
        DROP POLICY IF EXISTS "Authenticated users can update availability" ON public.barber_availability;
        DROP POLICY IF EXISTS "Authenticated users can delete availability" ON public.barber_availability;
        
        -- Create new policies
        CREATE POLICY "Anyone can view barber availability" ON public.barber_availability
            FOR SELECT USING (true);

        CREATE POLICY "Authenticated users can manage availability" ON public.barber_availability
            FOR INSERT WITH CHECK (true);

        CREATE POLICY "Authenticated users can update availability" ON public.barber_availability
            FOR UPDATE USING (true);

        CREATE POLICY "Authenticated users can delete availability" ON public.barber_availability
            FOR DELETE USING (true);
    END IF;
END$$;

-- Reviews table policies (users can manage their own reviews)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reviews') THEN
        -- Drop existing policies first to avoid conflicts
        DROP POLICY IF EXISTS "Anyone can view reviews" ON public.reviews;
        DROP POLICY IF EXISTS "Users can create their own reviews" ON public.reviews;
        DROP POLICY IF EXISTS "Users can update their own reviews" ON public.reviews;
        DROP POLICY IF EXISTS "Users can delete their own reviews" ON public.reviews;
        
        -- Create new policies
        CREATE POLICY "Anyone can view reviews" ON public.reviews
            FOR SELECT USING (true);

        CREATE POLICY "Users can create their own reviews" ON public.reviews
            FOR INSERT WITH CHECK (auth.uid() = user_id);

        CREATE POLICY "Users can update their own reviews" ON public.reviews
            FOR UPDATE USING (auth.uid() = user_id);

        CREATE POLICY "Users can delete their own reviews" ON public.reviews
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END$$;