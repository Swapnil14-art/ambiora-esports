-- ==============================================================================
-- ABSOLUTE INVARIANT: ONE TEAM PER GAME
-- A user can only be associated with ONE team per game, represented strictly by
-- their presence in the `players` table.
-- ==============================================================================

-- 1. Create the unified validation function
CREATE OR REPLACE FUNCTION public.check_one_team_per_game()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _user_id UUID;
  _game_id UUID;
  _conflict_count INTEGER;
BEGIN
  -- ==========================================
  -- CONTEXT A: Inserting/Updating a TEAM
  -- ==========================================
  IF TG_TABLE_NAME = 'teams' THEN
    _user_id := NEW.created_by;
    _game_id := NEW.game_id;
    
    IF _user_id IS NULL THEN
      RETURN NEW;
    END IF;

    -- Check: Is the creator already a member of ANY OTHER team in this game?
    SELECT COUNT(*) INTO _conflict_count
    FROM public.players p
    JOIN public.teams t ON p.team_id = t.id
    WHERE t.game_id = _game_id 
      AND p.user_id = _user_id
      AND t.id != NEW.id;

    IF _conflict_count > 0 THEN
      RAISE EXCEPTION 'User is already a member of a team in this game.';
    END IF;

  -- ==========================================
  -- CONTEXT B: Inserting/Updating a PLAYER
  -- ==========================================
  ELSIF TG_TABLE_NAME = 'players' THEN
    _user_id := NEW.user_id;
    
    IF _user_id IS NULL THEN
      RETURN NEW;
    END IF;

    SELECT game_id INTO _game_id FROM public.teams WHERE id = NEW.team_id;

    -- Check: Is this user already a player on ANOTHER team in this same game?
    SELECT COUNT(*) INTO _conflict_count
    FROM public.players p
    JOIN public.teams t ON p.team_id = t.id
    WHERE t.game_id = _game_id 
      AND p.user_id = _user_id
      AND p.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID);

    IF _conflict_count > 0 THEN
      RAISE EXCEPTION 'User is already a member of a team in this game.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Attach validation trigger to TEAMS
DROP TRIGGER IF EXISTS trg_check_team_limit ON public.teams;
CREATE TRIGGER trg_check_team_limit
  BEFORE INSERT OR UPDATE ON public.teams
  FOR EACH ROW
  EXECUTE FUNCTION public.check_one_team_per_game();

-- 3. Attach validation trigger to PLAYERS
DROP TRIGGER IF EXISTS trg_check_player_limit ON public.players;
CREATE TRIGGER trg_check_player_limit
  BEFORE INSERT OR UPDATE ON public.players
  FOR EACH ROW
  EXECUTE FUNCTION public.check_one_team_per_game();
