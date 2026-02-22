-- Allow players to create teams
-- Players don't have an assigned_game_id yet, so we just ensure they set themselves as created_by

DROP POLICY IF EXISTS "teams_player_insert" ON public.teams;
CREATE POLICY "teams_player_insert" ON public.teams
  FOR INSERT WITH CHECK (
    public.get_user_role() IN ('game_leader', 'player')
    AND created_by = auth.uid()
  );

-- We also need to relax the teams_leader_update/delete if they just created it,
-- though the UI updates their role immediately after creation.
-- Just to be safe, let's allow players to update/delete teams they own.
DROP POLICY IF EXISTS "teams_player_update" ON public.teams;
CREATE POLICY "teams_player_update" ON public.teams
  FOR UPDATE
  USING (
    public.get_user_role() IN ('game_leader', 'player', 'viewer')
    AND EXISTS (SELECT 1 FROM public.players WHERE team_id = id AND user_id = auth.uid() AND role = 'leader')
  )
  WITH CHECK (
    public.get_user_role() IN ('game_leader', 'player', 'viewer')
  );

DROP POLICY IF EXISTS "teams_player_delete" ON public.teams;
CREATE POLICY "teams_player_delete" ON public.teams
  FOR DELETE USING (
    public.get_user_role() IN ('game_leader', 'player', 'viewer')
    AND EXISTS (SELECT 1 FROM public.players WHERE team_id = id AND user_id = auth.uid() AND role = 'leader')
  );
