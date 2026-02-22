-- ==============================================================================
-- ADD PLAYER ROLE TO PROFILES
-- Run this script in your Supabase SQL Editor
-- ==============================================================================

-- 1. Drop the existing role check constraint
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;

-- 2. Add the new check constraint including 'player'
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
  CHECK (role IN ('admin', 'game_leader', 'viewer', 'player'));

-- 3. You can safely ignore backfilling since the previous script wasn't run.
-- Players will use the fresh role.
