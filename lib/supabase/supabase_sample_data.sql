-- Sample Data for Barbershop App

-- Helper function to insert users into auth.users and return their UUID
CREATE OR REPLACE FUNCTION insert_user_to_auth(user_email text, user_password text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    user_id uuid;
BEGIN
    -- Insert into auth.users
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_sso_user, phone_confirmed_at)
    VALUES (
        '00000000-0000-0000-0000-000000000000', -- Placeholder for instance_id
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        user_email,
        crypt(user_password, gen_salt('bf')),
        now(),
        now(),
        now(),
        now(),
        '{"provider": "email", "providers": ["email"]}',
        '{}',
        false,
        now()
    )
    RETURNING id INTO user_id;

    RETURN user_id;
END;
$$;

-- 1. Insert users into auth.users and then public.users
INSERT INTO public.users (id, name, email, phone, avatar_url)
SELECT insert_user_to_auth('john.doe@example.com', 'password123'), 'John Doe', 'john.doe@example.com', '555-111-2222', 'https://example.com/avatars/john.jpg'
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'john.doe@example.com');

INSERT INTO public.users (id, name, email, phone, avatar_url)
SELECT insert_user_to_auth('jane.smith@example.com', 'password123'), 'Jane Smith', 'jane.smith@example.com', '555-333-4444', 'https://example.com/avatars/jane.jpg'
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'jane.smith@example.com');

INSERT INTO public.users (id, name, email, phone, avatar_url)
SELECT insert_user_to_auth('barber.mike@example.com', 'password123'), 'Mike Barber', 'barber.mike@example.com', '555-555-6666', 'https://example.com/avatars/mike.jpg'
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'barber.mike@example.com');

INSERT INTO public.users (id, name, email, phone, avatar_url)
SELECT insert_user_to_auth('barber.lisa@example.com', 'password123'), 'Lisa Barber', 'barber.lisa@example.com', '555-777-8888', 'https://example.com/avatars/lisa.jpg'
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'barber.lisa@example.com');

-- 2. Insert Barbers
INSERT INTO public.barbers (name, email, phone, image_url, bio, specialties, rating, years_experience, is_available) VALUES
('Mike Johnson', 'mike.johnson@barbershop.com', '555-101-2020', 'https://example.com/barbers/mike.jpg', 'Experienced barber specializing in classic cuts and modern styles.', ARRAY['Haircut', 'Beard Trim', 'Shave'], 4.9, 10, TRUE),
('Lisa Davis', 'lisa.davis@barbershop.com', '555-303-4040', 'https://example.com/barbers/lisa.jpg', 'Passionate about creating unique looks and providing a relaxing experience.', ARRAY['Haircut', 'Coloring', 'Styling'], 4.8, 7, TRUE),
('Chris Evans', 'chris.evans@barbershop.com', '555-505-6060', 'https://example.com/barbers/chris.jpg', 'Master of fades and intricate designs. Always up-to-date with the latest trends.', ARRAY['Fade', 'Hair Tattoo', 'Kids Cut'], 5.0, 12, TRUE);

-- 3. Insert Services
INSERT INTO public.services (name, description, price, duration_minutes, image_url, category, is_active) VALUES
('Men''s Haircut', 'Classic haircut for men, includes wash and style.', 30.00, 45, 'https://example.com/services/mens_cut.jpg', 'Hair', TRUE),
('Beard Trim', 'Professional beard shaping and trimming.', 15.00, 20, 'https://example.com/services/beard_trim.jpg', 'Beard', TRUE),
('Hot Towel Shave', 'Traditional hot towel shave for a smooth finish.', 40.00, 60, 'https://example.com/services/hot_shave.jpg', 'Shave', TRUE),
('Kids Haircut', 'Haircut for children under 12.', 20.00, 30, 'https://example.com/services/kids_cut.jpg', 'Hair', TRUE),
('Hair Coloring', 'Full hair coloring service.', 80.00, 120, 'https://example.com/services/coloring.jpg', 'Hair', TRUE);

-- 4. Insert Appointments
INSERT INTO public.appointments (user_id, barber_id, service_id, appointment_date, appointment_time, status, notes, total_price)
SELECT
    (SELECT id FROM public.users WHERE email = 'john.doe@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Mike Johnson'),
    (SELECT id FROM public.services WHERE name = 'Men''s Haircut'),
    '2024-07-20', '10:00:00', 'scheduled', 'First time client, looking for a classic cut.', 30.00
WHERE NOT EXISTS (
    SELECT 1 FROM public.appointments
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
    AND service_id = (SELECT id FROM public.services WHERE name = 'Men''s Haircut')
    AND appointment_date = '2024-07-20'
    AND appointment_time = '10:00:00'
);

INSERT INTO public.appointments (user_id, barber_id, service_id, appointment_date, appointment_time, status, notes, total_price)
SELECT
    (SELECT id FROM public.users WHERE email = 'jane.smith@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Lisa Davis'),
    (SELECT id FROM public.services WHERE name = 'Hair Coloring'),
    '2024-07-21', '14:30:00', 'confirmed', 'Looking for a balayage.', 80.00
WHERE NOT EXISTS (
    SELECT 1 FROM public.appointments
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'jane.smith@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Lisa Davis')
    AND service_id = (SELECT id FROM public.services WHERE name = 'Hair Coloring')
    AND appointment_date = '2024-07-21'
    AND appointment_time = '14:30:00'
);

INSERT INTO public.appointments (user_id, barber_id, service_id, appointment_date, appointment_time, status, notes, total_price)
SELECT
    (SELECT id FROM public.users WHERE email = 'john.doe@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Chris Evans'),
    (SELECT id FROM public.services WHERE name = 'Beard Trim'),
    '2024-07-22', '11:00:00', 'completed', 'Quick trim, very satisfied.', 15.00
WHERE NOT EXISTS (
    SELECT 1 FROM public.appointments
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Chris Evans')
    AND service_id = (SELECT id FROM public.services WHERE name = 'Beard Trim')
    AND appointment_date = '2024-07-22'
    AND appointment_time = '11:00:00'
);

-- 5. Insert Barber Availability
INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
SELECT (SELECT id FROM public.barbers WHERE name = 'Mike Johnson'), 1, '09:00:00', '17:00:00', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM public.barber_availability
    WHERE barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
    AND day_of_week = 1
);

INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
SELECT (SELECT id FROM public.barbers WHERE name = 'Mike Johnson'), 2, '09:00:00', '17:00:00', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM public.barber_availability
    WHERE barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
    AND day_of_week = 2
);

INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
SELECT (SELECT id FROM public.barbers WHERE name = 'Lisa Davis'), 3, '10:00:00', '18:00:00', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM public.barber_availability
    WHERE barber_id = (SELECT id FROM public.barbers WHERE name = 'Lisa Davis')
    AND day_of_week = 3
);

INSERT INTO public.barber_availability (barber_id, day_of_week, start_time, end_time, is_available)
SELECT (SELECT id FROM public.barbers WHERE name = 'Chris Evans'), 4, '08:00:00', '16:00:00', TRUE
WHERE NOT EXISTS (
    SELECT 1 FROM public.barber_availability
    WHERE barber_id = (SELECT id FROM public.barbers WHERE name = 'Chris Evans')
    AND day_of_week = 4
);

-- 6. Insert Reviews
INSERT INTO public.reviews (user_id, barber_id, appointment_id, rating, comment)
SELECT
    (SELECT id FROM public.users WHERE email = 'john.doe@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Mike Johnson'),
    (SELECT id FROM public.appointments
     WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
     AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
     AND appointment_date = '2024-07-20' AND appointment_time = '10:00:00'),
    5, 'Mike gave me the best haircut I''ve had in years! Highly recommend.'
WHERE NOT EXISTS (
    SELECT 1 FROM public.reviews
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
    AND appointment_id = (SELECT id FROM public.appointments
                          WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
                          AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Mike Johnson')
                          AND appointment_date = '2024-07-20' AND appointment_time = '10:00:00')
);

INSERT INTO public.reviews (user_id, barber_id, appointment_id, rating, comment)
SELECT
    (SELECT id FROM public.users WHERE email = 'jane.smith@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Lisa Davis'),
    (SELECT id FROM public.appointments
     WHERE user_id = (SELECT id FROM public.users WHERE email = 'jane.smith@example.com')
     AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Lisa Davis')
     AND appointment_date = '2024-07-21' AND appointment_time = '14:30:00'),
    4, 'Lisa did a great job with my hair color. Very friendly and professional.'
WHERE NOT EXISTS (
    SELECT 1 FROM public.reviews
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'jane.smith@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Lisa Davis')
    AND appointment_id = (SELECT id FROM public.appointments
                          WHERE user_id = (SELECT id FROM public.users WHERE email = 'jane.smith@example.com')
                          AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Lisa Davis')
                          AND appointment_date = '2024-07-21' AND appointment_time = '14:30:00')
);

INSERT INTO public.reviews (user_id, barber_id, appointment_id, rating, comment)
SELECT
    (SELECT id FROM public.users WHERE email = 'john.doe@example.com'),
    (SELECT id FROM public.barbers WHERE name = 'Chris Evans'),
    (SELECT id FROM public.appointments
     WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
     AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Chris Evans')
     AND appointment_date = '2024-07-22' AND appointment_time = '11:00:00'),
    5, 'Chris is a master of beard trims. Quick and precise!'
WHERE NOT EXISTS (
    SELECT 1 FROM public.reviews
    WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
    AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Chris Evans')
    AND appointment_id = (SELECT id FROM public.appointments
                          WHERE user_id = (SELECT id FROM public.users WHERE email = 'john.doe@example.com')
                          AND barber_id = (SELECT id FROM public.barbers WHERE name = 'Chris Evans')
                          AND appointment_date = '2024-07-22' AND appointment_time = '11:00:00')
);

-- Clean up the helper function
DROP FUNCTION IF EXISTS insert_user_to_auth(text, text);