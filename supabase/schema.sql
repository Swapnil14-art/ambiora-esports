-- ============================================================
-- ESPORTS TOURNAMENT MANAGEMENT PLATFORM
-- Supabase PostgreSQL Schema
-- Run this entire file in the Supabase SQL Editor
-- ============================================================

-- ============================================================
-- STEP 1: TABLES
-- ============================================================

-- Games table
CREATE TABLE IF NOT EXISTS public.games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  max_teams INTEGER NOT NULL DEFAULT 16,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed the 4 games
INSERT INTO public.games (name, slug, max_teams) VALUES
  ('BGMI', 'bgmi', 16),
  ('VALORANT', 'valorant', 12),
  ('FIFA 25', 'fifa25', 32),
  ('F1', 'f1', 20)
ON CONFLICT (name) DO NOTHING;

-- Profiles table (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('admin', 'game_leader', 'viewer')),
  assigned_game_id UUID REFERENCES public.games(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Teams table
CREATE TABLE IF NOT EXISTS public.teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  team_name TEXT NOT NULL,
  logo_url TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(game_id, team_name)
);

-- Players table
CREATE TABLE IF NOT EXISTS public.players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('leader', 'member')),
  name TEXT NOT NULL,
  phone TEXT,
  year_of_study TEXT,
  in_game_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Matches table
CREATE TABLE IF NOT EXISTS public.matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  round TEXT NOT NULL DEFAULT 'Round 1',
  match_number INTEGER,
  status TEXT NOT NULL DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'live', 'completed')),
  match_type TEXT DEFAULT 'standard',
  best_of INTEGER DEFAULT 1,
  scheduled_at TIMESTAMPTZ,
  venue TEXT,
  locked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Match Teams (which teams play in which match)
CREATE TABLE IF NOT EXISTS public.match_teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  seed INTEGER,
  UNIQUE(match_id, team_id)
);

-- Match Results
CREATE TABLE IF NOT EXISTS public.match_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id UUID NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  score INTEGER DEFAULT 0,
  placement INTEGER,
  kills INTEGER DEFAULT 0,
  deaths INTEGER DEFAULT 0,
  time_ms BIGINT,
  extra_data JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(match_id, team_id)
);

-- Leaderboards
CREATE TABLE IF NOT EXISTS public.leaderboards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
  team_id UUID NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  total_points INTEGER NOT NULL DEFAULT 0,
  total_kills INTEGER DEFAULT 0,
  matches_played INTEGER DEFAULT 0,
  wins INTEGER DEFAULT 0,
  rank INTEGER,
  extra_data JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(game_id, team_id)
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  details JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 2: AUTO-CREATE PROFILE TRIGGER
-- This fires whenever a new user is created in auth.users
-- It safely handles missing/null/empty metadata fields
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _role TEXT := 'viewer';
  _display_name TEXT := '';
  _game_id UUID := NULL;
BEGIN
  -- 1. Extract role
  IF NEW.raw_user_meta_data ? 'role' THEN
    _role := NULLIF(TRIM(NEW.raw_user_meta_data->>'role'), '');
  END IF;
  
  -- Fallback if null or empty
  IF _role IS NULL THEN
    _role := 'viewer';
  END IF;

  -- 2. Extract display_name
  IF NEW.raw_user_meta_data ? 'display_name' THEN
    _display_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), '');
  END IF;
  
  -- Fallback if null or empty
  IF _display_name IS NULL THEN
    _display_name := split_part(COALESCE(NEW.email, ''), '@', 1);
  END IF;

  -- 3. Extract assigned_game_id safely
  IF NEW.raw_user_meta_data ? 'assigned_game_id' THEN
    BEGIN
      _game_id := (NULLIF(TRIM(NEW.raw_user_meta_data->>'assigned_game_id'), ''))::UUID;
    EXCEPTION WHEN OTHERS THEN
      _game_id := NULL;
    END;
  END IF;

  -- Insert the profile row. (No TRY...CATCH here so if it fails, the entire signup rolls back!)
  INSERT INTO public.profiles (id, email, display_name, role, assigned_game_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    _display_name,
    _role,
    _game_id
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    role = EXCLUDED.role,
    assigned_game_id = EXCLUDED.assigned_game_id,
    updated_at = NOW();

  RETURN NEW;
END;
$$;

-- Drop old trigger if exists, then recreate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- STEP 3: HELPER FUNCTIONS FOR RLS
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_user_game_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT assigned_game_id FROM public.profiles WHERE id = auth.uid();
$$;

-- ============================================================
-- STEP 4: ROW LEVEL SECURITY
-- ============================================================

-- ---- PROFILES ----
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_admin_all" ON public.profiles
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

CREATE POLICY "profiles_self_read" ON public.profiles
  FOR SELECT USING (id = auth.uid());

-- ---- GAMES ----
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

CREATE POLICY "games_read_all" ON public.games
  FOR SELECT USING (true);

CREATE POLICY "games_admin_all" ON public.games
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

-- ---- TEAMS ----
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "teams_read_all" ON public.teams
  FOR SELECT USING (true);

CREATE POLICY "teams_admin_all" ON public.teams
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

CREATE POLICY "teams_leader_insert" ON public.teams
  FOR INSERT WITH CHECK (
    public.get_user_role() = 'game_leader'
    AND game_id = public.get_user_game_id()
  );

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

CREATE POLICY "teams_leader_delete" ON public.teams
  FOR DELETE USING (
    public.get_user_role() = 'game_leader'
    AND game_id = public.get_user_game_id()
    AND EXISTS (SELECT 1 FROM public.players WHERE team_id = id AND user_id = auth.uid() AND role = 'leader')
  );

-- ---- PLAYERS ----
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "players_read_all" ON public.players
  FOR SELECT USING (true);

CREATE POLICY "players_admin_all" ON public.players
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

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

-- ---- MATCHES ----
ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "matches_read_all" ON public.matches
  FOR SELECT USING (true);

CREATE POLICY "matches_admin_all" ON public.matches
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

-- ---- MATCH_TEAMS ----
ALTER TABLE public.match_teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_teams_read_all" ON public.match_teams
  FOR SELECT USING (true);

CREATE POLICY "match_teams_admin_all" ON public.match_teams
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

-- ---- MATCH_RESULTS ----
ALTER TABLE public.match_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_results_read_all" ON public.match_results
  FOR SELECT USING (true);

CREATE POLICY "match_results_admin_all" ON public.match_results
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

-- ---- LEADERBOARDS ----
ALTER TABLE public.leaderboards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leaderboards_read_all" ON public.leaderboards
  FOR SELECT USING (true);

CREATE POLICY "leaderboards_admin_all" ON public.leaderboards
  FOR ALL USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

-- ---- AUDIT_LOGS ----
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_logs_admin_read" ON public.audit_logs
  FOR SELECT USING (public.get_user_role() = 'admin');

CREATE POLICY "audit_logs_insert" ON public.audit_logs
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================
-- STEP 5: SERVER-SIDE SCORING FUNCTIONS
-- ============================================================

-- Audit log helper
CREATE OR REPLACE FUNCTION public.log_audit(
  p_user_id UUID,
  p_action TEXT,
  p_details JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.audit_logs (user_id, action, details)
  VALUES (p_user_id, p_action, p_details)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- BGMI Leaderboard: Placement + Kill points
CREATE OR REPLACE FUNCTION public.calculate_bgmi_leaderboard(p_game_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.leaderboards WHERE game_id = p_game_id;

  INSERT INTO public.leaderboards (game_id, team_id, total_points, total_kills, matches_played, rank)
  SELECT
    p_game_id,
    mr.team_id,
    SUM(
      CASE
        WHEN mr.placement = 1 THEN 10
        WHEN mr.placement = 2 THEN 6
        WHEN mr.placement = 3 THEN 5
        WHEN mr.placement = 4 THEN 4
        WHEN mr.placement = 5 THEN 3
        WHEN mr.placement = 6 THEN 2
        WHEN mr.placement IN (7, 8) THEN 1
        ELSE 0
      END + COALESCE(mr.kills, 0)
    )::INTEGER,
    SUM(COALESCE(mr.kills, 0))::INTEGER,
    COUNT(DISTINCT mr.match_id)::INTEGER,
    ROW_NUMBER() OVER (
      ORDER BY SUM(
        CASE
          WHEN mr.placement = 1 THEN 10
          WHEN mr.placement = 2 THEN 6
          WHEN mr.placement = 3 THEN 5
          WHEN mr.placement = 4 THEN 4
          WHEN mr.placement = 5 THEN 3
          WHEN mr.placement = 6 THEN 2
          WHEN mr.placement IN (7, 8) THEN 1
          ELSE 0
        END + COALESCE(mr.kills, 0)
      ) DESC
    )::INTEGER
  FROM public.match_results mr
  JOIN public.matches m ON m.id = mr.match_id
  WHERE m.game_id = p_game_id AND m.status = 'completed'
  GROUP BY mr.team_id;
END;
$$;

-- VALORANT: Wins + Round diff
CREATE OR REPLACE FUNCTION public.calculate_valorant_standings(p_game_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.leaderboards WHERE game_id = p_game_id;

  INSERT INTO public.leaderboards (game_id, team_id, total_points, wins, matches_played, extra_data, rank)
  SELECT
    p_game_id,
    mr.team_id,
    SUM(COALESCE(mr.score, 0))::INTEGER,
    COUNT(*) FILTER (
      WHERE mr.score > 0 AND mr.score >= (
        SELECT MAX(mr2.score) FROM public.match_results mr2
        WHERE mr2.match_id = mr.match_id AND mr2.team_id != mr.team_id
      )
    )::INTEGER,
    COUNT(DISTINCT mr.match_id)::INTEGER,
    jsonb_build_object('round_diff', SUM(COALESCE(mr.score, 0))),
    ROW_NUMBER() OVER (
      ORDER BY
        COUNT(*) FILTER (
          WHERE mr.score > 0 AND mr.score >= (
            SELECT MAX(mr2.score) FROM public.match_results mr2
            WHERE mr2.match_id = mr.match_id AND mr2.team_id != mr.team_id
          )
        ) DESC,
        SUM(COALESCE(mr.score, 0)) DESC
    )::INTEGER
  FROM public.match_results mr
  JOIN public.matches m ON m.id = mr.match_id
  WHERE m.game_id = p_game_id AND m.status = 'completed'
  GROUP BY mr.team_id;
END;
$$;

-- FIFA 25: Knockout wins
CREATE OR REPLACE FUNCTION public.calculate_fifa25_bracket(p_game_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.leaderboards WHERE game_id = p_game_id;

  INSERT INTO public.leaderboards (game_id, team_id, total_points, wins, matches_played, rank)
  SELECT
    p_game_id,
    mr.team_id,
    COUNT(*) FILTER (
      WHERE mr.score > (
        SELECT MIN(mr2.score) FROM public.match_results mr2
        WHERE mr2.match_id = mr.match_id AND mr2.team_id != mr.team_id
      )
    )::INTEGER,
    COUNT(*) FILTER (
      WHERE mr.score > (
        SELECT MIN(mr2.score) FROM public.match_results mr2
        WHERE mr2.match_id = mr.match_id AND mr2.team_id != mr.team_id
      )
    )::INTEGER,
    COUNT(DISTINCT mr.match_id)::INTEGER,
    ROW_NUMBER() OVER (
      ORDER BY COUNT(*) FILTER (
        WHERE mr.score > (
          SELECT MIN(mr2.score) FROM public.match_results mr2
          WHERE mr2.match_id = mr.match_id AND mr2.team_id != mr.team_id
        )
      ) DESC
    )::INTEGER
  FROM public.match_results mr
  JOIN public.matches m ON m.id = mr.match_id
  WHERE m.game_id = p_game_id AND m.status = 'completed'
  GROUP BY mr.team_id;
END;
$$;

-- F1: Best lap time ranking
CREATE OR REPLACE FUNCTION public.calculate_f1_rankings(p_game_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.leaderboards WHERE game_id = p_game_id;

  INSERT INTO public.leaderboards (game_id, team_id, total_points, matches_played, extra_data, rank)
  SELECT
    p_game_id,
    mr.team_id,
    0,
    COUNT(DISTINCT mr.match_id)::INTEGER,
    jsonb_build_object('best_time_ms', MIN(mr.time_ms)),
    ROW_NUMBER() OVER (ORDER BY MIN(mr.time_ms) ASC)::INTEGER
  FROM public.match_results mr
  JOIN public.matches m ON m.id = mr.match_id
  WHERE m.game_id = p_game_id AND m.status = 'completed' AND mr.time_ms IS NOT NULL
  GROUP BY mr.team_id;
END;
$$;

-- ============================================================
-- STEP 6: UPDATED_AT TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS update_teams_updated_at ON public.teams;
CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS update_players_updated_at ON public.players;
CREATE TRIGGER update_players_updated_at BEFORE UPDATE ON public.players FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS update_matches_updated_at ON public.matches;
CREATE TRIGGER update_matches_updated_at BEFORE UPDATE ON public.matches FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS update_match_results_updated_at ON public.match_results;
CREATE TRIGGER update_match_results_updated_at BEFORE UPDATE ON public.match_results FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- STEP 7: ENABLE REALTIME
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'matches'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.matches;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'match_results'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.match_results;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'leaderboards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.leaderboards;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'teams'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.teams;
  END IF;
END;
$$;
