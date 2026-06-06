-- Storage setup for service photos.
-- Run this in the Supabase SQL Editor for the project used by the app:
-- https://uebvtbgvsyzbyzdilren.supabase.co

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'fotos',
    'fotos',
    true,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  ),
  (
    'service-images',
    'service-images',
    true,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  )
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Public can read service photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload service photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update service photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete service photos" ON storage.objects;
DROP POLICY IF EXISTS "App can upload service photos" ON storage.objects;
DROP POLICY IF EXISTS "App can update service photos" ON storage.objects;
DROP POLICY IF EXISTS "App can delete service photos" ON storage.objects;

CREATE POLICY "Public can read service photos"
  ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id IN ('fotos', 'service-images'));

CREATE POLICY "App can upload service photos"
  ON storage.objects
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    bucket_id = 'service-images'
    OR (
      bucket_id = 'fotos'
      AND (storage.foldername(name))[1] IN ('services', 'avatars')
    )
  );

CREATE POLICY "App can update service photos"
  ON storage.objects
  FOR UPDATE
  TO anon, authenticated
  USING (
    bucket_id = 'service-images'
    OR (
      bucket_id = 'fotos'
      AND (storage.foldername(name))[1] IN ('services', 'avatars')
    )
  )
  WITH CHECK (
    bucket_id = 'service-images'
    OR (
      bucket_id = 'fotos'
      AND (storage.foldername(name))[1] IN ('services', 'avatars')
    )
  );

CREATE POLICY "App can delete service photos"
  ON storage.objects
  FOR DELETE
  TO anon, authenticated
  USING (
    bucket_id = 'service-images'
    OR (
      bucket_id = 'fotos'
      AND (storage.foldername(name))[1] IN ('services', 'avatars')
    )
  );

-- The admin screens are a Flutter front-end using the anon key.
-- These policies allow that admin UI to save the service image_url after upload.
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can manage services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can update services" ON public.services;
DROP POLICY IF EXISTS "Authenticated users can delete services" ON public.services;
DROP POLICY IF EXISTS "App can view services" ON public.services;
DROP POLICY IF EXISTS "App can insert services" ON public.services;
DROP POLICY IF EXISTS "App can update services" ON public.services;
DROP POLICY IF EXISTS "App can delete services" ON public.services;

CREATE POLICY "App can view services"
  ON public.services
  FOR SELECT
  TO anon, authenticated
  USING (true);

CREATE POLICY "App can insert services"
  ON public.services
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

CREATE POLICY "App can update services"
  ON public.services
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "App can delete services"
  ON public.services
  FOR DELETE
  TO anon, authenticated
  USING (true);
