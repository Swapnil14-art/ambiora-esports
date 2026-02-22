-- 1. Add new columns to the players table
ALTER TABLE public.players 
ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member'));

-- 2. Update existing rows if necessary (optional, but good practice if you want to make existing creators leaders)
UPDATE public.players p
SET role = 'leader'
FROM public.teams t
WHERE p.team_id = t.id AND t.created_by = p.user_id;

-- 3. Replace RLS Policies on Teams
DROP POLICY IF EXISTS "teams_leader_update" ON public.teams;
CREATE POLICY "teams_leader_update" ON public.teams
  FOR UPDATE
  USING (
    public.get_user_role() = 'game_leader'
    AND game_id = public.get_user_game_id()
    AND EXISTS (SELECT 1 FROM public.players WHERE team_id = id AND user_id = auth.uid() AND role = 'leader')
  )
  WITH CHECK (
    public.get_user_role() = 'game_leader'
    AND game_id = public.get_user_game_id()
  );

DROP POLICY IF EXISTS "teams_leader_delete" ON public.teams;
CREATE POLICY "teams_leader_delete" ON public.teams
  FOR DELETE USING (
    public.get_user_role() = 'game_leader'
    AND game_id = public.get_user_game_id()
    AND EXISTS (SELECT 1 FROM public.players WHERE team_id = id AND user_id = auth.uid() AND role = 'leader')
  );

-- 4. Replace RLS Policies on Players
DROP POLICY IF EXISTS "players_leader_insert" ON public.players;
CREATE POLICY "players_leader_insert" ON public.players
  FOR INSERT WITH CHECK (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
    AND EXISTS (
      SELECT 1 FROM public.players p2 
      WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
    )
  );

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
    AND EXISTS (
      SELECT 1 FROM public.players p2 
      WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
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

DROP POLICY IF EXISTS "players_leader_delete" ON public.players;
CREATE POLICY "players_leader_delete" ON public.players
  FOR DELETE USING (
    public.get_user_role() = 'game_leader'
    AND EXISTS (
      SELECT 1 FROM public.teams
      WHERE teams.id = players.team_id
      AND teams.game_id = public.get_user_game_id()
    )
    AND EXISTS (
      SELECT 1 FROM public.players p2 
      WHERE p2.team_id = players.team_id AND p2.user_id = auth.uid() AND p2.role = 'leader'
    )
  );
