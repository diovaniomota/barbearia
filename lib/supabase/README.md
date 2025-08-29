# Supabase Database Setup for Barbershop App

This directory contains all the necessary SQL files to set up the Supabase database for the barbershop appointment system.

## Files Overview

### Original Files
- `supabase_tables.sql` - Database schema with all tables, indexes, and triggers
- `supabase_policies.sql` - Row Level Security (RLS) policies
- `supabase_sample_data.sql` - Sample data for testing
- `supabase_config.dart` - Dart configuration for Supabase client

### Safe Migration Files (Recommended)
- `supabase_tables_safe.sql` - Safe database schema that avoids conflicts
- `supabase_policies_safe.sql` - Safe RLS policies with conflict resolution
- `supabase_sample_data_safe.sql` - Safe sample data insertion
- `supabase_reset.sql` - Database reset script for cleanup

## Migration Error Fix

If you're experiencing migration errors with existing tables, use the **Safe Migration Files**:

### Quick Fix Setup

1. **Reset Database (if needed)**: Run `supabase_reset.sql` in your Supabase SQL editor to clean up
2. **Create Tables Safely**: Run `supabase_tables_safe.sql`
3. **Apply Security Safely**: Run `supabase_policies_safe.sql` 
4. **Add Sample Data Safely**: Run `supabase_sample_data_safe.sql`
5. **Configure Dart**: Update `supabase_config.dart` with your Supabase URL and anon key

### Safe Migration Features

- Uses `CREATE TABLE IF NOT EXISTS` to avoid table conflicts
- Safely creates indexes and triggers without duplicates
- Handles existing policies by dropping and recreating them
- Sample data insertion checks for existing records
- No dependencies on auth.users table for basic functionality

## Database Schema

### Tables
- `users` - User profiles (extends auth.users)
- `barbers` - Barber information and profiles
- `services` - Available services (haircuts, shaves, etc.)
- `appointments` - Scheduled appointments
- `barber_availability` - Working hours for each barber
- `reviews` - Customer reviews and ratings

### Security
- Row Level Security enabled on all tables
- Users can only access their own data
- Public read access for barbers, services, and availability
- Proper foreign key relationships and constraints

## Sample Data Included

- 3 sample barbers with different specialties and real profile images
- 5 different services (haircut, beard trim, etc.) with Unsplash images
- Sample availability schedules for all barbers
- No user-dependent sample data to avoid auth conflicts

## Troubleshooting

- **"relation already exists" error**: Use `supabase_tables_safe.sql` instead
- **"relation does not exist" error**: Run tables before sample data
- **Policy conflicts**: Use `supabase_policies_safe.sql` which handles existing policies
- **Complete reset needed**: Use `supabase_reset.sql` to start fresh

## Migration Application

Migrations are automatically applied during app initialization in `main.dart`.