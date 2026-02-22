-- ============================================================
-- RESET SCRIPT — Run this FIRST if you already ran the old schema
-- This drops everything cleanly so you can re-run schema.sql
-- Run in Supabase SQL Editor BEFORE running schema.sql
-- ============================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
DROP TRIGGER IF EXISTS update_teams_updated_at ON public.teams;
DROP TRIGGER IF EXISTS update_players_updated_at ON public.players;
DROP TRIGGER IF EXISTS update_matches_updated_at ON public.matches;
DROP TRIGGER IF EXISTS update_match_results_updated_at ON public.match_results;

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_role() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_game_id() CASCADE;
DROP FUNCTION IF EXISTS public.log_audit(UUID, TEXT, JSONB) CASCADE;
DROP FUNCTION IF EXISTS public.calculate_bgmi_leaderboard(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.calculate_valorant_standings(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.calculate_fifa25_bracket(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.calculate_f1_rankings(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at() CASCADE;

-- Drop tables in dependency order
DROP TABLE IF EXISTS public.audit_logs CASCADE;
DROP TABLE IF EXISTS public.leaderboards CASCADE;
DROP TABLE IF EXISTS public.match_results CASCADE;
DROP TABLE IF EXISTS public.match_teams CASCADE;
DROP TABLE IF EXISTS public.matches CASCADE;
DROP TABLE IF EXISTS public.players CASCADE;
DROP TABLE IF EXISTS public.teams CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.games CASCADE;

-- Remove from realtime publication (ignore errors if not there)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.matches;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.match_results;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.leaderboards;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.teams;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

-- Also delete any auth users that were created (clean slate)
-- This is safe — it only deletes from auth, profiles cascade
DELETE FROM auth.users;
