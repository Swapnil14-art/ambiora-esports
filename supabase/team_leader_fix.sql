-- ==============================================================================
-- FIX: AUTO-INSERT TEAM LEADERS INTO ROSTER & BACKFILL EXISTING TEAMS
-- Run this script in your Supabase SQL Editor
-- ==============================================================================

-- 1. Create a function that triggers when a team is inserted
CREATE OR REPLACE FUNCTION public.auto_insert_team_leader()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _name TEXT;
  _email TEXT;
BEGIN
  -- If the team was created by someone (which it should be)
  IF NEW.created_by IS NOT NULL THEN
    -- Fetch the profile details of the creator
    SELECT display_name, email INTO _name, _email FROM public.profiles WHERE id = NEW.created_by;
    
    -- Insert them as the first player in the team with the role of Captain
    INSERT INTO public.players (team_id, name, in_game_name)
    VALUES (
      NEW.id, 
      COALESCE(_name, split_part(COALESCE(_email, ''), '@', 1), 'Team Captain'), 
      'Captain'
    );
  END IF;
  RETURN NEW;
END;
$$;

-- 2. Attach the trigger to the teams table
DROP TRIGGER IF EXISTS on_team_created ON public.teams;
CREATE TRIGGER on_team_created
  AFTER INSERT ON public.teams
  FOR EACH ROW EXECUTE FUNCTION public.auto_insert_team_leader();

-- 3. BACKFILL script to fix all existing Teams
-- This will insert the team creator into the players table if they aren't already there
INSERT INTO public.players (team_id, name, in_game_name)
SELECT 
  t.id, 
  COALESCE(p.display_name, split_part(COALESCE(p.email, ''), '@', 1), 'Team Captain'), 
  'Captain'
FROM public.teams t
JOIN public.profiles p ON t.created_by = p.id
WHERE NOT EXISTS (
  SELECT 1 FROM public.players pl WHERE pl.team_id = t.id AND pl.in_game_name = 'Captain'
);
