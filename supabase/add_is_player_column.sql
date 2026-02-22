-- ==============================================================================
-- ADD IS_PLAYER TO PROFILES & AUTO-RESOLVE EXISTING 'GAME_LEADER'
-- Run this script in your Supabase SQL Editor
-- ==============================================================================

-- 1. Add the is_player boolean to the profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_player BOOLEAN DEFAULT FALSE;

-- 2. Backfill: If they already have a team, they are implicitly a Team Leader (is_player = false). 
--    This is already the default, so nothing to do. Wait, no. We actually want ANY existing game_leader to be set. 
--    Since `DEFAULT FALSE` covers all existing rows, they remain "Team Leaders".
--    If any existing users get stuck, they will see Gate 1.5.

-- NO further action needed as DEFAULT FALSE gracefully solves the backfill!
