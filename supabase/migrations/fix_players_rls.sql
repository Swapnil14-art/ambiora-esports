-- Fix: players_leader_insert / update / delete RLS policies
-- Problem: The current policy requires the user to already have a 'leader' row
-- in the players table for the team. This creates a chicken-and-egg problem —
-- if the leader row is missing (e.g. failed insert during team creation, or
-- a team created before the migration), the leader can never add players.
--
-- Solution: Also allow the team CREATOR (teams.created_by = auth.uid()) to
-- insert/update/delete players, not only someone with a leader row.

-- 1. Fix INSERT policy
DROP POLICY IF EXISTS "players_leader_insert" ON public.players;
CREATE POLICY "players_leader_insert" ON public.players
  FOR INSERT WITH CHECK (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
    AND (
      -- Either the user already has a leader row on this team...
      EXISTS (
        SELECT 1 FROM public.players p2
        WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
      )
      -- ...OR they are the creator of the team
      OR EXISTS (
        SELECT 1 FROM public.teams
        WHERE teams.id = players.team_id AND teams.created_by = auth.uid()
      )
    )
  );

-- 2. Fix UPDATE policy
DROP POLICY IF EXISTS "players_leader_update" ON public.players;
CREATE POLICY "players_leader_update" ON public.players
  FOR UPDATE
  USING (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
    AND (
      EXISTS (
        SELECT 1 FROM public.players p2
        WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
      )
      OR EXISTS (
        SELECT 1 FROM public.teams
        WHERE teams.id = players.team_id AND teams.created_by = auth.uid()
      )
    )
  )
  WITH CHECK (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
  );

-- 3. Fix DELETE policy
DROP POLICY IF EXISTS "players_leader_delete" ON public.players;
CREATE POLICY "players_leader_delete" ON public.players
  FOR DELETE USING (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
    AND (
      EXISTS (
        SELECT 1 FROM public.players p2
        WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
      )
      OR EXISTS (
        SELECT 1 FROM public.teams
        WHERE teams.id = players.team_id AND teams.created_by = auth.uid()
      )
    )
  );
