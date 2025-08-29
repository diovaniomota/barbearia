-- Fixed Sample Data for Barbershop App
-- This file safely inserts sample data that works with the corrected schema

-- 1. Insert Barbers (safe - no dependencies on users table)
INSERT INTO public.barbers (name, email, phone, image_url, bio, specialties, rating, years_experience, is_available) 
SELECT 'Mike Johnson', 'mike.johnson@barbershop.com', '555-101-2020', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300&h=300&fit=crop', 'Experienced barber specializing in classic cuts and modern styles.', ARRAY['Haircut', 'Beard Trim', 'Shave'], 4.9, 10, TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.barbers WHERE email = 'mike.johnson@barbershop.com');

INSERT INTO public.barbers (name, email, phone, image_url, bio, specialties, rating, years_experience, is_available)
SELECT 'Lisa Davis', 'lisa.davis@barbershop.com', '555-303-4040', 'https://images.unsplash.com/photo-1494790108755-2616b332c81c?w=300&h=300&fit=crop', 'Passionate about creating unique looks and providing a relaxing experience.', ARRAY['Haircut', 'Coloring', 'Styling'], 4.8, 7, TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.barbers WHERE email = 'lisa.davis@barbershop.com');

INSERT INTO public.barbers (name, email, phone, image_url, bio, specialties, rating, years_experience, is_available)
SELECT 'Chris Evans', 'chris.evans@barbershop.com', '555-505-6060', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&h=300&fit=crop', 'Master of fades and intricate designs. Always up-to-date with the latest trends.', ARRAY['Fade', 'Hair Tattoo', 'Kids Cut'], 5.0, 12, TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.barbers WHERE email = 'chris.evans@barbershop.com');

-- 2. Insert Services (ensuring all columns are properly specified)
INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active)
SELECT 'Men''s Haircut', 'Classic haircut for men, includes wash and style.', 30.00, 45, 'https://images.unsplash.com/photo-1622296147272-ffefd1e2e3c3?w=400&h=300&fit=crop', 'Hair', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Men''s Haircut');

INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active)
SELECT 'Beard Trim', 'Professional beard shaping and trimming.', 15.00, 20, 'https://images.unsplash.com/photo-1621605815971-fbc98d665033?w=400&h=300&fit=crop', 'Beard', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Beard Trim');

INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active)
SELECT 'Hot Towel Shave', 'Traditional hot towel shave for a smooth finish.', 40.00, 60, 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=400&h=300&fit=crop', 'Shave', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Hot Towel Shave');

INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active)
SELECT 'Kids Haircut', 'Haircut for children under 12.', 20.00, 30, 'https://images.unsplash.com/photo-1622240506921-042ba2c08e5b?w=400&h=300&fit=crop', 'Hair', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Kids Haircut');

INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active)
SELECT 'Hair Coloring', 'Full hair coloring service.', 80.00, 120, 'https://images.unsplash.com/photo-1560066984-138dadb4c035?w=400&h=300&fit=crop', 'Hair', TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Hair Coloring');

-- 3. Insert Barber Availability (comprehensive schedules)

-- Mike Johnson availability (Monday-Friday)
DO $$
DECLARE
    mike_id uuid;
    day_num integer;
BEGIN
    SELECT id INTO mike_id FROM public.barbers WHERE email = 'mike.johnson@barbershop.com';
    
    IF mike_id IS NOT NULL THEN
        FOR day_num IN 1..5 LOOP
            INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
            SELECT mike_id, day_num, '09:00:00', '17:00:00', TRUE
            WHERE NOT EXISTS (
                SELECT 1 FROM public.barber_availability
                WHERE barber_id = mike_id AND day_of_week = day_num
            );
        END LOOP;
    END IF;
END$$;

-- Lisa Davis availability (Tuesday-Saturday)  
DO $$
DECLARE
    lisa_id uuid;
    day_num integer;
BEGIN
    SELECT id INTO lisa_id FROM public.barbers WHERE email = 'lisa.davis@barbershop.com';
    
    IF lisa_id IS NOT NULL THEN
        FOR day_num IN 2..6 LOOP
            INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
            SELECT lisa_id, day_num, '10:00:00', '18:00:00', TRUE
            WHERE NOT EXISTS (
                SELECT 1 FROM public.barber_availability
                WHERE barber_id = lisa_id AND day_of_week = day_num
            );
        END LOOP;
    END IF;
END$$;

-- Chris Evans availability (Wednesday-Sunday)
DO $$
DECLARE
    chris_id uuid;
    day_num integer;
BEGIN
    SELECT id INTO chris_id FROM public.barbers WHERE email = 'chris.evans@barbershop.com';
    
    IF chris_id IS NOT NULL THEN
        FOR day_num IN 3..6 LOOP
            INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
            SELECT chris_id, day_num, '08:00:00', '16:00:00', TRUE
            WHERE NOT EXISTS (
                SELECT 1 FROM public.barber_availability
                WHERE barber_id = chris_id AND day_of_week = day_num
            );
        END LOOP;
        
        -- Sunday availability (shorter hours)
        INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
        SELECT chris_id, 0, '10:00:00', '14:00:00', TRUE
        WHERE NOT EXISTS (
            SELECT 1 FROM public.barber_availability
            WHERE barber_id = chris_id AND day_of_week = 0
        );
    END IF;
END$$;