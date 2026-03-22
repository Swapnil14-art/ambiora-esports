--
-- PostgreSQL database dump
--

\restrict CVBAsG2vhQ3rgmogTfOekEf89OD1DH9QRSJY8ewjLfatUfbOtSWMIW42YhdjVCh

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: calculate_bgmi_leaderboard(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_bgmi_leaderboard(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: calculate_f1_rankings(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_f1_rankings(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: calculate_fifa25_bracket(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_fifa25_bracket(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: calculate_valorant_standings(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_valorant_standings(p_game_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: check_one_team_per_game(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_one_team_per_game() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: create_fixtures_batch(uuid, text, timestamp with time zone, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_fixtures_batch(p_game_id uuid, p_round_name text, p_scheduled_at timestamp with time zone, p_matchups jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_matchup JSONB;
    v_new_match_id UUID;
    v_team_id TEXT;
    v_match_number INTEGER := 1;
    v_inserted_count INTEGER := 0;
BEGIN
    -- Verify the caller is an Admin
    IF public.get_user_role() != 'admin' THEN
        RAISE EXCEPTION 'Only Admins can batch-create fixtures.';
    END IF;

    -- Iterate over each matchup in the JSON array
    FOR v_matchup IN SELECT * FROM jsonb_array_elements(p_matchups)
    LOOP
        -- 1. Insert the Match Row
        INSERT INTO public.matches (
            game_id, 
            round, 
            match_number, 
            status, 
            match_type, 
            best_of, 
            scheduled_at
        ) VALUES (
            p_game_id,
            p_round_name,
            v_match_number,
            'upcoming',
            COALESCE(v_matchup->>'match_type', 'standard'),
            COALESCE((v_matchup->>'best_of')::INTEGER, 1),
            p_scheduled_at
        ) RETURNING id INTO v_new_match_id;

        -- 2. Insert the Match Teams
        -- We extract the team_ids string array and insert a row for each
        FOR v_team_id IN SELECT * FROM jsonb_array_elements_text(v_matchup->'team_ids')
        LOOP
            INSERT INTO public.match_teams (match_id, team_id)
            VALUES (v_new_match_id, v_team_id::UUID);
        END LOOP;

        v_match_number := v_match_number + 1;
        v_inserted_count := v_inserted_count + 1;
    END LOOP;

    -- Log the action
    INSERT INTO public.audit_logs (user_id, action, details)
    VALUES (
        auth.uid(),
        'Generated bracket fixtures',
        jsonb_build_object('game_id', p_game_id, 'round', p_round_name, 'count', v_inserted_count)
    );

    RETURN jsonb_build_object('success', true, 'inserted_count', v_inserted_count);
EXCEPTION WHEN OTHERS THEN
    -- If ANYTHING fails, Postgres will automatically rollback the entire transaction block.
    -- We just re-raise the error so the client UI can gracefully catch it.
    RAISE EXCEPTION 'Fixture generation failed: %', SQLERRM;
END;
$$;


--
-- Name: get_user_game_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_game_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT assigned_game_id FROM public.profiles WHERE id = auth.uid();
$$;


--
-- Name: get_user_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_role() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(COALESCE(NEW.email, ''), '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'game_leader')
  );
  RETURN NEW;
END;
$$;


--
-- Name: log_audit(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_audit(p_user_id uuid, p_action text, p_details jsonb DEFAULT '{}'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    action text NOT NULL,
    details jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.games (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    max_teams integer DEFAULT 16 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: leaderboards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaderboards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    game_id uuid NOT NULL,
    team_id uuid NOT NULL,
    total_points integer DEFAULT 0 NOT NULL,
    total_kills integer DEFAULT 0,
    matches_played integer DEFAULT 0,
    wins integer DEFAULT 0,
    rank integer,
    extra_data jsonb DEFAULT '{}'::jsonb,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: match_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.match_results (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    match_id uuid NOT NULL,
    team_id uuid NOT NULL,
    score integer DEFAULT 0,
    placement integer,
    kills integer DEFAULT 0,
    deaths integer DEFAULT 0,
    time_ms bigint,
    extra_data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: match_teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.match_teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    match_id uuid NOT NULL,
    team_id uuid NOT NULL,
    seed integer
);


--
-- Name: matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.matches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    game_id uuid NOT NULL,
    round text DEFAULT 'Round 1'::text NOT NULL,
    match_number integer,
    status text DEFAULT 'upcoming'::text NOT NULL,
    match_type text DEFAULT 'standard'::text,
    best_of integer DEFAULT 1,
    scheduled_at timestamp with time zone,
    locked boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    venue text,
    CONSTRAINT matches_status_check CHECK ((status = ANY (ARRAY['upcoming'::text, 'live'::text, 'completed'::text])))
);


--
-- Name: players; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.players (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    team_id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    year_of_study text,
    in_game_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid,
    role text DEFAULT 'member'::text NOT NULL,
    CONSTRAINT players_role_check CHECK ((role = ANY (ARRAY['leader'::text, 'member'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    display_name text,
    role text DEFAULT 'viewer'::text NOT NULL,
    assigned_game_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'game_leader'::text, 'viewer'::text, 'player'::text])))
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    game_id uuid NOT NULL,
    team_name text NOT NULL,
    logo_url text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'qualified'::text NOT NULL,
    CONSTRAINT teams_status_check CHECK ((status = ANY (ARRAY['qualified'::text, 'disqualified'::text])))
);


--
-- Data for Name: audit_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_logs (id, user_id, action, details, created_at) FROM stdin;
4d710a87-8550-416f-8a30-a1e48087e90e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: asd@gmail.com	{"deleted_user_id": "d4f0bf64-a2aa-46ed-8e6a-af0adcb346c4"}	2026-02-21 14:55:03.625113+00
20cfd793-ee0e-4611-aa68-5d2c32a77704	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qweqweq@gmail.com	{"deleted_user_id": "38254030-9d49-44a8-8464-31530ad04fe4"}	2026-02-21 15:14:25.338125+00
6bd7b385-8c8a-4a1d-85f3-c022fb556ef6	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "match_id": "c8c20c18-d5b0-43de-beb7-f8d634c76315"}	2026-02-21 15:22:54.807852+00
b5c7ab23-bd59-4784-ab1e-d0e71b638969	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwertyyy@gmail.com	{"deleted_user_id": "0ecb3c03-43cb-47c8-a169-276d0b39e04f"}	2026-02-21 15:32:35.441903+00
57e46176-8f9d-4ac8-99eb-7365435f94c5	\N	Leader created team: F1	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 15:21:18.540765+00
ee0fa9a6-5d03-4aa2-8334-b5e8efa30eaf	\N	Leader created team: F11	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 15:22:17.195456+00
30721b8c-7143-4fee-99ad-ee429086d6b6	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwertyy@gmail.com	{"deleted_user_id": "ec96f2a4-782f-47af-9522-52b2d14c551c"}	2026-02-21 15:32:37.113243+00
ad606079-1449-4be0-a14d-4339c2fb6d19	\N	Leader created team: Bihari	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-21 15:19:04.820528+00
65ae0658-a651-43d4-8888-e3a44b6fac27	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwerty@gmail.com	{"deleted_user_id": "b920cea6-7a67-4633-a264-2d44501f8837"}	2026-02-21 15:32:38.612412+00
14ec547c-4c55-427f-a90f-38f4d0e0716b	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F11	{"game": "F1", "team_id": "8dda2dda-9681-4591-baea-f6bffb39e532"}	2026-02-21 15:32:45.350576+00
7817fa82-5c18-4cfb-9927-12c58caeab63	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F1	{"game": "F1", "team_id": "a0a31945-be05-4ed8-914a-b3162b77698c"}	2026-02-21 15:32:47.531001+00
7f14dbd3-ddba-44d0-8e93-397af6592560	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Bihari	{"game": "BGMI", "team_id": "205f1585-ad02-4c64-8034-99dd90dd1466"}	2026-02-21 15:32:49.860968+00
742b3ef8-791d-4b81-a16f-b1cf43d152af	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "c8c20c18-d5b0-43de-beb7-f8d634c76315"}	2026-02-21 15:37:03.953564+00
f7d3fcad-da98-46b0-bc64-424b8bb460c6	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455", "match_id": "98e051de-541a-4c8f-8986-f999ca7b296e"}	2026-02-21 15:48:17.648272+00
07aae48f-358d-41f4-8a20-80385474fc21	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1 #1	{"match_id": "98e051de-541a-4c8f-8986-f999ca7b296e"}	2026-02-21 15:48:43.479145+00
21e0c5d1-b6c0-4c7b-b0db-dbe61cb945f4	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "98e051de-541a-4c8f-8986-f999ca7b296e"}	2026-02-21 15:48:54.960103+00
e2d972b5-241b-4f15-b335-1364a96397bc	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "98e051de-541a-4c8f-8986-f999ca7b296e"}	2026-02-21 15:48:59.000502+00
7b379d34-813d-421d-9689-5c1046b8b7bd	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F12	{"game": "F1", "team_id": "c8e44208-86b7-4d18-9347-d220e251377d"}	2026-02-21 17:20:06.695598+00
2f2836b2-98fd-4285-94d7-1700387b1898	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F11	{"game": "F1", "team_id": "67b5c3b6-1e24-4fa6-beef-14db25cfc986"}	2026-02-21 17:20:09.136388+00
5c5b0a8a-8987-4ea9-a46d-27a69a3fce2f	\N	Leader created team: F11	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 15:47:07.122045+00
2815cfbc-b8b5-43b8-aa45-0281bddd0bda	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f11@gmail.com	{"deleted_user_id": "d967b3da-3c98-498a-a31b-7d4c73506b9e"}	2026-02-21 17:20:12.212063+00
9102d793-bd63-4e2b-8f35-eb501a6893cf	\N	Leader created team: F12	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 15:47:34.761862+00
44af60ac-7240-4112-b64e-51f6ce1de09c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f12@gmail.com	{"deleted_user_id": "b8d9b98c-d90b-48be-8e9b-329920fbc1e1"}	2026-02-21 17:20:13.646275+00
a089a04c-9292-4d1f-be56-4fbc52e865db	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F11	{"game": "F1", "team_id": "4f8abf85-2503-4478-97b8-89a18f4770f7"}	2026-02-21 17:23:26.811843+00
4b17353a-26b3-497c-8dd3-6d5a8bc7a63f	\N	Mandatory setup: Created team F11	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 17:22:57.506578+00
64b6a0ed-ef2e-42ba-a0f3-b08b3535d726	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f11@gmail.com	{"deleted_user_id": "4c4ad910-a517-48b2-97e0-49b7175a8df9"}	2026-02-21 17:23:31.419309+00
3b7c79f3-19de-4957-b5db-36212712394c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F11	{"game": "F1", "team_id": "d332fd8b-34bd-4adf-89b5-4c38ddcc582d"}	2026-02-21 17:26:35.078706+00
888a6b21-be9c-4b39-b77a-2f3319a7585d	\N	Mandatory setup: Created team F11	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 17:23:44.026625+00
ca74b79c-8052-4335-a4fa-9911bdfea9f2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f11@gmail.com	{"deleted_user_id": "4954bd14-889f-4c62-ad52-34c6ae1cd412"}	2026-02-21 17:26:38.277192+00
0ec30628-ff71-46bd-a2ab-0ce8ce769b89	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F22	{"game": "F1", "team_id": "1409832c-d435-4975-bc44-374176e48696"}	2026-02-21 17:35:00.975862+00
5acc77b1-0fed-4bb5-a5ce-861df6e6d51f	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: F11	{"game": "F1", "team_id": "0c88f370-ef7f-4e47-9925-675fecbf8a85"}	2026-02-21 17:35:02.78998+00
feaeea85-aca9-437d-a3ec-dda0db4175db	\N	Mandatory setup: Created team F22	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 17:27:21.74675+00
da3c31d3-bba3-4536-a2e1-417b5db13d12	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f22@gmail.com	{"deleted_user_id": "41b134b9-2228-4872-a568-0382f65f15a9"}	2026-02-21 17:35:05.697951+00
08611d2d-8dcf-4e17-af64-d59b98790785	\N	Mandatory setup: Created team F11	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 17:26:53.64436+00
5892c844-1225-4493-98b2-e7a95a7658ee	\N	Leader created team: gsdf	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-21 17:27:03.937099+00
25629496-5cc8-471b-bf4b-77dccb701b62	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f11@gmail.com	{"deleted_user_id": "8baaa922-a361-4f25-a2b3-8a466e01032d"}	2026-02-21 17:35:07.474196+00
2033e507-88ba-44b4-addb-70a5e5fd14a3	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f11@gmail.com	{"deleted_user_id": "5106b86c-716c-43b3-afc1-796bd0a40ae1"}	2026-02-21 17:40:22.380894+00
3bbd33f8-3504-4f2b-8be3-5cfb4d31d70a	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: valo11@gmail.com	{"deleted_user_id": "19d902a8-3d54-4572-bae0-961991398dc4"}	2026-02-21 17:45:15.493144+00
ebab7b3a-81cf-48ba-9809-3400a570e84c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "d2cb671b-e4b6-445a-8d94-4aafee87065d"}	2026-02-21 17:48:26.821105+00
c9b20739-de8d-4df7-9358-eeaefe4ef82d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "bfa8a99e-7cd8-48d7-8436-0744746fd2e4"}	2026-02-21 17:51:49.670847+00
265a6ee7-2ccf-4ac9-a837-964790cc1e4e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "137459be-f4bd-405a-890b-867697eebec1"}	2026-02-21 18:00:08.876967+00
c4e0b0c3-fbb4-461d-88fc-b9c37a13bbc2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "9e910d20-f9dc-4b4e-9fb2-315b95df788e"}	2026-02-21 18:03:11.61721+00
7c96bafc-2860-45e4-b3b2-cf49244b6631	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "6b52dcf8-7b5f-47b8-b8be-8f2862553d59"}	2026-02-21 18:54:52.729451+00
b9ade8bc-8900-471a-bce9-595214caf113	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "37741f51-1fa2-489c-a9d5-5b7ab709b632"}	2026-02-21 18:59:53.44565+00
102001da-e18a-4217-a834-2dd21bce6ac0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "9a99625a-4a6f-400f-a113-b5a8fd828e0a"}	2026-02-22 05:11:54.299839+00
64194a3e-41f3-4113-be0a-99da2824d035	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 0, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:14:51.340677+00
dccee107-954c-439f-b2d6-adbb04108197	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 0, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:15:10.170125+00
3d48c2db-e112-463a-aedb-451f88a3df43	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: v2	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:15:29.553487+00
1a1b52a3-e41a-4d8a-9b42-391a14fcd683	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:16:12.024425+00
e9df2f71-9fc0-4c76-a626-0f919999c339	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "19420c63-7009-44fc-98fb-9e7803d08b20"}	2026-02-22 09:16:42.033968+00
7e73dce8-2fac-4558-a337-78ad7bf5d819	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: v2	{"game": "VALORANT", "team_id": "62aa6956-6d01-412c-8564-5a514a4754d1"}	2026-02-22 09:22:42.546552+00
caa81265-979f-4604-9777-e4748f695789	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: f11	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:23:23.838256+00
5269f953-eb20-463c-b62c-53880d876c02	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: f11	{"game": "VALORANT", "team_id": "dc77305b-ff12-4223-badb-35179368a641"}	2026-02-22 09:24:13.365282+00
fbaf9613-8d8a-40b4-88cb-c2f30fedf4ce	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: f11	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:24:18.114688+00
91b72a7b-c8c6-45da-a834-6bff8207f077	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Aqua	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-02-22 09:43:09.941243+00
17a60cfc-f2b9-4f0f-afe4-e1c9ab541908	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 09:43:45.178477+00
46bb9dfe-188e-4cdc-ba78-f5128f4b7035	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Round of 32", "game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-02-22 09:49:19.483877+00
49380a4f-6582-4b57-9acc-e6fc1eb5b909	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Lobby 1", "game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-22 11:49:39.641463+00
f33b1240-3c3b-4847-924e-d87c447de9bb	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: yes@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "ce2532e2-aba3-4890-bf21-dd3ec4eed3a7"}	2026-02-22 11:50:39.617229+00
a0ebcbef-bdcd-4b02-ba24-c8da46a7951f	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: yes@gmail.com (role → game_leader)	{"target_user_id": "ce2532e2-aba3-4890-bf21-dd3ec4eed3a7"}	2026-02-22 11:50:53.3098+00
f76ff26e-ddb2-4d46-9a48-c5b3250f3545	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: yes	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-22 11:52:04.913187+00
e9a1c1f2-56e9-46a1-970a-cc7ad970fc4f	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Lobby 1", "game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-22 11:53:27.218832+00
1972237f-e70c-451a-8786-ef35625bc579	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v12@gmail.com	{"deleted_user_id": "a77f55c4-949d-47a7-843e-c40ff7638a21"}	2026-02-22 12:12:37.721011+00
813eaba9-17f6-4823-9c78-68c577d6773f	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:05:09.837385+00
568142df-05d9-4195-b4eb-293396182f36	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:05:29.89093+00
5efc64de-19f1-4990-978e-698cf8cefaa3	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:06:18.588444+00
8aa40011-864e-4f72-ab9c-ac110e87549a	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:07:25.157147+00
cde4b58b-cccf-4aae-af8e-62db78edfc5c	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:07:34.006883+00
6293f5dc-f1e2-4b12-93ad-01a45dae46fc	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-02-22 13:07:47.261989+00
f2ef8601-d231-4ba5-a244-370174850f12	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-23 17:15:11.158066+00
f6eb0981-3707-4240-b909-312bc3376e00	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Lobby 1", "game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-25 14:28:13.765018+00
c31833e6-c8ec-44d8-983e-0bf7a7ba08af	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Lobby 3", "game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-02-25 14:28:20.234263+00
1fa66110-8415-4b63-806a-bc526414b2c6	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 2, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-25 14:28:35.322501+00
c99e67a0-0e11-451c-8f16-726e20c0ad30	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test@gmail.com	{"deleted_user_id": "73240103-2e38-4fbf-80cb-0677623d2608"}	2026-03-02 17:25:16.51312+00
447de3cc-7d75-4d61-9784-4839fb84a4d8	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test003	{"game": "VALORANT", "team_id": "cd0308fc-97c2-4fbd-a585-0ac9fd1debb9"}	2026-03-02 17:54:31.340935+00
7c230aeb-9b63-4d74-9915-93a79cdafa3a	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test003@gmail.com	{"deleted_user_id": "9023d459-69a6-42aa-953f-b7aa92630e35"}	2026-03-02 17:54:35.855157+00
5479017c-8194-4e71-804c-e768afdd1024	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test008@gmail.com	{"deleted_user_id": "09945bcc-c365-4835-8c3f-c68371139506"}	2026-03-02 18:55:34.96265+00
ca46bc06-e781-43e1-a157-d6eb36ba7319	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test007@gmail.com	{"deleted_user_id": "847ed751-afeb-4b5d-8260-c39146827f4a"}	2026-03-02 18:55:36.991344+00
0e73ce54-c6f8-4b04-9089-c96ab421e89e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test006@gmail.com	{"deleted_user_id": "a90e42a0-d0eb-44df-8df3-f114f1a59c3a"}	2026-03-02 18:55:41.546901+00
def35be9-f83c-4f03-856d-d6bc4db1319e	\N	Mandatory setup: Created team Test005	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-02 18:08:55.189218+00
62017cd4-dfb3-4a48-84bc-ee726def8a05	\N	Mandatory setup: Created team Test004	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-02 18:02:27.180346+00
20df0f69-1d3f-4b82-b36a-c257d931d564	\N	Mandatory setup: Created team Test002	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-02 17:36:49.789758+00
602a9fce-5c73-48ab-bef7-8aea8628a02b	\N	Mandatory setup: Created team Test001	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-02 17:32:27.655356+00
1322d912-3cc2-49c0-a99e-9cd233e03980	\N	Mandatory setup: Created team Testing123	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-02 17:23:42.029478+00
fcd76724-7617-478f-932a-bfc07fa4def1	\N	Mandatory setup: Created team Qwertyuiop	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-02-28 02:41:46.858003+00
303d07a9-de6c-4036-a6c2-74325b25f3a6	\N	Mandatory setup: Created team qwertyyuu	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-28 02:38:47.869084+00
96b45cc2-6dc7-4453-b39c-d4bbbc576744	\N	Mandatory setup: Created team qwer	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-24 12:37:19.637978+00
f472b098-f0a4-48fe-b8be-81f874e57475	\N	Mandatory setup: Created team hdf	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-22 10:07:04.836981+00
ffadc622-519c-465e-8887-ec54f312f5ab	\N	Mandatory setup: Created team Chutiya hu mai	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-02-22 09:47:51.90578+00
765b5622-795f-4319-b024-d304c5e2e15a	\N	Leader added player: F11	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-22 05:26:32.4091+00
d5e82167-51ff-44d1-a445-7c10288422c2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test005@gmail.com	{"deleted_user_id": "4e0cbf6c-5633-41ee-bf16-d36467ff222b"}	2026-03-02 18:55:43.542576+00
91fc7e9c-b4f3-4457-bfa4-d476646b9e31	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test004@gmail.com	{"deleted_user_id": "349b8df5-7b1f-45fa-8290-45fdc6dfcdca"}	2026-03-02 18:55:45.03673+00
6cc3960b-d8a0-4563-85b9-d88920253828	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testleader@example.com	{"deleted_user_id": "e2cf0cba-d7b2-4479-9999-2fcb4a1127ec"}	2026-03-02 18:55:46.573208+00
c420a43f-d5de-4cc8-b31c-4566d57c5b2d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test002@gmail.com	{"deleted_user_id": "03e12360-a29e-413a-84c2-e203a1c025e2"}	2026-03-02 18:55:47.845318+00
3ff595b4-62f0-4b8f-8ed0-2c296b863b57	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: test001@gmail.com	{"deleted_user_id": "e6ee36d0-2b79-47f1-b39e-fa09c267c210"}	2026-03-02 18:55:49.279787+00
ea0ecabc-039c-4604-af5f-f1727a4a1d27	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testing@gmail.com	{"deleted_user_id": "12a6c294-6b36-4805-91f3-436a3fae3767"}	2026-03-02 18:55:50.509485+00
8b83f1c3-67f0-4301-aeb4-821b24dc659c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: appa@gmail.com	{"deleted_user_id": "0cacb2c6-9237-4092-9307-3d46efefddb0"}	2026-03-02 18:55:51.842326+00
6f8af4f1-1f7d-408d-86a7-2ca785368aa8	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwe@gmail.com	{"deleted_user_id": "84767202-134e-4024-af7b-080d571bad9d"}	2026-03-02 18:55:52.968898+00
ee66af72-48c5-4e89-a8ec-3f588ae21e3b	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwe2@gmail.com	{"deleted_user_id": "58c5eeda-41e8-4e0c-8fe7-60845a95b34a"}	2026-03-02 18:55:54.257645+00
004d05d3-6193-422f-ac6c-2788675c5734	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: yes@gmail.com	{"deleted_user_id": "ce2532e2-aba3-4890-bf21-dd3ec4eed3a7"}	2026-03-02 18:55:55.405132+00
c62d3f58-caba-4d87-b38f-39bee1ad66cc	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testadmin@ambiora.com	{"deleted_user_id": "fb4f0469-f9bb-483f-a1f8-dc2eaf76edf7"}	2026-03-02 18:55:56.656202+00
face9988-183c-4277-a8ec-a3925a8b1084	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: bihari@gmail.com	{"deleted_user_id": "9f96719b-bc22-4350-bb51-735a963e0e85"}	2026-03-02 18:55:57.766714+00
a289772a-0524-4c02-a9d2-65c7cb055412	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: sshhuubb@gmail.com	{"deleted_user_id": "ce36caef-77a3-4cb6-8b96-8dd958a3fb63"}	2026-03-02 18:55:59.138851+00
730e3f07-ce0c-4f49-aa0e-fe5708c4ca7d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: f12@gmail.com	{"deleted_user_id": "53a7444c-3766-4158-91e6-28df9cc66085"}	2026-03-02 18:56:00.294825+00
bd196114-3f1e-4abc-80c8-25ba9e65404f	\N	Mandatory setup: Created team v1	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-02-21 17:45:36.852579+00
8d7b6995-06f1-446d-97a9-ecabfe672302	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.3576+00
a07cebbd-f41b-490e-9cce-e92d02e81a54	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.37786+00
bff42007-7549-4988-aab4-21b3410acd21	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.381845+00
cb098b44-1ef9-4817-8220-3d21a9a77379	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.382375+00
d9276db6-7e5a-4763-b531-78c794d97516	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.388694+00
2e686f1d-af28-424f-bcd8-3ecd7ada7a6f	\N	Leader added player: V12	{"team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-02-21 19:01:46.391462+00
77e30fac-6251-48ab-869f-18a910fdfd83	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: v11@gmail.com	{"deleted_user_id": "eac61288-e68e-4e42-9727-c29538663a41"}	2026-03-02 18:56:01.56113+00
aac984f0-20c9-4817-a203-e35cc46ead87	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: bhiii	{"game": "BGMI", "team_id": "5faaeda1-a189-4137-9a25-2289f37ae579"}	2026-03-02 18:56:06.238896+00
d8ca0680-cf7b-413b-b406-b986036ea129	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: bhiii	{"game": "BGMI", "team_id": "5faaeda1-a189-4137-9a25-2289f37ae579"}	2026-03-02 18:56:07.719638+00
9a09277c-c740-4f59-b615-a4ccdfba40e2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: yes	{"game": "BGMI", "team_id": "8c470675-ef40-40c4-9741-5135afce76dd"}	2026-03-02 18:56:09.733102+00
790307be-5249-40da-b867-4ffe679c1bc2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: BGMI12	{"game": "BGMI", "team_id": "012d843f-3204-4df0-9632-396485fd018c"}	2026-03-02 18:56:10.617032+00
0b0fe452-20f7-43f8-8d2c-e65f77c55dad	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Qwertyuiop	{"game": "F1", "team_id": "2e0b1f75-5f08-47f9-a8e9-0df0f8e46c36"}	2026-03-02 18:56:47.61298+00
4ffa938c-146b-4d65-b3ba-2b67d74248d2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Aqua	{"game": "FIFA 25", "team_id": "41ccaebb-b386-4d2e-ba02-edc7ed13d763"}	2026-03-02 18:56:51.422818+00
43651186-3ad9-4487-b615-66dc3d9373b8	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test008	{"game": "VALORANT", "team_id": "57ad44e2-bb43-4cf2-b7f5-d01dc298590b"}	2026-03-02 18:56:55.806459+00
b1bd1570-f3d8-4352-8545-3d2ba06e9059	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test007	{"game": "VALORANT", "team_id": "80459057-7abd-430c-b864-0e85d7ac733d"}	2026-03-02 18:56:59.543651+00
e57001ed-2541-42e9-8f4f-4c6b14788bc7	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Tes4	{"game": "VALORANT", "team_id": "f026778e-915d-4a73-b1c6-ffd4a1745406"}	2026-03-02 18:57:01.139818+00
114a28e9-ec59-4b46-b344-4259ad0014fc	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test0066	{"game": "VALORANT", "team_id": "3f97b4af-26c3-490d-9752-b8012fb41293"}	2026-03-02 18:57:02.167139+00
e0b84681-eac6-4beb-ab39-2854cbc8b0e0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test006	{"game": "VALORANT", "team_id": "895f27b6-aed0-4dfb-9f47-76835ad90b99"}	2026-03-02 18:57:03.09813+00
c38c8772-0d3b-4480-9d21-9e042d810c23	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test005	{"game": "VALORANT", "team_id": "0c1739e6-5dba-4e76-a17e-13081cc06137"}	2026-03-02 18:57:04.18987+00
d71e6352-b233-471a-bd40-8af33eef73e4	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test004	{"game": "VALORANT", "team_id": "5400df0b-6d6c-4518-b566-a5208084a549"}	2026-03-02 18:57:05.135861+00
acdd03a8-e8cf-43d6-96f5-27ff30e62134	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test Team Alpha	{"game": "VALORANT", "team_id": "7875cb62-2ed0-4cdd-bae8-0bb8aa569b6b"}	2026-03-02 18:57:05.893855+00
933fb334-64f3-4790-a635-57b965c1129e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: 1234567890	{"game": "VALORANT", "team_id": "28318fae-9039-48e9-be9d-3f6c1c79ccfe"}	2026-03-02 18:57:06.89814+00
72655dc0-7a86-4dcb-8c59-1fd394d0f453	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test002	{"game": "VALORANT", "team_id": "1feb74e3-6b63-4f78-a071-978870a73d03"}	2026-03-02 18:57:08.696165+00
a3d082cf-101a-442e-b48c-cd23f0399ca2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test001	{"game": "VALORANT", "team_id": "be636597-e291-44ed-add3-8cf209d1b2d9"}	2026-03-02 18:57:10.900621+00
f01ee163-3b71-43c0-952a-fb8fb74eb969	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Tet	{"game": "VALORANT", "team_id": "fdab07e3-4796-4b46-8352-ebd25903b066"}	2026-03-02 18:57:12.113446+00
9a028a7b-09af-45f8-9ffd-8025f9171559	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Testing123	{"game": "VALORANT", "team_id": "f4e936f4-6b95-4daa-80da-ec894c40c57e"}	2026-03-02 18:57:13.045839+00
b764b76b-8f3c-4a70-9fe2-65adf88de8f6	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: qwe	{"game": "VALORANT", "team_id": "e5ed6462-2bd7-47f7-8362-3cabd10dc384"}	2026-03-02 18:57:13.879099+00
2f383d6a-b417-4ebb-90e2-e187dd4da5c2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: qwertyyuu	{"game": "VALORANT", "team_id": "2a3dd4a0-e4f9-4b76-88fa-72b3b3abbb7e"}	2026-03-02 18:57:15.077953+00
29e1368f-f2d5-4225-8370-2c1106ab9ce2	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: jk	{"game": "VALORANT", "team_id": "5b3b40de-c530-4615-bfba-10be43a64467"}	2026-03-02 18:57:17.693323+00
a148f369-3684-49bf-afb4-264bbf7ba34b	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: qwer	{"game": "VALORANT", "team_id": "99ce4efd-f4c4-48fe-886b-6305fe1760eb"}	2026-03-02 18:57:19.793982+00
b0b1ff40-9d5a-4c9a-a944-0e2a19df26e0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: hdf	{"game": "VALORANT", "team_id": "d11d4e31-49ae-4cf9-93ef-f05a11032dea"}	2026-03-02 18:57:20.772446+00
a5ca0626-563a-42c0-ab9a-9c652177392f	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: f11	{"game": "VALORANT", "team_id": "3b020730-d158-4044-a533-29e929bfe7ea"}	2026-03-02 18:57:22.099048+00
ffb6b28c-1248-4815-b6f3-98360628fbac	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: v1	{"game": "VALORANT", "team_id": "88335da4-1e2f-4c5e-a248-730f5aa132f4"}	2026-03-02 18:57:23.949667+00
873fcf34-544c-4fee-96c7-fea9cdb0b8f8	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Qwertyuiop	{"game": "F1", "team_id": "2e0b1f75-5f08-47f9-a8e9-0df0f8e46c36"}	2026-03-02 18:57:31.062148+00
bd1eb9e1-a916-40b1-a284-3709c24a1c29	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #2	{"match_id": "fec0aaaa-5554-45fc-91cb-48f65fe5f5e6"}	2026-03-02 18:58:07.60456+00
725de3bc-d743-4c87-87ee-789476fad1ed	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "19dccf93-ba97-438d-91a8-464043998282"}	2026-03-02 18:58:09.304168+00
a37f86c1-1971-49c2-bbc3-90bfad37aabf	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Lobby 3 #1	{"match_id": "eb045b31-0266-4dc8-8ac9-80a2a606da2b"}	2026-03-02 18:58:10.779211+00
804e340d-cf48-456a-bafd-c5ed54e00113	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Lobby 1 #1	{"match_id": "fef739b2-6a85-4e25-a49e-cf8c22e83c53"}	2026-03-02 18:58:12.822423+00
a5961ac2-edba-4a9f-a28a-29a2530ac803	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "bc18b473-1eef-4b4e-b2f4-1c1cd3fcc514"}	2026-03-02 18:58:17.310641+00
7065d50c-244e-491a-b9b4-b50013aa1b06	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Lobby 1 #1	{"match_id": "a8fcb21b-09bc-4c12-8fd2-062cb8a2305e"}	2026-03-02 18:58:18.949619+00
a60e3566-e60a-486e-9d2c-95a7b2726ad0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Lobby 1 #1	{"match_id": "8fbd2bf9-db3c-416b-a613-dd5b6c699c65"}	2026-03-02 18:58:20.49606+00
6861e663-1f0b-4cf1-b848-7d366d3bea2e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 32 #1	{"match_id": "75aa60cd-d740-4da1-9e77-dbcb018f6dc2"}	2026-03-02 18:58:21.971328+00
5c1be5be-587c-42c0-9bca-74ec0b31476f	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "f54dd901-5533-4a36-9638-ba259d4e4378"}	2026-03-02 18:58:23.438848+00
f9c6cd29-fbd2-4b27-9524-96e4a94555f9	\N	Mandatory setup: Created team Testing4	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-02 19:07:25.767071+00
2d5ac897-c4db-4097-99db-16aff25a7079	\N	Leader added player: Testing3	{"team_id": "05fc76ce-f616-4cea-b296-67257b4f0e3f"}	2026-03-02 19:07:44.821389+00
0e9284b9-2cf8-499a-8006-b85b58ded5d3	\N	Mandatory setup: Created team Testing2	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-02 19:05:38.176732+00
39093ca3-1c4c-4147-8a6e-7335b054a2cd	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testing4@gmail.com	{"deleted_user_id": "7d30ee1c-c141-423e-b670-21f14246bc4d"}	2026-03-02 19:10:02.902164+00
44793fea-00e1-4b89-b29f-8d9813d43b89	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testing2@gmail.com	{"deleted_user_id": "c64e6397-c526-4bec-85f2-af700ffc4af6"}	2026-03-02 19:10:02.90332+00
30c4e5c8-b54c-4696-b870-ac562569a088	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testing3@gmail.com	{"deleted_user_id": "1af83188-a1a8-4341-843a-5e09c0c0aeb3"}	2026-03-02 19:10:02.920564+00
a9a29e27-948e-4a76-8f71-ae4ad06875d5	\N	Mandatory setup: Created team Test	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-02 19:00:11.733721+00
205779de-ba05-4907-b76d-f1d9432a7c19	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testieyeyng@gmail.com	{"deleted_user_id": "cb200d20-0677-464b-be70-8fa7d6034cc2"}	2026-03-03 18:22:28.509841+00
b11eb9bb-0f53-498e-ab9a-88d1366ec71d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testieyfjgeyng@gmail.com	{"deleted_user_id": "fbcabcb7-cf1b-4568-9c82-f64fc6e56fc2"}	2026-03-03 18:22:29.33465+00
351f8f58-7e0b-4690-b9d8-2468c220867c	\N	Mandatory setup: Created team Rt	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-03 18:23:04.566961+00
174a6f82-3765-4f16-ad2b-25b96c43b22e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: qwerr@gmail.com	{"deleted_user_id": "9f1a3809-4b0c-484e-b13c-5e6be7fa315e"}	2026-03-04 04:51:45.747146+00
acf535da-6b3e-4b61-a158-6c822e728985	\N	Mandatory setup: Created team Zatu	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-03 17:52:51.171839+00
69c92f5c-3d8a-4b51-960c-a9a9928c92e7	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: shinderaj2006@gmail.com	{"deleted_user_id": "c41a0199-7738-4280-b404-9a12741fa616"}	2026-03-04 04:51:48.083865+00
35400835-4ed8-4fa3-a28a-69949c0f572c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: rajshinde0604@gmail.com	{"deleted_user_id": "7088c5f8-4132-4097-9ee8-c3605a20e971"}	2026-03-04 04:51:51.562946+00
a23348e9-c595-4a47-a351-86b7513d4d5b	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: Laveshpatil103@gmail.com (admin)	{"role": "admin", "new_user_id": "9e5339c5-a706-4ae3-aaa7-beda00fc88ea"}	2026-03-04 04:54:10.58966+00
69476db9-9bdb-49b1-86d8-e57bff8b4a7f	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: anantjha884@gmail.com (admin)	{"role": "admin", "new_user_id": "bfc601de-144e-4470-bc49-abba27e1654e"}	2026-03-04 04:54:55.201176+00
1a2b6198-c768-4ddd-b5dc-894cfd9ebf0d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Testing4	{"game": "BGMI", "team_id": "05fc76ce-f616-4cea-b296-67257b4f0e3f"}	2026-03-05 03:21:53.835911+00
9a45f685-001c-456b-ba10-b8cc1e27068d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Testing2	{"game": "BGMI", "team_id": "7466c898-0b6b-4f28-bd59-0e7ce2011132"}	2026-03-05 03:21:56.367291+00
aa2d6579-6439-4917-9fff-280dd447bc4c	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Test	{"game": "F1", "team_id": "90bfe26e-b814-474a-a88d-b019ec2bbdf5"}	2026-03-05 03:22:03.804004+00
99892dce-29d3-4ebb-b787-290d9995629d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Rt	{"game": "VALORANT", "team_id": "e1000fac-8d55-45f5-86cb-d57a2b1fcc02"}	2026-03-05 03:22:11.168266+00
0815078c-5a8b-427f-80a1-81167a6234bb	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Zatu	{"game": "VALORANT", "team_id": "5bc806b0-e13c-41db-9c13-8e4bb55ca77a"}	2026-03-05 03:22:13.444105+00
d19cad69-f374-4e96-b87b-271e0960efde	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: testing5@gmail.com	{"deleted_user_id": "8412deae-2f8d-4432-ac22-285833d0c5fa"}	2026-03-05 12:51:54.510728+00
a2cc6d17-555e-42e6-8332-772e501d143b	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: sharvinneve67@gmail.com (admin)	{"role": "admin", "new_user_id": "80e32448-e07e-4d7b-a543-7fb9b527413d"}	2026-03-05 18:22:15.336586+00
c3a5329c-8e84-4a08-a99b-5a5950d72850	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: utkarsh3200singh@gmail.com	{"deleted_user_id": "a2dadae6-75f7-43ad-9907-dea546e377bb"}	2026-03-06 16:01:51.739297+00
23c62a8e-4495-463c-8985-8cbf686c0f1d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: therevolutionofgaming@gmail.com	{"deleted_user_id": "e67912d1-b125-4289-8847-3990832e923a"}	2026-03-06 16:01:53.993385+00
af43e00c-77fa-414d-a8a3-3d41473713d1	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: apexpredator@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "e34e443c-30fe-4d7e-b495-7daa8d8aad48"}	2026-03-06 16:04:58.551143+00
739eaf98-af2a-4439-8fb4-3ee39b3cd9e0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: apexpredator@gmail.com	{"deleted_user_id": "e34e443c-30fe-4d7e-b495-7daa8d8aad48"}	2026-03-06 16:05:28.246131+00
51952105-2dda-4096-a06c-d264804b40f6	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: apexpredator@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "12e45af4-bcb2-4b70-a9c6-4a606edca64d"}	2026-03-06 16:06:10.517744+00
d4261de3-cbb6-41d5-bc76-9cf216bc852c	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Apex Predator 	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 16:06:25.010083+00
0ace2dfc-1d6b-4c0f-ac71-a7e19effac50	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: teamogmanav@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "ab6b8348-ff70-41f0-9d2c-c7eb7f6cd098"}	2026-03-06 16:10:08.357004+00
f11211fd-7751-4675-926b-87af43eef261	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team OG	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 16:10:26.520209+00
24962699-1587-4b86-a8f4-4c4d33b5a89b	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: apexpredator@gmail.com	{"deleted_user_id": "12e45af4-bcb2-4b70-a9c6-4a606edca64d"}	2026-03-06 16:22:56.260502+00
7b411bc2-f6ec-4a2b-9c68-255cb29e6724	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: teamogmanav@gmail.com	{"deleted_user_id": "ab6b8348-ff70-41f0-9d2c-c7eb7f6cd098"}	2026-03-06 16:22:57.815842+00
4d315213-76ab-4679-b9ac-30018f3e5a97	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Apex Predator	{"game": "BGMI", "team_id": "c98e1b1b-7774-4784-bc6e-15aa811b0d66"}	2026-03-06 16:23:02.856597+00
ef42528a-951b-499d-8ad0-b9bef6627af7	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted team: Team OG	{"game": "BGMI", "team_id": "a51f1ff1-6d35-4b1f-8b93-5b989edb9148"}	2026-03-06 16:23:04.248413+00
250452d4-4255-4d8c-b745-34d4dc36131d	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: atharvatanpure01@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "3d84676d-caa7-4e6f-97a1-aaa8e2f13f81"}	2026-03-06 16:25:01.311128+00
3c28f6d8-aea5-4ad9-a2cf-8eb58a2d6c28	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted user: atharvatanpure01@gmail.com	{"deleted_user_id": "3d84676d-caa7-4e6f-97a1-aaa8e2f13f81"}	2026-03-06 21:22:45.583914+00
43a896c9-7753-46cd-91e3-3d3a6602b384	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: manavpendalwad456@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "965f3a72-0891-4e78-bea0-43dc9933d2cf"}	2026-03-06 21:28:20.645302+00
9f982565-4031-4d48-b561-41e8ff1d3464	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: manavpendalwad456@gmail.com (role → game_leader)	{"target_user_id": "965f3a72-0891-4e78-bea0-43dc9933d2cf"}	2026-03-06 21:28:37.618319+00
eea9a3fe-e5d7-4956-b5bd-9c80bb4ec496	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: nairarjun915@gmail.com (role → game_leader)	{"target_user_id": "85f178e6-d0f6-4322-8968-7b66b9eaa0de"}	2026-03-06 21:29:11.973539+00
b0ac24ae-de80-4c60-8736-12a2e9607d1b	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: nigelm524@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "f2035212-4b88-446a-84cc-c04c3ebb2128"}	2026-03-06 21:30:30.962009+00
145053de-af32-4167-b9b5-a4db3a651ab9	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: nigelm524@gmail.com (role → game_leader)	{"target_user_id": "f2035212-4b88-446a-84cc-c04c3ebb2128"}	2026-03-06 21:30:36.886483+00
4ef77acb-c76d-4769-8cce-abaf07a26c2a	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: atharva.charu.16@gmail.com (role → game_leader)	{"target_user_id": "675cf1ea-9a72-40fb-b683-27f83d4a69cc"}	2026-03-06 21:32:26.036886+00
320b733d-63f8-40be-b4ca-fc23c1cb3456	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: yuvrajkale95@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "8d0e8d1c-eb4c-4305-b619-0213ac73f24a"}	2026-03-06 21:32:52.002556+00
07de0f0e-b2c0-42e3-a106-7557a0bbc351	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: yuvrajkale95@gmail.com (role → game_leader)	{"target_user_id": "8d0e8d1c-eb4c-4305-b619-0213ac73f24a"}	2026-03-06 21:32:57.975486+00
7482091f-bbf1-4b12-8f95-c432604ecb44	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: malhar@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "668bc4b9-d6f4-4bc3-b067-1430a017b18d"}	2026-03-06 21:33:16.838515+00
6aff07ca-724e-437d-8f07-f634ba6142d3	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: atharvatanpure01@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "aa8b5ffe-c211-4124-b178-6da96489038e"}	2026-03-06 21:29:38.200555+00
ee207151-4ec1-4cd9-8b6d-d145948b7b92	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: atharvatanpure01@gmail.com (role → game_leader)	{"target_user_id": "aa8b5ffe-c211-4124-b178-6da96489038e"}	2026-03-06 21:29:45.391654+00
9d3a8cb0-9764-4387-8700-d7912083af06	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: krishnabhamare60@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "96c36e58-36c3-4d1b-92db-59663cfd93ae"}	2026-03-06 21:30:56.303327+00
cd8f190a-9b79-4f5f-bb09-b11e4a1d8ec6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: krishnabhamare60@gmail.com (role → game_leader)	{"target_user_id": "96c36e58-36c3-4d1b-92db-59663cfd93ae"}	2026-03-06 21:31:04.121773+00
88fad128-1ec1-473e-9bf0-08c1e4a50c42	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jangidaditya2304@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "623986af-52a6-44b5-9ae6-7cd2db37c6cb"}	2026-03-06 21:31:55.503958+00
9c00cff7-1554-4991-8876-a6d67641bf98	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jangidaditya2304@gmail.com (role → game_leader)	{"target_user_id": "623986af-52a6-44b5-9ae6-7cd2db37c6cb"}	2026-03-06 21:32:00.760115+00
d6edb5ad-aefb-4224-9fe6-a82f4774fbae	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: malhar@gmail.com (role → game_leader)	{"target_user_id": "668bc4b9-d6f4-4bc3-b067-1430a017b18d"}	2026-03-06 21:33:22.530767+00
f50a5de5-80dc-4b04-8523-42a8c0aa552e	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: aryanbhakuni2006@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "5e431913-6b58-4617-ace5-4427cde50719"}	2026-03-06 21:30:06.199176+00
0cf67afa-12b4-4e4c-b676-46685d4b49d1	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: aryanbhakuni2006@gmail.com (role → game_leader)	{"target_user_id": "5e431913-6b58-4617-ace5-4427cde50719"}	2026-03-06 21:30:12.011826+00
ad7cb071-840f-45f4-8a48-ab939f7a1c7a	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jadhavpiyush868@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "14dfefb0-f5fc-4dac-96b0-5e7099fbf8a0"}	2026-03-06 21:31:24.625013+00
ab931fef-6a71-4025-a5e0-d5f539eb70ae	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jadhavpiyush868@gmail.com (role → game_leader)	{"target_user_id": "14dfefb0-f5fc-4dac-96b0-5e7099fbf8a0"}	2026-03-06 21:31:31.174343+00
06f99e5d-d85e-4396-861e-aad3eeea9142	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: atharva.charu.16@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "675cf1ea-9a72-40fb-b683-27f83d4a69cc"}	2026-03-06 21:32:19.742517+00
9b928b8a-5dfc-4ce4-a88c-8be2c46be8bc	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team OG	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:36:18.569971+00
a939f535-9263-402c-a212-50be3b0ac4af	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: 4 Angry Men	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:36:32.274337+00
984d21d2-8fa0-43b4-aa6e-5acb56b30a28	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Apex Predators	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:36:46.453349+00
95dbb7e1-3d2b-4b12-8f0c-b06c9929d04b	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Zero mercy	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:37:00.014823+00
8ef0c6d5-c7c0-48ec-8b4c-f3736bd7bcf6	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team Insanity	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:37:24.591082+00
cba8ffe2-8e1f-45b4-818f-7e0dbaf1d8f4	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Krishna	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:37:38.745985+00
a4d562f0-df46-4273-abd9-735b13cb70d7	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team Maka Ladlleeeee	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:37:46.832766+00
4e03edd7-1b31-4005-88c9-97d30dc3f6f6	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team Santra	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:37:58.635713+00
189a34f2-c1de-482f-b61d-9ad1d324dde0	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Team.VNAND	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:38:41.444148+00
c50d3c18-bce3-436d-b15b-bee54e8c3b49	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: fnatic	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:38:46.400821+00
353ebf60-a7ad-44b7-ba3b-ef9ae7add580	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Malhar	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7"}	2026-03-06 21:39:06.257576+00
94aa6b86-5a6e-447a-9982-0f7401b140ed	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jaypatelhd2005@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "90c218dc-2f80-47d6-bf34-e81b40887524"}	2026-03-06 21:43:04.75527+00
c0a7c177-646c-4a8e-a0fb-86457990204e	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: shubhanyways07@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "d92a0f94-3ff9-41e1-b5d5-72cd2b38b60d"}	2026-03-06 21:43:19.104632+00
82c9e853-786b-4be0-8e42-db42feb15630	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jaypatelhd2005@gmail.com (role → game_leader)	{"target_user_id": "90c218dc-2f80-47d6-bf34-e81b40887524"}	2026-03-06 21:43:30.628368+00
f459bc39-f0df-4d80-8f26-08a5b0a1275d	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: shubhanyways07@gmail.com (role → game_leader)	{"target_user_id": "d92a0f94-3ff9-41e1-b5d5-72cd2b38b60d"}	2026-03-06 21:43:36.275522+00
a25873ad-0ebe-49c0-a703-61ed290e1448	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: bhatsiddhant1@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "f619cf40-4412-4eab-bc49-f9f6db280c71"}	2026-03-06 21:43:51.924378+00
150cb5dc-c4f8-4ba0-948a-e7e7250b2875	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: bhatsiddhant1@gmail.com (role → game_leader)	{"target_user_id": "f619cf40-4412-4eab-bc49-f9f6db280c71"}	2026-03-06 21:43:59.057199+00
725a3958-4558-4a34-83c2-f1d810268672	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: bharukaharsh@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "360d6d78-a47e-46e9-958e-b36600fae21e"}	2026-03-06 21:44:18.857548+00
a7ef89f0-86f2-424d-b44a-f808c53c64e0	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: garvitnandwana22@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "e29de3e4-88a0-4b0a-9c8e-abceac26ee29"}	2026-03-06 21:44:44.043875+00
8c1e7d70-e17e-4896-8f92-abdca6589b81	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: bharukaharsh@gmail.com (role → game_leader)	{"target_user_id": "360d6d78-a47e-46e9-958e-b36600fae21e"}	2026-03-06 21:44:52.257113+00
820c5289-343d-4e11-b946-581959c0ecc7	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: garvitnandwana22@gmail.com (role → game_leader)	{"target_user_id": "e29de3e4-88a0-4b0a-9c8e-abceac26ee29"}	2026-03-06 21:44:59.234686+00
1ef8005f-2129-47ef-9584-e17187a248e2	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: rujul.yerne276@nmims.in (game_leader)	{"role": "game_leader", "new_user_id": "122773a7-9411-4b8e-b97a-271bcfd78006"}	2026-03-06 21:45:28.767982+00
687e4511-761a-4a0c-9e97-cc7ca154a5e5	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: rujul.yerne276@nmims.in (role → game_leader)	{"target_user_id": "122773a7-9411-4b8e-b97a-271bcfd78006"}	2026-03-06 21:45:35.583043+00
7302f1cb-491a-4b7f-aece-0fff210bfecb	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: krish1346p@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "ec970805-c740-4f1b-ab8e-580f0468b272"}	2026-03-06 21:45:49.115726+00
845fe35b-730f-474d-b6ea-b354530b5e5b	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: krish1346p@gmail.com (role → game_leader)	{"target_user_id": "ec970805-c740-4f1b-ab8e-580f0468b272"}	2026-03-06 21:46:01.122951+00
714dfa43-a5d0-40d9-b1f5-d1045e20a6fa	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jay Patel	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:46:16.694509+00
9f53fa05-f451-4f7d-8cc2-cf56f37308ce	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Shubham Jha	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:46:44.072483+00
052a16de-049f-41eb-a7da-0e0ebb75d641	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Sid	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:46:51.30554+00
839286e7-01ec-45b8-9453-a5fbf72d7c90	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Harsh Bharuka	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:47:12.615001+00
38ff4b04-2b89-4475-ac96-8cc439824c76	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Garvit Nandwana	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:47:25.802228+00
eef45739-1db3-4167-8033-bedfcb5b5934	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rujul yerne	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:47:42.263031+00
c1bd59b4-10b5-41de-9dbf-e8e4c63f3d2a	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Krish Prajapati	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 21:47:56.742908+00
594e8a04-a1a9-4b98-a7ff-f054e43968a4	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: dispanker2018@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "f2d47eb0-2761-4cc8-93bc-591950f813f8"}	2026-03-06 21:54:06.117976+00
cac11371-4de9-46c7-af03-7a166686b253	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: godspeeed@duck.com (game_leader)	{"role": "game_leader", "new_user_id": "2e035d82-8836-476c-a816-7ba275701202"}	2026-03-06 21:54:25.369685+00
7c4d64e5-c01b-426b-9fa5-106c5821880a	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: nilanshsinghal10@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "29bfc8df-fe4a-4592-b6c6-d72a8c06a884"}	2026-03-06 21:54:54.169203+00
2b51c769-b78e-43f9-8380-a4eabf1f3d7e	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: dispanker2018@gmail.com (role → game_leader)	{"target_user_id": "f2d47eb0-2761-4cc8-93bc-591950f813f8"}	2026-03-06 21:55:09.486258+00
4425f733-58d4-496e-81c9-a5b345f3b484	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: godspeeed@duck.com (role → game_leader)	{"target_user_id": "2e035d82-8836-476c-a816-7ba275701202"}	2026-03-06 21:55:15.295991+00
03eedf6a-f6eb-4c2a-9f78-f75f3af4734b	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: nilanshsinghal10@gmail.com (role → game_leader)	{"target_user_id": "29bfc8df-fe4a-4592-b6c6-d72a8c06a884"}	2026-03-06 21:55:21.167151+00
fcb1726d-6cec-46d4-bf66-62288fa7677c	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jaypatilll20@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "f70a35b1-48e9-4bf0-88db-8a0fc5076e14"}	2026-03-06 21:56:22.908673+00
2f4a4da7-f445-4f21-8d79-1576ecc69514	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jaypatilll20@gmail.com (role → game_leader)	{"target_user_id": "f70a35b1-48e9-4bf0-88db-8a0fc5076e14"}	2026-03-06 21:56:36.028117+00
cc43d105-5714-4742-9c30-58baa27b8187	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: rps.rudu@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "5d6a6675-b191-4444-811a-45efe9ad9268"}	2026-03-06 21:56:51.116846+00
a9a08937-d271-4de0-93c3-7110c6b2c9ee	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jmandloi6638@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "96b3586c-1a86-4f2e-b65c-110e1d9f839c"}	2026-03-06 21:57:11.121797+00
aba3827a-7eb1-4a0a-8c2f-2fce17d9fa2b	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: kunjdesai28@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "620c954f-f59d-48f9-b3e7-3be9b77b8ac9"}	2026-03-06 21:57:35.128533+00
d38f252a-05f0-427a-9011-e45e6f477c01	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: rakshitpandey680@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "e0c06eff-fd91-4ad3-a340-55f293872df1"}	2026-03-06 21:57:56.368455+00
c67204ea-f644-4a5b-a02d-1ba653e3ea57	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jmandloi6638@gmail.com (role → game_leader)	{"target_user_id": "96b3586c-1a86-4f2e-b65c-110e1d9f839c"}	2026-03-06 21:58:01.806911+00
7455b4d9-02c8-4a46-ba7e-60a716d47c47	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: rps.rudu@gmail.com (role → game_leader)	{"target_user_id": "5d6a6675-b191-4444-811a-45efe9ad9268"}	2026-03-06 21:58:06.685555+00
ab66218f-4990-4551-bf7a-c68fa2eb7e18	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: rakshitpandey680@gmail.com (role → game_leader)	{"target_user_id": "e0c06eff-fd91-4ad3-a340-55f293872df1"}	2026-03-06 21:58:13.528657+00
5b58a428-88d2-4a4d-ac65-307b09ce8304	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: kunjdesai28@gmail.com (role → game_leader)	{"target_user_id": "620c954f-f59d-48f9-b3e7-3be9b77b8ac9"}	2026-03-06 21:58:20.723276+00
76e7122b-2d3e-48d6-bfa5-116edca9403d	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: yashnitinsingpatil.8@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "e1c94e11-5396-4130-9ffa-1c76b6d7969c"}	2026-03-06 21:58:45.189925+00
427ac590-8c65-4120-8b7c-85fd02e58a06	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: nikhilraulo70@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "2a9de694-2dbc-4d17-b109-5a2e7e13f656"}	2026-03-06 21:59:04.098456+00
1912d02a-6908-4c2e-a1fa-4dd670401bad	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: shlokkatwate2705@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "3356d2b0-32fc-486b-af7b-afcbf26ac7b3"}	2026-03-06 21:59:19.11864+00
f4ca26be-c129-4ad9-bde7-0ee86591ed14	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: jason15th2007@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "7e76c858-e523-4bc0-af1c-99db247c840a"}	2026-03-06 21:59:58.510199+00
6e5326e1-3994-4d4f-96ec-d353255d1ca2	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jason15th2007@gmail.com (role → game_leader)	{"target_user_id": "7e76c858-e523-4bc0-af1c-99db247c840a"}	2026-03-06 22:00:05.553231+00
9989f8a0-e555-4735-b120-5ed6fc5261c7	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: nikunjgoyal681@gmail.com (role → game_leader)	{"target_user_id": "16c20803-c5a3-4b46-b263-0a9243e528cd"}	2026-03-06 22:00:11.74773+00
6b423180-aa09-4b4b-9b1a-51b9810bef05	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: shlokkatwate2705@gmail.com (role → game_leader)	{"target_user_id": "3356d2b0-32fc-486b-af7b-afcbf26ac7b3"}	2026-03-06 22:00:17.147706+00
52bc1e19-6e8a-43bb-b6c5-3073de7e1dc6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: nikhilraulo70@gmail.com (role → game_leader)	{"target_user_id": "2a9de694-2dbc-4d17-b109-5a2e7e13f656"}	2026-03-06 22:00:22.799226+00
b3111c9a-4160-425a-a0cf-b30bbf2ea257	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: yashnitinsingpatil.8@gmail.com (role → game_leader)	{"target_user_id": "e1c94e11-5396-4130-9ffa-1c76b6d7969c"}	2026-03-06 22:00:27.939866+00
9ec026af-abb2-43ca-8d67-68904cf7f663	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: painterrohan@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "d6786693-2e23-4fa8-902f-3287585eb336"}	2026-03-06 22:01:04.943179+00
99056620-53ba-4e49-820c-1c55b2b90908	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: hemant@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "c89a4286-c785-477d-8f2f-694a92bda4e5"}	2026-03-06 22:01:57.42942+00
07195903-895e-4d41-9cfd-d50486261876	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: Aryan@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "b0507a12-afa1-4c01-9cdd-2d5fea199ca1"}	2026-03-06 22:02:35.768608+00
4d8d1499-1478-43b0-a694-02ec24e289d7	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: arnabchowdhury979@gmail.com (role → game_leader)	{"target_user_id": "6a70988d-9044-47b9-bac7-cc839cf58556"}	2026-03-06 22:02:42.794568+00
b29bc483-3187-4ab8-8e48-f08610d0ba07	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: painterrohan@gmail.com (role → game_leader)	{"target_user_id": "d6786693-2e23-4fa8-902f-3287585eb336"}	2026-03-06 22:02:49.006262+00
39e3e060-341e-4e45-a8ae-548e53b53400	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: hemant@gmail.com (role → game_leader)	{"target_user_id": "c89a4286-c785-477d-8f2f-694a92bda4e5"}	2026-03-06 22:02:55.136534+00
c120e38f-7768-4da7-b0db-ea7a36b30b36	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: jashraj@gmail.com (role → game_leader)	{"target_user_id": "78894d49-24f3-43da-b4d6-3fd1b58101eb"}	2026-03-06 22:03:01.857551+00
ace36430-9c8f-44e3-b550-d908de693133	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: aryan@gmail.com (role → game_leader)	{"target_user_id": "b0507a12-afa1-4c01-9cdd-2d5fea199ca1"}	2026-03-06 22:03:06.858807+00
01749aee-43d9-450d-b295-b1247335f41d	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Deepankar Paul	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:03:26.887769+00
14231ccd-e08c-4508-b7b4-896bd1a0f26c	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Shauryadeep Singh	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:03:40.141148+00
5e1f0ed6-a626-4e0a-9217-0af213442f33	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Nilansh Singhal	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:03:51.603624+00
2609dd00-ee68-4483-9992-4afcc449fa24	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Nigel Menezes	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:04:06.482114+00
ba691bcc-c34f-4205-9919-2e3a25790a5f	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jay Patil	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:04:24.585654+00
8e74533e-f644-4ec0-9682-6dbf2dab9e03	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: nikunjgoyal681@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "16c20803-c5a3-4b46-b263-0a9243e528cd"}	2026-03-06 21:59:35.129093+00
19860e3d-d9fb-4859-b288-f48b0ec6ebe6	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: arnabchowdhury979@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "6a70988d-9044-47b9-bac7-cc839cf58556"}	2026-03-06 22:00:46.658085+00
ee950cbd-4dc3-44fc-b958-125315ccf093	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: Jashraj@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "78894d49-24f3-43da-b4d6-3fd1b58101eb"}	2026-03-06 22:02:18.357973+00
e28620ec-1b95-4e98-98bd-8194260af6fb	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rudrapratap Singh	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:04:45.963021+00
df06685d-2ac1-4b33-aa10-33386a41e6cd	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jayesh Mandloi	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:05:02.672875+00
788b1c8c-ed37-4a1d-b18d-ff62b1014fd7	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rishabh Mehta	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:05:17.800113+00
6c5e7d9b-6213-4e06-8ca5-760071857069	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rakshit Pandey	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:05:30.600858+00
0f67a8ca-989a-4f2e-8b75-c06985c247fb	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Yash Patil	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:05:42.219247+00
9013ee81-ee4e-4888-afb2-bbf321b50b34	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Nikhil Raulo	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:05:54.955971+00
ecfb0de3-7c97-41fc-a726-b593c4946f3a	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Shlok Katwate	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:06:07.848108+00
e8c5491e-5261-4369-95e1-86e264d9c099	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Nikunj Goyal	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:06:19.467063+00
8d3ca526-1ea6-4a89-b23f-b11989f60701	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jason Philip	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:06:29.719808+00
5cb2692f-8cc2-42ed-9cb3-c302b215af85	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Arnab Chowdhury	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:06:42.337382+00
79011e92-4606-4931-a498-4c9992791d5a	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rohan Painter	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:07:07.065348+00
bd843230-dc84-4ce4-bf31-68cb20559775	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Krish Prajapati	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:07:22.43898+00
3d249d18-f0cb-481b-8433-9eb2c6ffe004	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Hemant	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:08:25.070752+00
e5c72070-3e9d-4e09-92de-5e7c493ff3e9	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jashraj	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:08:58.595208+00
48e2beab-f11c-4aa8-bf43-f3a9b591204c	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Aryan	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:09:14.241268+00
8341229f-b8cf-422a-a231-8ce941aedb31	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: shreyasnair002@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "06a47237-f90a-40f3-9a5d-316701113d55"}	2026-03-06 22:13:54.283269+00
60c7105e-b529-4a2b-8f09-a09254237f79	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: ankitj2811@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "90f5afde-deb1-4a0c-b330-9a485d39a305"}	2026-03-06 22:15:31.593002+00
7be0a5d1-07cf-44d1-8083-2713dbcd7e5e	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: shreyasnair002@gmail.com (role → game_leader)	{"target_user_id": "06a47237-f90a-40f3-9a5d-316701113d55"}	2026-03-06 22:15:41.046695+00
9a167f46-0be9-4c25-ba3c-746d8ad02347	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: ankitj2811@gmail.com (role → game_leader)	{"target_user_id": "90f5afde-deb1-4a0c-b330-9a485d39a305"}	2026-03-06 22:15:46.942906+00
de2f43e3-b665-4c6b-a83d-53dfc914d459	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: m10prjpt@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "4b40008f-abcc-4793-a280-3b1407cdb044"}	2026-03-06 22:16:06.93388+00
3b5294d6-ffb6-428b-98a2-c2d4048a87fe	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: m10prjpt@gmail.com (role → game_leader)	{"target_user_id": "4b40008f-abcc-4793-a280-3b1407cdb044"}	2026-03-06 22:16:15.585952+00
84332d20-1332-4466-a26a-809e5250b930	80e32448-e07e-4d7b-a543-7fb9b527413d	Created team: Sharvin Neve	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:18:04.070195+00
01816837-5571-410a-8a7e-12f8fbfb80d1	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Shreyas Nair	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:18:22.410916+00
b211d794-ac02-473b-92f5-076451e68103	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Jay Patil	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:18:35.905287+00
58d10812-fe32-4ce7-b8cb-aeb69ef7e118	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Nigel Menezes	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:18:46.995446+00
36e2c14a-312c-456b-9850-b638e50ca2f3	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Ankit Jangid	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:19:03.140362+00
d8aa7379-10e5-4d93-9733-e3e03c988ece	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Maharshi Prajapati	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:19:14.888295+00
1bdc3c05-7564-4783-91ba-eeb5c193eb00	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4", "match_id": "84cce3c2-7b4b-49dc-b5d8-1cd1a0a634f1"}	2026-03-06 22:21:14.344986+00
51597b53-3576-44da-8d01-95ea2061c452	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "84cce3c2-7b4b-49dc-b5d8-1cd1a0a634f1"}	2026-03-06 22:21:24.812517+00
ad47375e-c94e-4f4c-841f-36fe8bcbf28f	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "match_id": "5889a6d6-d22a-4656-9c89-26f5db27fb5e"}	2026-03-06 22:21:55.082448+00
e66ee9a3-99d1-43f2-8a88-7a0f9203f561	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "5889a6d6-d22a-4656-9c89-26f5db27fb5e"}	2026-03-06 22:22:02.28005+00
a00b3236-230f-4737-b97e-fda3ef64d6ab	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 10, "round": "Round of 32", "game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-06 22:36:24.114292+00
2a2cda3c-d2d7-4e22-8f9d-914add094e14	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 3, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:39:55.577417+00
8b27172f-bded-4fc2-8d32-aad29bce5e05	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "2438e292-da41-4469-90ce-b30fc43cc81b"}	2026-03-06 22:40:34.983245+00
2640ef17-708c-4e54-bda3-f05a3ad2903e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #2	{"match_id": "17845900-70a9-4ccc-9c4f-fcac732036f7"}	2026-03-06 22:40:37.583283+00
bf32b342-d4ee-47a0-aa3a-fd231e82daa1	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #3	{"match_id": "4755146d-be96-430f-8e6c-a0204d19585e"}	2026-03-06 22:40:40.135129+00
5373a7ca-84f9-4211-8202-2f8c5a4d3b12	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 3, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:40:47.317215+00
f2adf4ec-27e7-450f-956d-1d90c1e2f37c	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Qualifiers (Time Trial)", "game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455"}	2026-03-06 22:41:14.28164+00
1b0a63b5-82ac-43e1-8a9a-f29e806b61ec	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1: Knockout #1	{"match_id": "feccbacb-408f-4b70-a07b-d1adceba770b"}	2026-03-06 22:54:06.648354+00
d569abe7-7b7b-4909-9dbc-f1b785c5702c	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1: Knockout #1	{"match_id": "feccbacb-408f-4b70-a07b-d1adceba770b"}	2026-03-06 22:54:40.360528+00
57ab0724-e8d1-41a5-9b4e-9b8e7a11a774	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1: Knockout #3	{"match_id": "f17f85d5-c9c3-4e94-af29-d69e311d33c8"}	2026-03-06 22:55:03.708859+00
5ea4085a-8e24-4839-9684-47f1395a5655	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1: Knockout #3	{"match_id": "f17f85d5-c9c3-4e94-af29-d69e311d33c8"}	2026-03-06 22:55:09.252655+00
e2bf80bf-6cb1-4a3f-a096-5d9362f2cf2b	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1: Knockout #2	{"match_id": "98a601bb-d866-4bb5-b415-1c41a80d4b03"}	2026-03-06 22:55:28.881634+00
36e71163-d911-4687-a7dc-818540a24c42	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1: Knockout #2	{"match_id": "98a601bb-d866-4bb5-b415-1c41a80d4b03"}	2026-03-06 22:55:33.869148+00
43cd3156-b7fd-4932-a626-97e34b73122e	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 1, "round": "Round 2: BO3", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:55:50.155664+00
d8a6702d-7c95-4354-a542-23f96f84b5dd	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #1	{"match_id": "feccbacb-408f-4b70-a07b-d1adceba770b"}	2026-03-06 22:56:24.340893+00
93b60d79-6a24-4af9-8820-fad912ab5533	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #3	{"match_id": "f17f85d5-c9c3-4e94-af29-d69e311d33c8"}	2026-03-06 22:56:26.916468+00
5de0ef95-c2d1-4b09-b438-7b8e3ab0546e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1: Knockout #2	{"match_id": "98a601bb-d866-4bb5-b415-1c41a80d4b03"}	2026-03-06 22:56:30.998966+00
976072cd-5d35-48a8-95d1-09298eb6cbfc	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 2: BO3 #1	{"match_id": "6e7b4f52-f0c2-432d-a6df-b71f7c3607f8"}	2026-03-06 22:56:33.650784+00
53e0486d-d9a8-40c5-9efd-207afcc900d5	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 3, "round": "Round 1: Knockout", "game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4"}	2026-03-06 22:56:39.106305+00
0b294274-2a53-4bd3-b9c2-97ab302f1171	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "disqualified"}	2026-03-06 23:07:22.987862+00
75f0d751-4d42-4168-9bb4-c2567ffe6fd3	94a14681-63d4-4771-b283-f2d65a2717d5	Re-qualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "qualified"}	2026-03-06 23:07:29.405852+00
cd2a2c86-9ad8-452f-9381-2186580eaf09	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "disqualified"}	2026-03-06 23:08:51.101376+00
3816c2f7-ef21-44a4-9cb9-3bff606c1456	94a14681-63d4-4771-b283-f2d65a2717d5	Re-qualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "qualified"}	2026-03-06 23:09:33.987792+00
56801254-59ff-4403-9edc-eb410b9990b2	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "disqualified"}	2026-03-06 23:11:38.562121+00
16199f3f-4c2a-4a2e-93af-bdf0768a8298	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "disqualified"}	2026-03-06 23:11:38.562813+00
874b8f6b-4233-4e2b-988f-52862235fa98	94a14681-63d4-4771-b283-f2d65a2717d5	Re-qualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "qualified"}	2026-03-06 23:11:52.451488+00
26e74fbd-6254-4f9c-87cf-9859ba926f92	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "disqualified"}	2026-03-06 23:12:00.33403+00
5fa74d04-c7a1-4d89-b838-2cb37142789e	94a14681-63d4-4771-b283-f2d65a2717d5	Re-qualified team: Team OG	{"game": "BGMI", "team_id": "6bb1896c-d706-4a9b-8e01-57d35fe863d0", "new_status": "qualified"}	2026-03-06 23:12:21.810516+00
5fd2409f-e592-422c-876c-25af68d9848c	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "match_id": "4000222b-ea87-463d-b83f-a2e6f17b0667"}	2026-03-07 02:37:34.205312+00
5a91f804-6b71-43af-854c-6317808be770	94a14681-63d4-4771-b283-f2d65a2717d5	Updated team: 9/11 PILOTS 	{"team_id": "efbe9dde-5da8-4fe3-bdc7-5c3e3eff4171"}	2026-03-07 02:48:20.648629+00
36580d1a-124d-4ed3-8732-57387fbc18d9	9e5339c5-a706-4ae3-aaa7-beda00fc88ea	Updated match: Round 1 #1	{"match_id": "4000222b-ea87-463d-b83f-a2e6f17b0667"}	2026-03-07 02:50:42.710777+00
9f7988f3-f6f3-4409-8e11-af0db50298ba	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1:  #1	{"match_id": "122cecac-6cd0-40c1-b033-8a22c6b179d0"}	2026-03-07 03:03:34.987669+00
585ee37d-1e32-48cb-b196-1aa03f80fcce	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1:  #2	{"match_id": "c529f1e7-d506-4068-8f58-4430dfee2aab"}	2026-03-07 03:03:41.512928+00
3570c497-c6a8-4995-a81f-900f6cc6f81c	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1:  #3	{"match_id": "adffd857-649c-43a2-b7d9-afb75ae678cd"}	2026-03-07 03:03:47.093368+00
2e7f0958-1a31-4df0-8936-9f01c1636896	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: kavyansh@gmail.com (admin)	{"role": "admin", "new_user_id": "bf18986c-e856-48aa-a3c8-565387234507"}	2026-03-07 04:06:21.087045+00
94645d95-6b71-4291-b8e0-8e5c2dec473d	9e5339c5-a706-4ae3-aaa7-beda00fc88ea	Updated results for: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 05:43:06.681278+00
4d867c4a-0259-4489-9df0-e98cbf76be38	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 05:52:39.98046+00
f35e99a7-c0a2-404f-a6da-786e5ebf00b8	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 05:53:38.245528+00
5d4a1f93-309d-42b6-96b4-26d5ace4db8e	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Rujul yerne	{"game": "F1", "team_id": "30c72e95-c8b4-4681-b686-edc1cea3921b", "new_status": "disqualified"}	2026-03-07 05:59:11.69387+00
c8bd1487-4695-4185-9087-71911c6e80c7	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #6	{"match_id": "75ec8738-f4b0-4888-a82c-0b812453cf82"}	2026-03-07 06:30:13.477367+00
8f76de24-37cb-484c-befd-cf366b059165	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #6	{"match_id": "75ec8738-f4b0-4888-a82c-0b812453cf82"}	2026-03-07 06:30:24.093242+00
e954d07a-1327-48e0-9c6e-ecc0ddbf6ed9	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #8	{"match_id": "667f105a-a13f-4fb8-a482-2024949f0968"}	2026-03-07 07:05:05.405457+00
cdd0cb5a-be29-4953-9b5b-9a292da7f3f0	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #8	{"match_id": "667f105a-a13f-4fb8-a482-2024949f0968"}	2026-03-07 07:05:57.784517+00
e789a1ad-a664-4db8-90e4-4a28981bd45c	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #8	{"match_id": "667f105a-a13f-4fb8-a482-2024949f0968"}	2026-03-07 07:06:17.213346+00
2b92f219-3f76-4754-a2cd-210f7ff2a5c9	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 07:36:51.809102+00
cbe1aa44-bf59-4f37-b562-54f4dd02bdc1	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 07:40:38.593722+00
a386a593-cd70-49a0-bcef-1c2e3c4e2e6d	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #7	{"match_id": "61118d73-b931-459a-8d4b-1240dd2c3d53"}	2026-03-07 07:45:55.043577+00
a14f7ced-3963-4cf5-8c20-f0d8f859ebd6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #7	{"match_id": "61118d73-b931-459a-8d4b-1240dd2c3d53"}	2026-03-07 07:46:11.755272+00
247f014d-5677-497e-962d-708d7cb80359	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #4	{"match_id": "8982da35-15f4-4db7-8583-99428b755e15"}	2026-03-07 07:46:43.750733+00
8efc9f6a-2c1f-4527-a5e4-3f2561a847e4	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #4	{"match_id": "8982da35-15f4-4db7-8583-99428b755e15"}	2026-03-07 07:46:57.498192+00
88f32bc4-ea15-44fd-ac24-b3cc10e2b221	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for F1	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455", "entries_count": 6}	2026-03-07 07:50:05.944446+00
215752f3-38cd-4ddd-b4e3-8bde349afa6c	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for F1	{"game_id": "d5e2e87f-b319-4c36-8dbd-0570471ee455", "entries_count": 6}	2026-03-07 07:50:51.999803+00
e8731b8b-d3b3-4ec1-99b2-e76a2f4b811a	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Qualifiers (Time Trial) #1	{"match_id": "65066cd1-1dce-4dfc-ad4f-178952722d59"}	2026-03-07 07:53:16.463771+00
490b2524-229b-4679-9a82-da2c02c27657	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #5	{"match_id": "f7d9edd7-161a-4ed6-a3f6-894b45b368e9"}	2026-03-07 07:57:27.540348+00
405a8a7d-38f8-46d3-99a0-0c219c8caa8b	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #5	{"match_id": "f7d9edd7-161a-4ed6-a3f6-894b45b368e9"}	2026-03-07 07:57:38.192882+00
af33a202-b56f-476b-82c0-7ec0fc5c4e01	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: rehan@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "e0a021fc-bcdb-4a3f-831f-b755f34937cd"}	2026-03-07 07:58:53.333417+00
79ef3d8e-fee6-4bf4-94b7-a5864657c10a	94a14681-63d4-4771-b283-f2d65a2717d5	Created user: arav@gmail.com (game_leader)	{"role": "game_leader", "new_user_id": "7f77c219-1b2e-4eec-ba2e-0051b3ecee13"}	2026-03-07 07:59:14.420284+00
3303aff7-9cd8-4927-bb17-5db3471fe618	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: rehan@gmail.com (role → game_leader)	{"target_user_id": "e0a021fc-bcdb-4a3f-831f-b755f34937cd"}	2026-03-07 07:59:20.973723+00
31515201-433a-47a9-979a-35428562c48d	94a14681-63d4-4771-b283-f2d65a2717d5	Updated user: arav@gmail.com (role → game_leader)	{"target_user_id": "7f77c219-1b2e-4eec-ba2e-0051b3ecee13"}	2026-03-07 07:59:28.534318+00
f08a6fb7-cca5-48ab-b307-d6b6017926eb	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Rehan	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-07 08:00:22.915053+00
0da46aa9-33c2-48a1-bc79-9f9c27cd3c51	94a14681-63d4-4771-b283-f2d65a2717d5	Created team: Arav	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-07 08:00:34.1488+00
cee0cc55-70c2-463a-8cb8-9749095655aa	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "348d0fc5-577f-4842-ac12-1a94d8b0d770"}	2026-03-07 08:03:35.071703+00
3fe15be8-d06e-4f4d-a025-6172c5bd8c0a	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "6bf9571d-aef7-479f-8674-86c9a8791513"}	2026-03-07 08:04:59.637285+00
eb7ee5f1-1b71-4e71-94f0-b91f70e5848e	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 32 #1	{"match_id": "565cbf54-9453-4cac-93ea-983310f2c37d"}	2026-03-07 08:05:08.693173+00
c6af018b-228d-484f-8877-c0f88c83d91e	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "237f13e0-9db3-4fa0-9a50-b9b001ae401f"}	2026-03-07 08:09:54.105445+00
899ca8b0-5c2f-4aca-a82b-1cd420fc520b	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "380e846c-a17f-49b8-be02-8f0d8739efa7"}	2026-03-07 08:10:22.002174+00
5a46e39b-9cdf-4e7a-96ec-79207471b915	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "6bf9571d-aef7-479f-8674-86c9a8791513"}	2026-03-07 08:10:28.190048+00
3c599dd1-5a58-414e-a6b1-5098f6065f3d	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "348d0fc5-577f-4842-ac12-1a94d8b0d770"}	2026-03-07 08:10:31.122424+00
bb630ace-56a5-4521-b755-919a421a9b8f	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "52ed4ed9-229d-4d29-b0a4-316a86751eeb"}	2026-03-07 08:12:36.113478+00
a34f9938-dd1e-4613-9b43-d5afd06ea9c2	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "2a1558c6-0e56-4918-9b1d-39c1a9b4a3e9"}	2026-03-07 08:12:51.622857+00
8cbde1bc-2a24-464c-aab0-6ce212b1b5a1	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "237f13e0-9db3-4fa0-9a50-b9b001ae401f"}	2026-03-07 08:12:55.804624+00
c7728bcd-3577-4ed6-9360-ea03ec9ed057	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "380e846c-a17f-49b8-be02-8f0d8739efa7"}	2026-03-07 08:13:03.748026+00
30319c60-8db5-4088-8cc4-0a1173d0f968	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #9	{"match_id": "514227cb-fbe0-43d4-8e5b-a579e000364b"}	2026-03-07 08:17:14.874325+00
adeb50f9-0030-40bc-b445-745b020d16d8	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #9	{"match_id": "514227cb-fbe0-43d4-8e5b-a579e000364b"}	2026-03-07 08:17:22.834084+00
42ffb2c5-eb36-4315-a63c-169c247c6838	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Krish Prajapati	{"game": "FIFA 25", "team_id": "a1e42367-c38e-40d1-88cb-8ea7916ac3d4", "new_status": "disqualified"}	2026-03-07 08:26:51.361934+00
f061b5d8-06f8-4fde-99dc-e83bd15fe61b	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Jay Patil	{"game": "FIFA 25", "team_id": "a98be024-98de-47d8-b4ee-81ac979e68cc", "new_status": "disqualified"}	2026-03-07 08:27:01.252436+00
6761e422-8d22-45e2-ac61-74d2a1107339	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Rudrapratap Singh	{"game": "FIFA 25", "team_id": "3094153b-b3c5-402f-9995-0bc0b503b95b", "new_status": "disqualified"}	2026-03-07 08:27:11.539367+00
a34bcdf8-e3a6-4b4c-a25b-f6e92119810e	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Nikhil Raulo	{"game": "FIFA 25", "team_id": "39317674-6115-4075-aad8-5224044539d0", "new_status": "disqualified"}	2026-03-07 08:28:11.666894+00
b7334942-1f2f-4cb7-a814-18474d99a094	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Rakshit Pandey	{"game": "FIFA 25", "team_id": "1c74fd33-ccfd-48a2-a16b-86c376af8ab6", "new_status": "disqualified"}	2026-03-07 08:28:20.255908+00
fb442a2f-dc2d-4af0-b563-0ea24f05f94c	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Rishabh Mehta	{"game": "FIFA 25", "team_id": "19d61ac8-c437-46ab-95f2-a383e4e5569f", "new_status": "disqualified"}	2026-03-07 08:28:30.721133+00
f9b5b6ef-e8a9-4b68-98c7-a719783b01f5	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for FIFA 25	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "entries_count": 0}	2026-03-07 08:30:06.566169+00
5712a8a9-8389-4244-86f8-b605bee25f75	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #10	{"match_id": "a029633d-c548-462b-b994-ff046c092279"}	2026-03-07 09:37:10.104322+00
d0ed6942-95fc-4089-99e7-65a21099ad02	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #10	{"match_id": "a029633d-c548-462b-b994-ff046c092279"}	2026-03-07 09:37:16.781551+00
85ff0e3f-dcc4-4361-8557-fae05dcbbfc0	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "52ed4ed9-229d-4d29-b0a4-316a86751eeb"}	2026-03-07 09:50:29.893667+00
722945ed-8d18-4b2b-98a2-1928cfbe4f19	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "52ed4ed9-229d-4d29-b0a4-316a86751eeb"}	2026-03-07 09:51:29.136672+00
5ef7f864-713d-40ab-9fc5-e1ecc04c8c17	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "52ed4ed9-229d-4d29-b0a4-316a86751eeb"}	2026-03-07 09:52:49.415074+00
31b2697a-cee5-432b-a001-484fa89a8d44	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "67180e31-fd9c-424c-b25a-f4cbb9a50d3e"}	2026-03-07 09:56:41.507144+00
09ef9436-abc9-452b-9909-cc5d7de96f3a	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "67180e31-fd9c-424c-b25a-f4cbb9a50d3e"}	2026-03-07 09:57:00.725943+00
401d8db2-69af-49de-80b7-22e7bffc3078	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "52ed4ed9-229d-4d29-b0a4-316a86751eeb"}	2026-03-07 09:57:10.669312+00
cf9043d4-fe59-4a9f-9a3b-56f6d5014959	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Arav	{"game": "FIFA 25", "team_id": "27841588-dece-4e64-b6d5-ff47fe980c78", "new_status": "disqualified"}	2026-03-07 10:04:55.978629+00
7233356c-2cb9-4d76-bcb9-ce798dc51c64	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #3	{"match_id": "a3d21764-5a65-4c31-add6-e6fe61172823"}	2026-03-07 10:06:16.552419+00
ff245ee8-df7a-403f-b3c2-40a2e678b24e	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #3	{"match_id": "a3d21764-5a65-4c31-add6-e6fe61172823"}	2026-03-07 10:06:23.061791+00
43526dd8-2eb9-4d93-ae9d-89bd01b78555	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Jason Philip	{"game": "FIFA 25", "team_id": "b642afd0-88a7-4eec-809b-61b1b75c6e7e", "new_status": "disqualified"}	2026-03-07 10:06:38.851126+00
2ce26f99-2beb-45f7-b0f1-4b9706c7e456	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round of 32 #2	{"match_id": "d10fe520-c630-411d-b3df-d67c3edccccf"}	2026-03-07 10:14:42.03163+00
369e41e4-257d-4e76-b2ca-25894c8c38e5	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round of 32 #2	{"match_id": "d10fe520-c630-411d-b3df-d67c3edccccf"}	2026-03-07 10:14:55.046799+00
18eaebf3-0f8a-4fa5-82c2-277b387a8e5d	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Deepankar Paul	{"game": "FIFA 25", "team_id": "2ab64636-26cc-4aa8-a283-a58bd11c87b5", "new_status": "disqualified"}	2026-03-07 10:15:06.155684+00
36eb64a7-2695-49d0-993c-96813e8d837f	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "2a1558c6-0e56-4918-9b1d-39c1a9b4a3e9"}	2026-03-07 10:34:16.809192+00
e1f304d7-cd03-42c3-afb7-5ef9069a9c06	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "2a1558c6-0e56-4918-9b1d-39c1a9b4a3e9"}	2026-03-07 10:34:23.221381+00
f43bdc96-1fa4-449d-b4d9-b47ba89b5a57	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "f7ff55f6-c382-48dd-ae82-dc03c00fde1c"}	2026-03-07 10:34:48.684538+00
06909382-41ee-49cb-b0a5-91e3cb4478c6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "f7ff55f6-c382-48dd-ae82-dc03c00fde1c"}	2026-03-07 10:35:01.485816+00
c739c544-58b3-4e83-bb49-a35e38c2f20f	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "f7ff55f6-c382-48dd-ae82-dc03c00fde1c"}	2026-03-07 10:35:40.753188+00
c78ad908-c159-4373-b9b4-ab82e68f4296	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "2a1558c6-0e56-4918-9b1d-39c1a9b4a3e9"}	2026-03-07 10:35:43.815258+00
bf422588-4d3d-4bf2-80ac-7181d2a825ba	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "f7ff55f6-c382-48dd-ae82-dc03c00fde1c"}	2026-03-07 10:35:51.507676+00
e308476b-0fec-4394-b5fd-9a7682b82758	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "2a1558c6-0e56-4918-9b1d-39c1a9b4a3e9"}	2026-03-07 10:35:52.881943+00
b3e1bdcf-cd88-46e8-8341-104da70adab5	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "67012bde-a466-4555-9700-7f04e163c0bb"}	2026-03-07 10:36:19.268067+00
23dd6564-817e-4504-b9d6-fa2dd83a3b34	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Aryan	{"game": "FIFA 25", "team_id": "6d8ce91a-6b8b-49a4-826d-1da46b46b2b8", "new_status": "disqualified"}	2026-03-07 10:37:01.428252+00
33e49ca1-859f-47c2-9349-f14c62ec3412	94a14681-63d4-4771-b283-f2d65a2717d5	Generated bracket fixtures	{"count": 4, "round": "Round of 16", "game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e"}	2026-03-07 10:37:18.242883+00
c192c0a3-6687-4f8c-9e89-5e5260c0cd81	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round 1 #1	{"match_id": "67012bde-a466-4555-9700-7f04e163c0bb"}	2026-03-07 10:36:39.439056+00
d49260fb-4043-403d-bd4e-2594ffea1fd5	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Shlok Katwate	{"game": "FIFA 25", "team_id": "337648e5-2b97-4dfb-81b0-d113b94c3745", "new_status": "disqualified"}	2026-03-07 10:38:44.822323+00
f02529ac-6258-4478-a1c0-6be86da9bcd8	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 16 #2	{"match_id": "cb2cf46a-3b14-46d4-a9a2-415ac6679a08"}	2026-03-07 10:39:32.898222+00
8d4b1e71-c3b0-4461-8ee9-6d4a085b379a	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 16 #1	{"match_id": "0d44f913-0844-4ba2-b3a2-dc0cafb44e5b"}	2026-03-07 10:39:35.226497+00
3f88c4fc-1f0a-4ba9-bb8d-2124bc202b62	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 16 #3	{"match_id": "1fc2f066-2461-4c23-b3f1-ba27e0bb24e5"}	2026-03-07 10:39:36.713373+00
811d569f-f499-4b24-8c21-ae1ec03472ef	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Round of 16 #4	{"match_id": "2752c31a-483b-4724-b97f-e190ac6cc736"}	2026-03-07 10:39:38.70685+00
6e34a5f2-9373-4c19-ab56-2b01b213b5f9	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "35dda51f-8733-40b4-b3fe-515b40c49657"}	2026-03-07 10:44:19.149334+00
25cb6a6e-28fc-46cb-85b3-7d5c2d798cad	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #2	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "0f3701c3-fa9e-4f24-a92f-09dc3c667c80"}	2026-03-07 10:44:50.627662+00
eb3f790e-d4b6-42a7-9b6a-3ca97aba170c	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #3	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "2fb11401-13e9-4321-b923-aa0731648cae"}	2026-03-07 10:45:24.901377+00
bcd48f8f-7cd1-4f1e-afdb-b7a6f7bf7eb5	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #5	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "f4d481d6-d5ea-4130-a6e0-86ffcb2e5d1c"}	2026-03-07 10:45:55.87478+00
352ff387-2677-4867-9d22-5904c8da5c1e	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "7c4d6314-e379-4c1a-a860-d9b02d318cf2"}	2026-03-07 10:46:30.929463+00
7a2efa72-3006-4ff4-969d-29ef350632ab	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-07 21:12:03.030414+00
fa8d8d63-d15e-48a5-860d-d52e76e2e874	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-07 21:14:49.232868+00
82e4fc23-b975-455b-9414-8a7024511163	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-07 21:29:34.561473+00
477a27c3-2a6b-47f1-99ff-d29c453afb4b	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-07 21:29:43.940197+00
3745db37-e9da-44aa-8b3b-ef16de402df4	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-07 21:30:00.596717+00
82dafda7-1d34-4cae-939b-cb9c060bec7f	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Quad #1	{"match_id": "7c4d6314-e379-4c1a-a860-d9b02d318cf2"}	2026-03-08 05:06:42.621551+00
1fa84412-0706-41b7-a9c6-d9fdc3782191	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Round 1 #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "5c482e07-bf9f-4aaf-8fbb-c802feede07f"}	2026-03-08 05:07:41.264711+00
63e2d32b-b7a0-4a3f-8578-c19d097b4e80	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Round 1 #1	{"match_id": "5c482e07-bf9f-4aaf-8fbb-c802feede07f"}	2026-03-08 05:07:50.29428+00
80e3652a-4cf1-4326-b89f-79cdbd788bed	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "7c4d6314-e379-4c1a-a860-d9b02d318cf2"}	2026-03-08 05:07:59.230685+00
64afae8f-48f0-4a9d-80d6-72c5fe353748	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Nilansh Singhal	{"game": "FIFA 25", "team_id": "bd380d9b-fc7f-4f19-9775-d1ec4be7c549", "new_status": "disqualified"}	2026-03-08 05:08:14.227637+00
be5a772e-20bb-4000-9c02-1144fb0cd2a4	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "bf9a4db8-b065-4ce6-9eaa-82aca460cf8a"}	2026-03-08 05:09:51.072978+00
f704bb76-3630-4273-83b7-6e85fe42ddf7	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "897eaf01-cded-4bc0-bc35-8576dec82d95"}	2026-03-08 05:10:08.404095+00
eccec8bf-3553-4d95-8029-d7397a1313b0	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #2	{"match_id": "0f3701c3-fa9e-4f24-a92f-09dc3c667c80"}	2026-03-08 05:10:16.618776+00
0e9cd54a-d082-4c9a-ac9a-48a8b40632ea	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #3	{"match_id": "2fb11401-13e9-4321-b923-aa0731648cae"}	2026-03-08 05:10:18.778196+00
1f5ea8d1-d79d-42b5-8766-d4429e8d70f2	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "b3d8635f-31d3-4e32-8f17-f3f4cea01ab2"}	2026-03-08 05:19:01.648953+00
082722e5-c470-4a85-842e-567247aafaef	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "8ff67c1c-b40c-4dd9-b394-edbe3c0a8cb8"}	2026-03-08 05:19:21.160359+00
7862f591-2e05-4751-84c5-6710693b47de	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #5	{"match_id": "f4d481d6-d5ea-4130-a6e0-86ffcb2e5d1c"}	2026-03-08 05:19:26.089435+00
2e1574c7-3b75-4d2d-9673-1f7409354bb7	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "35dda51f-8733-40b4-b3fe-515b40c49657"}	2026-03-08 05:19:29.45834+00
5e838c80-5981-46a1-bc55-2b02387bd729	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "5b363c7a-a89b-4040-909f-291db81426b0"}	2026-03-08 05:20:19.23675+00
b916c57a-4426-4977-90a9-8649dc37759b	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "897eaf01-cded-4bc0-bc35-8576dec82d95"}	2026-03-08 05:20:23.145801+00
0ed867a9-bbe9-4900-8ab9-dd039c3941b3	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "a853a7ce-93ee-4db5-9961-e23f3d1fc9a4"}	2026-03-08 05:24:31.927371+00
7ab89df2-264e-493e-bc9a-136ba1817c21	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "8ff67c1c-b40c-4dd9-b394-edbe3c0a8cb8"}	2026-03-08 05:24:38.23536+00
6c0df8bf-7537-4bfd-8e12-9fddf7bfdb45	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "3a5d8d20-0794-42ef-9198-94a3aa0a570d"}	2026-03-08 05:25:01.314511+00
08f747b8-9769-49e6-b299-8623e8e09d17	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "b3d8635f-31d3-4e32-8f17-f3f4cea01ab2"}	2026-03-08 05:25:04.517781+00
6455c55e-d98e-4071-b56c-0d4dfb4cc050	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "4f19d214-56d1-45e7-9021-acb21e25c7b6"}	2026-03-08 05:25:22.438313+00
3fd6daee-1627-42cf-9da1-936fb7621148	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "bf9a4db8-b065-4ce6-9eaa-82aca460cf8a"}	2026-03-08 05:25:25.25899+00
f39ebe12-cf6b-44a5-bd16-dcc8491057eb	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Quad #1	{"match_id": "5b363c7a-a89b-4040-909f-291db81426b0"}	2026-03-08 05:27:56.435417+00
401ba999-53f6-4d8d-a2e6-9de0dc03de31	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Nikunj Goyal	{"game": "FIFA 25", "team_id": "978428dc-539b-413a-a9c7-a08b1f4fbc33", "new_status": "disqualified"}	2026-03-08 05:28:04.746743+00
16d5a822-a116-4def-961e-474eaf38987c	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "b0da69f2-572c-42ac-a974-e04242aae9a2"}	2026-03-08 05:41:27.878825+00
0f0f0c8a-a28d-4138-8825-b48fb0b1400c	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Quad #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "dd88c40e-d8db-460d-9e79-597b04045192"}	2026-03-08 05:41:46.946844+00
fe0fa775-99bb-48c7-93c1-fabd7cb6f7d7	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "4f19d214-56d1-45e7-9021-acb21e25c7b6"}	2026-03-08 05:41:52.027216+00
b283c667-7a08-4d88-b8d3-a9efcc458037	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "3a5d8d20-0794-42ef-9198-94a3aa0a570d"}	2026-03-08 05:41:55.237997+00
95406015-d0d3-45e7-a980-939bccdaf703	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Quad #1	{"match_id": "b0da69f2-572c-42ac-a974-e04242aae9a2"}	2026-03-08 05:59:36.319434+00
ed6c1360-af60-40ce-b7b2-2f265b6c2de5	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Quad #1	{"match_id": "b0da69f2-572c-42ac-a974-e04242aae9a2"}	2026-03-08 05:59:42.271357+00
8d4ef765-5611-4d88-b0c4-9a089b97fd85	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "dd88c40e-d8db-460d-9e79-597b04045192"}	2026-03-08 06:20:25.66911+00
d3b19ff0-f89b-4c4d-be40-c073a84efd73	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Quad #1	{"match_id": "a853a7ce-93ee-4db5-9961-e23f3d1fc9a4"}	2026-03-08 06:20:27.428425+00
6fc936f6-3c16-47a2-b787-0fe87755fbd1	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Hemant	{"game": "FIFA 25", "team_id": "235cbc38-03e2-4845-a55c-1a8419cfc850", "new_status": "disqualified"}	2026-03-08 06:20:39.61134+00
13d45c74-eac2-47e8-8946-168cb3e2fba0	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Jayesh Mandloi	{"game": "FIFA 25", "team_id": "85bba676-5457-473c-bc04-57ec51c50d83", "new_status": "disqualified"}	2026-03-08 06:20:44.993615+00
68ae7327-959e-4e38-afda-8591fb0bc27f	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Shauryadeep Singh	{"game": "FIFA 25", "team_id": "733a172f-b6a7-454a-9752-4ea13cc2c1ed", "new_status": "disqualified"}	2026-03-08 06:21:04.029296+00
ad52cd2f-5a0b-4d19-bf3d-d27f8841ee71	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Semis #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225"}	2026-03-08 06:22:55.91683+00
c7761b90-5ba8-4d3e-aa4d-7f2ac7929a26	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Semis #1	{"match_id": "1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225"}	2026-03-08 06:23:39.245879+00
3cdbf060-e6f9-4cba-bf20-1d77a61b9c8c	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Semi #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "e03f5958-8566-4ce0-99d1-f6a176c3e19e"}	2026-03-08 06:24:00.565174+00
55ed25b1-cd3d-4f10-835f-c32fe5a59577	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Semi #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "4f70329b-42c9-4a4c-962f-519b9b4dc363"}	2026-03-08 06:24:21.213761+00
df4edcd9-a6a0-4fd2-b81b-4920adfebb9d	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Semi #1	{"match_id": "e03f5958-8566-4ce0-99d1-f6a176c3e19e"}	2026-03-08 06:52:19.917785+00
9c48d00f-1ec3-4982-a8dd-0e543e9b6fa6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Semi #1	{"match_id": "e03f5958-8566-4ce0-99d1-f6a176c3e19e"}	2026-03-08 06:52:26.035436+00
7b44230e-0d82-479a-96df-aba4ae92cfe8	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Semi #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "39474f6f-b9e2-432e-b886-4869a45e7925"}	2026-03-08 06:54:02.514782+00
61308a30-d075-410e-982b-3dd002f45a2d	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Semis #1	{"match_id": "1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225"}	2026-03-08 06:54:09.698156+00
39a6be12-9940-4a6e-a500-ceefe5642975	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Semis #1	{"match_id": "1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225"}	2026-03-08 06:54:14.937483+00
b965e80a-8868-4557-a695-fc32b19ad399	94a14681-63d4-4771-b283-f2d65a2717d5	Deleted match: Semi #1	{"match_id": "4f70329b-42c9-4a4c-962f-519b9b4dc363"}	2026-03-08 06:54:19.194025+00
65a9d2a8-d915-4200-a658-6cabebc781db	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Jashraj	{"game": "FIFA 25", "team_id": "4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa", "new_status": "disqualified"}	2026-03-08 06:54:29.467581+00
7fbe9068-4b35-491f-af0b-1232a7b98e96	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Yash Patil	{"game": "FIFA 25", "team_id": "e0ee6fe8-e915-4158-9568-fbd5ba69974f", "new_status": "disqualified"}	2026-03-08 06:54:33.081602+00
bbdc1dac-ee3e-4712-8a07-b0f0e2d33ab6	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1 #1	{"match_id": "4000222b-ea87-463d-b83f-a2e6f17b0667"}	2026-03-08 07:26:11.035942+00
f1c9c517-2116-4872-8685-5924fc8aae8a	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1 #1	{"match_id": "4000222b-ea87-463d-b83f-a2e6f17b0667"}	2026-03-08 07:26:52.445982+00
2531ec7f-5b2c-4e87-82a2-b34896ad2779	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Round 1 #1	{"match_id": "4000222b-ea87-463d-b83f-a2e6f17b0667"}	2026-03-08 07:27:17.695437+00
e159d704-5b2a-4bcb-8afe-81c4679c0bd9	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Semi #1	{"match_id": "39474f6f-b9e2-432e-b886-4869a45e7925"}	2026-03-08 07:29:59.293078+00
c4a18094-cc23-4508-b3bb-3f325ad6b900	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Semi #1	{"match_id": "39474f6f-b9e2-432e-b886-4869a45e7925"}	2026-03-08 07:30:05.378941+00
b995a68f-3116-47d9-a4fd-2ed7c7866081	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Rohan Painter	{"game": "FIFA 25", "team_id": "496413d3-13f1-483f-9ff3-73616550d122", "new_status": "disqualified"}	2026-03-08 07:30:12.685346+00
a9b088d1-62a9-4ddc-8634-15cfc10eb8b0	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-08 07:43:54.258323+00
08bce237-743b-4156-af4c-49684021164e	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: Semi #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7"}	2026-03-08 07:47:02.008283+00
b9c3fd3f-139c-4c6f-94d0-20baa8ac41b8	94a14681-63d4-4771-b283-f2d65a2717d5	Updated match: Semi #1	{"match_id": "7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7"}	2026-03-08 07:47:24.865511+00
295cc308-1e90-427f-a586-2ae67d8f2cd2	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: Semi #1	{"match_id": "7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7"}	2026-03-08 07:55:16.376705+00
6a61b166-53c2-4bd9-9311-ab6d3de9f83d	94a14681-63d4-4771-b283-f2d65a2717d5	Disqualified team: Nigel Menezes	{"game": "FIFA 25", "team_id": "de739ccb-f695-454d-8ffc-ce8fa7fb74c2", "new_status": "disqualified"}	2026-03-08 07:55:25.784171+00
a19beea2-6062-4401-8e98-c411e38773c7	94a14681-63d4-4771-b283-f2d65a2717d5	Created match: FINALS #1	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "match_id": "b2a9282f-63de-451b-9f14-7afc38fed60e"}	2026-03-08 07:57:01.942957+00
9e5657f5-3bcf-4b5a-8893-97f0b3ae9d4b	94a14681-63d4-4771-b283-f2d65a2717d5	Updated results for: FINALS #1	{"match_id": "b2a9282f-63de-451b-9f14-7afc38fed60e"}	2026-03-08 08:34:06.929765+00
52566f8f-0ac0-4eb9-af31-66669a44af73	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for FIFA 25	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "entries_count": 2}	2026-03-08 09:34:42.630581+00
4734bfdd-ea21-4853-8b5a-6a34fd68e489	94a14681-63d4-4771-b283-f2d65a2717d5	Re-qualified team: Nigel Menezes	{"game": "FIFA 25", "team_id": "de739ccb-f695-454d-8ffc-ce8fa7fb74c2", "new_status": "qualified"}	2026-03-08 09:34:53.038318+00
c6af04b2-4d52-4d6f-8e29-a17b02f45f46	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for FIFA 25	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "entries_count": 3}	2026-03-08 09:35:02.893797+00
2d8dbf92-bc81-4220-8d25-3a9c57984e8c	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for VALORANT	{"game_id": "62bb5f98-4326-4364-b02e-8f58f85aa1b4", "entries_count": 3}	2026-03-08 09:36:08.813745+00
88a8e498-0a5c-4c66-8b96-cc9f3c3d124d	94a14681-63d4-4771-b283-f2d65a2717d5	Manually edited leaderboard for FIFA 25	{"game_id": "d379dcab-b19d-4dc9-9447-eaa173e3c96e", "entries_count": 3}	2026-03-08 09:37:12.942638+00
c46f7800-dcf4-4c40-9540-07b4392a6076	9e5339c5-a706-4ae3-aaa7-beda00fc88ea	Manually edited leaderboard for BGMI	{"game_id": "8b790a72-0135-48d2-8d4c-308ebf20d5d7", "entries_count": 11}	2026-03-11 05:30:48.875899+00
\.


--
-- Data for Name: games; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.games (id, name, slug, max_teams, created_at) FROM stdin;
8b790a72-0135-48d2-8d4c-308ebf20d5d7	BGMI	bgmi	16	2026-02-21 11:50:02.039521+00
62bb5f98-4326-4364-b02e-8f58f85aa1b4	VALORANT	valorant	12	2026-02-21 11:50:02.039521+00
d379dcab-b19d-4dc9-9447-eaa173e3c96e	FIFA 25	fifa25	32	2026-02-21 11:50:02.039521+00
d5e2e87f-b319-4c36-8dbd-0570471ee455	F1	f1	20	2026-02-21 11:50:02.039521+00
\.


--
-- Data for Name: leaderboards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.leaderboards (id, game_id, team_id, total_points, total_kills, matches_played, wins, rank, extra_data, updated_at) FROM stdin;
e05e8522-6449-4aef-a5d3-d60bb8751285	d5e2e87f-b319-4c36-8dbd-0570471ee455	1b77b920-2df1-492e-ab74-c6f2fb9a3c18	0	0	1	0	1	{"best_time_ms": 108}	2026-03-08 07:26:28.732979+00
9efb3aad-c502-41c0-a929-ef662918364f	d5e2e87f-b319-4c36-8dbd-0570471ee455	65ee7087-4d43-4a0c-88e7-7b7e3a3b0cc4	0	0	1	0	2	{"best_time_ms": 110}	2026-03-08 07:26:28.732979+00
cc126d35-8d98-4612-9832-c9c7f0b35e77	d5e2e87f-b319-4c36-8dbd-0570471ee455	71678b2e-a79d-4e70-8c3c-23a71d7a432b	0	0	1	0	3	{"best_time_ms": 111}	2026-03-08 07:26:28.732979+00
c9843ead-ef05-4552-974c-ac18af01d468	d5e2e87f-b319-4c36-8dbd-0570471ee455	4b22a07d-a9bd-4d66-a342-c0a76e3b6011	0	0	1	0	4	{"best_time_ms": 119}	2026-03-08 07:26:28.732979+00
07bfe6bb-4137-48a5-b159-3653f373283f	d5e2e87f-b319-4c36-8dbd-0570471ee455	41c88bb3-ac01-4976-a34f-14364d5847e2	0	0	1	0	5	{"best_time_ms": 143}	2026-03-08 07:26:28.732979+00
dd53f6ce-bde2-42b5-9473-e597eed7830e	d5e2e87f-b319-4c36-8dbd-0570471ee455	bc427e00-9095-4fe5-ab92-1483bd306db9	0	0	1	0	6	{"best_time_ms": 147}	2026-03-08 07:26:28.732979+00
c9b9133d-46f3-4e59-978d-5db7bbc6c9d0	62bb5f98-4326-4364-b02e-8f58f85aa1b4	25f57276-dbf8-4e46-b083-cd5f89fde86d	0	0	0	0	1	{}	2026-03-08 09:36:08.301859+00
de995424-3a03-4bd7-8c17-84884ce219a7	62bb5f98-4326-4364-b02e-8f58f85aa1b4	7dba394c-40e0-4912-99ae-f402afce9647	0	0	0	0	2	{}	2026-03-08 09:36:08.53732+00
cc223411-1051-4e7e-acbe-c59a70f384c8	62bb5f98-4326-4364-b02e-8f58f85aa1b4	59f5eeef-aac5-407a-9caa-32293aef2624	0	0	0	0	3	{}	2026-03-08 09:36:08.679822+00
acff4494-ab4e-479f-8a4e-fbf80e44b242	d379dcab-b19d-4dc9-9447-eaa173e3c96e	0c588117-c80a-4549-97a9-f1c4d7137107	7	0	0	0	1	{}	2026-03-08 09:34:42.449111+00
fd899dc5-8729-4246-9bf3-2783ef6a62ce	d379dcab-b19d-4dc9-9447-eaa173e3c96e	aa4ab848-fda4-44b1-9875-690c46ac0d79	5	0	0	0	2	{}	2026-03-08 09:34:42.308127+00
11a5adf3-5f8b-447e-a9a5-606c825ba712	d379dcab-b19d-4dc9-9447-eaa173e3c96e	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	3	0	0	0	3	{}	2026-03-08 09:35:02.755154+00
\.


--
-- Data for Name: match_results; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.match_results (id, match_id, team_id, score, placement, kills, deaths, time_ms, extra_data, created_at, updated_at) FROM stdin;
91178364-1658-4983-8d0b-6f8ddd63c410	a029633d-c548-462b-b994-ff046c092279	337648e5-2b97-4dfb-81b0-d113b94c3745	0	\N	0	0	\N	{}	2026-03-07 09:37:09.435267+00	2026-03-07 09:37:09.435267+00
679569a1-dce6-4f08-b585-c410ae229d7a	a029633d-c548-462b-b994-ff046c092279	e0ee6fe8-e915-4158-9568-fbd5ba69974f	1	\N	0	0	\N	{}	2026-03-07 09:37:09.685875+00	2026-03-07 09:37:09.685875+00
a4078938-5235-4d24-b22b-7eb91ad60618	b2a9282f-63de-451b-9f14-7afc38fed60e	aa4ab848-fda4-44b1-9875-690c46ac0d79	5	\N	0	0	\N	{}	2026-03-08 08:34:06.563585+00	2026-03-08 08:34:06.563585+00
3353d7c8-84d2-42c8-8155-3f2e0d910892	b2a9282f-63de-451b-9f14-7afc38fed60e	0c588117-c80a-4549-97a9-f1c4d7137107	7	\N	0	0	\N	{}	2026-03-08 08:34:06.737273+00	2026-03-08 08:34:06.737273+00
750a952b-90e6-4c59-9af8-c351a48da093	67180e31-fd9c-424c-b25a-f4cbb9a50d3e	27841588-dece-4e64-b6d5-ff47fe980c78	2	\N	0	0	\N	{}	2026-03-07 09:57:00.425127+00	2026-03-07 09:57:00.425127+00
bf3c1589-ce8c-4af8-96b1-a516a445e137	67180e31-fd9c-424c-b25a-f4cbb9a50d3e	aa4ab848-fda4-44b1-9875-690c46ac0d79	3	\N	0	0	\N	{}	2026-03-07 09:57:00.573214+00	2026-03-07 09:57:00.573214+00
879f94bd-5694-416c-a451-62edb87d50a8	a3d21764-5a65-4c31-add6-e6fe61172823	4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	1	\N	0	0	\N	{}	2026-03-07 10:06:16.259037+00	2026-03-07 10:06:16.259037+00
a64e5944-8238-4860-84a8-329abeaad912	a3d21764-5a65-4c31-add6-e6fe61172823	b642afd0-88a7-4eec-809b-61b1b75c6e7e	0	\N	0	0	\N	{}	2026-03-07 10:06:16.401502+00	2026-03-07 10:06:16.401502+00
c9fa403b-c54d-46a4-b058-6ebe077bfc35	d10fe520-c630-411d-b3df-d67c3edccccf	2ab64636-26cc-4aa8-a283-a58bd11c87b5	3	\N	0	0	\N	{}	2026-03-07 10:14:41.597197+00	2026-03-07 10:14:41.597197+00
b2725af5-ba88-4ec9-9e53-0775d4584c08	d10fe520-c630-411d-b3df-d67c3edccccf	235cbc38-03e2-4845-a55c-1a8419cfc850	6	\N	0	0	\N	{}	2026-03-07 10:14:41.824146+00	2026-03-07 10:14:41.824146+00
91345c7b-cf96-4bd1-959d-256c5a69d1ab	75ec8738-f4b0-4888-a82c-0b812453cf82	39317674-6115-4075-aad8-5224044539d0	0	\N	0	0	\N	{}	2026-03-07 06:30:12.551981+00	2026-03-07 06:30:12.551981+00
fd26db01-2032-4ad8-96f1-cd6bf51682f2	75ec8738-f4b0-4888-a82c-0b812453cf82	978428dc-539b-413a-a9c7-a08b1f4fbc33	9	\N	0	0	\N	{}	2026-03-07 06:30:13.006206+00	2026-03-07 06:30:13.006206+00
a2c48a53-a42b-45b4-bfb1-aa3e0b87ce99	667f105a-a13f-4fb8-a482-2024949f0968	19d61ac8-c437-46ab-95f2-a383e4e5569f	4	\N	0	0	\N	{}	2026-03-07 07:05:04.903521+00	2026-03-07 07:05:57.097374+00
4b704d6b-648c-4e69-a1fd-5ce07a1b8da1	667f105a-a13f-4fb8-a482-2024949f0968	496413d3-13f1-483f-9ff3-73616550d122	7	\N	0	0	\N	{}	2026-03-07 07:05:05.182338+00	2026-03-07 07:05:57.515592+00
1b65d00c-b88f-4b3f-bf83-56418d9c471b	61118d73-b931-459a-8d4b-1240dd2c3d53	bd380d9b-fc7f-4f19-9775-d1ec4be7c549	5	\N	0	0	\N	{}	2026-03-07 07:45:54.71648+00	2026-03-07 07:45:54.71648+00
d0f13b5b-039f-4da8-96cf-cf900ebce5d1	61118d73-b931-459a-8d4b-1240dd2c3d53	1c74fd33-ccfd-48a2-a16b-86c376af8ab6	2	\N	0	0	\N	{}	2026-03-07 07:45:54.895298+00	2026-03-07 07:45:54.895298+00
d401e634-f903-48b6-9598-06387691b448	8982da35-15f4-4db7-8583-99428b755e15	a98be024-98de-47d8-b4ee-81ac979e68cc	2	\N	0	0	\N	{}	2026-03-07 07:46:43.34985+00	2026-03-07 07:46:43.34985+00
70a4e3d8-a907-47c3-8e3c-90593d7865fa	8982da35-15f4-4db7-8583-99428b755e15	85bba676-5457-473c-bc04-57ec51c50d83	11	\N	0	0	\N	{}	2026-03-07 07:46:43.560175+00	2026-03-07 07:46:43.560175+00
d04d4d76-851b-45a4-9bd1-084e5c55f79f	65066cd1-1dce-4dfc-ad4f-178952722d59	1b77b920-2df1-492e-ab74-c6f2fb9a3c18	0	1	0	0	108	{}	2026-03-07 05:43:05.541317+00	2026-03-07 07:53:15.496284+00
2a187d50-a330-4ab7-ba06-8bf8e172f99f	65066cd1-1dce-4dfc-ad4f-178952722d59	30c72e95-c8b4-4681-b686-edc1cea3921b	0	7	0	0	\N	{}	2026-03-07 05:43:05.837238+00	2026-03-07 07:53:15.690575+00
0b7f752c-f222-4259-8372-e0670e32c293	65066cd1-1dce-4dfc-ad4f-178952722d59	41c88bb3-ac01-4976-a34f-14364d5847e2	0	5	0	0	143	{}	2026-03-07 05:43:04.182079+00	2026-03-07 07:53:15.836103+00
37deefd3-99da-432a-9f89-66cbc2332807	65066cd1-1dce-4dfc-ad4f-178952722d59	4b22a07d-a9bd-4d66-a342-c0a76e3b6011	0	4	0	0	119	{}	2026-03-07 05:43:06.096026+00	2026-03-07 07:53:15.966078+00
bbe45ef8-7237-4169-87f9-5f8801c4492c	65066cd1-1dce-4dfc-ad4f-178952722d59	65ee7087-4d43-4a0c-88e7-7b7e3a3b0cc4	0	2	0	0	110	{}	2026-03-07 05:43:03.737093+00	2026-03-07 07:53:16.101881+00
ce5e4f65-520d-40d3-9170-280eecfe91c6	65066cd1-1dce-4dfc-ad4f-178952722d59	71678b2e-a79d-4e70-8c3c-23a71d7a432b	0	3	0	0	111	{}	2026-03-07 05:43:04.729383+00	2026-03-07 07:53:16.227207+00
586b7488-9230-4aa1-ba5a-431be2ae7575	65066cd1-1dce-4dfc-ad4f-178952722d59	bc427e00-9095-4fe5-ab92-1483bd306db9	0	6	0	0	147	{}	2026-03-07 05:43:05.084203+00	2026-03-07 07:53:16.33848+00
836e0878-f6d3-4dc4-84d8-2fc448c4cc91	f7d9edd7-161a-4ed6-a3f6-894b45b368e9	a1e42367-c38e-40d1-88cb-8ea7916ac3d4	0	\N	0	0	\N	{}	2026-03-07 07:57:27.197603+00	2026-03-07 07:57:27.197603+00
33648b13-9ec1-494a-985b-2c5f907bb4e1	f7d9edd7-161a-4ed6-a3f6-894b45b368e9	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	12	\N	0	0	\N	{}	2026-03-07 07:57:27.371838+00	2026-03-07 07:57:27.371838+00
51707cf1-92ce-4979-b58e-cc6005e6c302	514227cb-fbe0-43d4-8e5b-a579e000364b	3094153b-b3c5-402f-9995-0bc0b503b95b	3	\N	0	0	\N	{}	2026-03-07 08:17:14.470604+00	2026-03-07 08:17:14.470604+00
ada623ea-9d0f-4f71-9103-5467379e7a76	514227cb-fbe0-43d4-8e5b-a579e000364b	733a172f-b6a7-454a-9752-4ea13cc2c1ed	4	\N	0	0	\N	{}	2026-03-07 08:17:14.636525+00	2026-03-07 08:17:14.636525+00
d06f9a60-16e6-4cc9-ae8a-3b7061c7177e	5c482e07-bf9f-4aaf-8fbb-c802feede07f	496413d3-13f1-483f-9ff3-73616550d122	1	\N	0	0	\N	{}	2026-03-08 05:07:50.049667+00	2026-03-08 05:07:50.049667+00
dccea554-a69a-44a6-9f69-005f46fc1fa9	5c482e07-bf9f-4aaf-8fbb-c802feede07f	bd380d9b-fc7f-4f19-9775-d1ec4be7c549	0	\N	0	0	\N	{}	2026-03-08 05:07:50.167972+00	2026-03-08 05:07:50.167972+00
41db3746-72ed-4b68-aa51-f6a7ed2b75a4	5b363c7a-a89b-4040-909f-291db81426b0	978428dc-539b-413a-a9c7-a08b1f4fbc33	2	\N	0	0	\N	{}	2026-03-08 05:27:56.194534+00	2026-03-08 05:27:56.194534+00
57ac154c-e0c2-4436-85ae-8dea943adc15	5b363c7a-a89b-4040-909f-291db81426b0	e0ee6fe8-e915-4158-9568-fbd5ba69974f	4	\N	0	0	\N	{}	2026-03-08 05:27:56.320157+00	2026-03-08 05:27:56.320157+00
1e7ab80b-7974-41c1-8ad1-aea4e28adcb6	b0da69f2-572c-42ac-a974-e04242aae9a2	aa4ab848-fda4-44b1-9875-690c46ac0d79	6	\N	0	0	\N	{}	2026-03-08 05:59:35.881304+00	2026-03-08 05:59:35.881304+00
9e52e3e7-469e-452d-8c9b-44a6d56c5162	b0da69f2-572c-42ac-a974-e04242aae9a2	733a172f-b6a7-454a-9752-4ea13cc2c1ed	3	\N	0	0	\N	{}	2026-03-08 05:59:36.115649+00	2026-03-08 05:59:36.115649+00
6744e2a6-e4dc-4926-89dd-b76379dd40ee	e03f5958-8566-4ce0-99d1-f6a176c3e19e	aa4ab848-fda4-44b1-9875-690c46ac0d79	7	\N	0	0	\N	{}	2026-03-08 06:52:19.466869+00	2026-03-08 06:52:19.466869+00
077e0203-8512-478b-9461-142b89ad1fcd	e03f5958-8566-4ce0-99d1-f6a176c3e19e	e0ee6fe8-e915-4158-9568-fbd5ba69974f	3	\N	0	0	\N	{}	2026-03-08 06:52:19.778613+00	2026-03-08 06:52:19.778613+00
2a6d2107-0b26-4741-b83a-d92893d4017b	1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225	0c588117-c80a-4549-97a9-f1c4d7137107	1	\N	0	0	\N	{}	2026-03-08 06:54:09.353172+00	2026-03-08 06:54:09.353172+00
5f3d9be5-47af-4be1-8589-42e27c2e2298	1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225	4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	0	\N	0	0	\N	{}	2026-03-08 06:54:09.476966+00	2026-03-08 06:54:09.476966+00
611e8b4a-951d-4f4e-9582-afe5898d800e	39474f6f-b9e2-432e-b886-4869a45e7925	0c588117-c80a-4549-97a9-f1c4d7137107	6	\N	0	0	\N	{}	2026-03-08 07:29:58.949629+00	2026-03-08 07:29:58.949629+00
c536f1c6-db0d-4436-98d3-5d142bacf4ac	39474f6f-b9e2-432e-b886-4869a45e7925	496413d3-13f1-483f-9ff3-73616550d122	3	\N	0	0	\N	{}	2026-03-08 07:29:59.094668+00	2026-03-08 07:29:59.094668+00
2a08de18-1012-4921-b2c1-90b0ad68c80f	7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7	0c588117-c80a-4549-97a9-f1c4d7137107	6	\N	0	0	\N	{}	2026-03-08 07:55:15.771321+00	2026-03-08 07:55:15.771321+00
f28e14f2-e6c5-4c3e-b26a-a2009b04d66c	7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	3	\N	0	0	\N	{}	2026-03-08 07:55:16.092893+00	2026-03-08 07:55:16.092893+00
\.


--
-- Data for Name: match_teams; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.match_teams (id, match_id, team_id, seed) FROM stdin;
6b3661da-9f0c-487f-8af5-02d935cb8888	39474f6f-b9e2-432e-b886-4869a45e7925	496413d3-13f1-483f-9ff3-73616550d122	\N
908b1095-2882-4220-a95a-bcd1d88345bd	39474f6f-b9e2-432e-b886-4869a45e7925	0c588117-c80a-4549-97a9-f1c4d7137107	\N
8d80d715-273d-4a6d-90f1-fe3953d5a1c1	7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7	0c588117-c80a-4549-97a9-f1c4d7137107	\N
32de74b1-a600-4a99-85ab-37f18a5bbf1b	7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	\N
aee07482-d9af-4608-9752-2b8a0aad2e7a	b2a9282f-63de-451b-9f14-7afc38fed60e	aa4ab848-fda4-44b1-9875-690c46ac0d79	\N
4fe1d259-38da-46ca-99a4-f0c49078c903	b2a9282f-63de-451b-9f14-7afc38fed60e	0c588117-c80a-4549-97a9-f1c4d7137107	\N
9f0eef5a-fc16-40b1-87a5-1bfa250163f1	122cecac-6cd0-40c1-b033-8a22c6b179d0	1df3fc25-a63d-4d49-9f8f-efd77bc12d58	\N
23a1410e-2410-4f1f-8c6c-aabbae395cc5	122cecac-6cd0-40c1-b033-8a22c6b179d0	7dba394c-40e0-4912-99ae-f402afce9647	\N
cbeed01e-7ad1-4a18-8016-d4e21a2cbe6d	c529f1e7-d506-4068-8f58-4430dfee2aab	25f57276-dbf8-4e46-b083-cd5f89fde86d	\N
76135324-a60d-48f4-b1b8-f2492bf4c1db	c529f1e7-d506-4068-8f58-4430dfee2aab	6990f292-0ba9-41cc-a20c-07780a8a27b2	\N
7758cff7-d6fe-42c6-be4a-487159d9d69f	adffd857-649c-43a2-b7d9-afb75ae678cd	59f5eeef-aac5-407a-9caa-32293aef2624	\N
d86882de-27a7-4ade-9bce-edacbb27ad6f	adffd857-649c-43a2-b7d9-afb75ae678cd	84e94daf-e5be-49cd-b1ad-ec9f04e9326a	\N
c59cb8f9-4b14-4373-8a97-a01eda386e36	75ec8738-f4b0-4888-a82c-0b812453cf82	39317674-6115-4075-aad8-5224044539d0	\N
7ab64df5-7893-429f-8add-7ff9eaa67247	75ec8738-f4b0-4888-a82c-0b812453cf82	978428dc-539b-413a-a9c7-a08b1f4fbc33	\N
0d0832eb-98c0-47a8-8776-6682e8e0a705	667f105a-a13f-4fb8-a482-2024949f0968	19d61ac8-c437-46ab-95f2-a383e4e5569f	\N
f7e62982-b8ec-4aa0-a2bc-518a2666b678	667f105a-a13f-4fb8-a482-2024949f0968	496413d3-13f1-483f-9ff3-73616550d122	\N
570d01bd-6a78-4923-b59e-660d698257de	65066cd1-1dce-4dfc-ad4f-178952722d59	1b77b920-2df1-492e-ab74-c6f2fb9a3c18	\N
151a273a-6500-4883-a170-d9b6d4bfc304	65066cd1-1dce-4dfc-ad4f-178952722d59	30c72e95-c8b4-4681-b686-edc1cea3921b	\N
11919017-ec4b-4bd5-af8e-b2288923a113	65066cd1-1dce-4dfc-ad4f-178952722d59	41c88bb3-ac01-4976-a34f-14364d5847e2	\N
e0129721-4bc6-40a9-a8b7-7ae835f266d3	65066cd1-1dce-4dfc-ad4f-178952722d59	4b22a07d-a9bd-4d66-a342-c0a76e3b6011	\N
bf7672b3-54c2-4d4d-bf85-0b61e0d48c15	65066cd1-1dce-4dfc-ad4f-178952722d59	65ee7087-4d43-4a0c-88e7-7b7e3a3b0cc4	\N
33209adc-9b94-4611-938c-e5a7f7d4410c	65066cd1-1dce-4dfc-ad4f-178952722d59	71678b2e-a79d-4e70-8c3c-23a71d7a432b	\N
a283a2b7-f0c7-449e-ab9d-f0cecf4ea608	65066cd1-1dce-4dfc-ad4f-178952722d59	bc427e00-9095-4fe5-ab92-1483bd306db9	\N
f854b23b-4cdf-4582-8df6-bcfde8700221	61118d73-b931-459a-8d4b-1240dd2c3d53	bd380d9b-fc7f-4f19-9775-d1ec4be7c549	\N
74bb2ccf-9805-4c05-a2f0-5c8528cf0f69	61118d73-b931-459a-8d4b-1240dd2c3d53	1c74fd33-ccfd-48a2-a16b-86c376af8ab6	\N
6ec36a89-9c5d-4f04-9284-68da8ac7f14b	8982da35-15f4-4db7-8583-99428b755e15	a98be024-98de-47d8-b4ee-81ac979e68cc	\N
22b60e4d-6f6f-4abc-bbfe-84d28adf0cd3	5c482e07-bf9f-4aaf-8fbb-c802feede07f	bd380d9b-fc7f-4f19-9775-d1ec4be7c549	\N
5adf50f4-1f6b-49e6-b657-f3ce0c031043	5c482e07-bf9f-4aaf-8fbb-c802feede07f	496413d3-13f1-483f-9ff3-73616550d122	\N
865222a8-5c7e-4380-a8f8-22ede5bd7dff	5b363c7a-a89b-4040-909f-291db81426b0	978428dc-539b-413a-a9c7-a08b1f4fbc33	\N
3e934b1a-9ef9-4c69-929c-54892b408528	5b363c7a-a89b-4040-909f-291db81426b0	e0ee6fe8-e915-4158-9568-fbd5ba69974f	\N
8969a45f-b486-42d1-b057-7136928051ab	8982da35-15f4-4db7-8583-99428b755e15	85bba676-5457-473c-bc04-57ec51c50d83	\N
a56730b1-a494-4d92-ae33-4ee9fc981b8b	f7d9edd7-161a-4ed6-a3f6-894b45b368e9	a1e42367-c38e-40d1-88cb-8ea7916ac3d4	\N
74cbe81c-3161-436b-bd3b-a0094ee02452	f7d9edd7-161a-4ed6-a3f6-894b45b368e9	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	\N
2fcd643c-3dc2-47ba-ba99-91f2be5d1c85	b0da69f2-572c-42ac-a974-e04242aae9a2	aa4ab848-fda4-44b1-9875-690c46ac0d79	\N
13a59a39-4643-4e59-8de0-febc44af6682	b0da69f2-572c-42ac-a974-e04242aae9a2	733a172f-b6a7-454a-9752-4ea13cc2c1ed	\N
3300d3dc-3710-4c80-a721-c239988ede5d	514227cb-fbe0-43d4-8e5b-a579e000364b	3094153b-b3c5-402f-9995-0bc0b503b95b	\N
9c695823-55c5-4d0c-babc-ff582bacabaa	514227cb-fbe0-43d4-8e5b-a579e000364b	733a172f-b6a7-454a-9752-4ea13cc2c1ed	\N
ae5432e7-58cc-4265-945b-9c8317045005	a029633d-c548-462b-b994-ff046c092279	337648e5-2b97-4dfb-81b0-d113b94c3745	\N
7d77e274-fd66-4886-a83d-86c0060b7586	a029633d-c548-462b-b994-ff046c092279	e0ee6fe8-e915-4158-9568-fbd5ba69974f	\N
1a753d59-69da-4b22-b166-96e19e45ac58	67180e31-fd9c-424c-b25a-f4cbb9a50d3e	27841588-dece-4e64-b6d5-ff47fe980c78	\N
3090a403-9d15-470e-8336-d77ac6e1f7c6	e03f5958-8566-4ce0-99d1-f6a176c3e19e	aa4ab848-fda4-44b1-9875-690c46ac0d79	\N
a9532dc0-9137-4eb0-bbbe-8c94ea71e87a	e03f5958-8566-4ce0-99d1-f6a176c3e19e	e0ee6fe8-e915-4158-9568-fbd5ba69974f	\N
4b76c96c-25a8-4179-9c7b-6f9a16270472	1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225	0c588117-c80a-4549-97a9-f1c4d7137107	\N
9a95d428-9444-4ac9-9031-421fa58b1db9	1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225	4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	\N
182fde92-36a3-4f44-b8df-0988d96946a5	67180e31-fd9c-424c-b25a-f4cbb9a50d3e	aa4ab848-fda4-44b1-9875-690c46ac0d79	\N
167914cb-48dc-4050-94e7-d5c7ee9f92eb	a3d21764-5a65-4c31-add6-e6fe61172823	4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	\N
54240e3e-2e26-4b2d-be30-648bfd03fb8c	a3d21764-5a65-4c31-add6-e6fe61172823	b642afd0-88a7-4eec-809b-61b1b75c6e7e	\N
fe65110a-0fb3-4e3a-bdfa-7a72d72ba900	d10fe520-c630-411d-b3df-d67c3edccccf	2ab64636-26cc-4aa8-a283-a58bd11c87b5	\N
d6747980-8545-446f-bd7a-e75218861843	d10fe520-c630-411d-b3df-d67c3edccccf	235cbc38-03e2-4845-a55c-1a8419cfc850	\N
b6a6a9cb-1a70-4a2a-94fb-7de515157f25	4000222b-ea87-463d-b83f-a2e6f17b0667	0b335c14-7114-4e06-84e8-e3f82d217b4c	\N
422c4bba-c188-4a90-a655-07bb965d5112	4000222b-ea87-463d-b83f-a2e6f17b0667	10d5175b-55bc-4463-bdb7-2b51bb04c445	\N
d45e05c0-1bae-44a9-8de8-f676b186c227	4000222b-ea87-463d-b83f-a2e6f17b0667	1235a35b-d032-451e-a40c-582ca8eefd70	\N
2ddc7a6f-189a-4257-8f4e-c88d712735cb	4000222b-ea87-463d-b83f-a2e6f17b0667	26e5e4ae-51f5-4247-a5bd-6e72a2583020	\N
dd3ea8d8-e6e9-438c-b10b-127059feb804	4000222b-ea87-463d-b83f-a2e6f17b0667	37e8dc0d-9f70-4d3b-8407-1b79b614288d	\N
d818d5bc-99c0-4e97-bbdf-769e2661a62d	4000222b-ea87-463d-b83f-a2e6f17b0667	6bb1896c-d706-4a9b-8e01-57d35fe863d0	\N
37b51392-3e84-4984-be8b-c35401fe72e7	4000222b-ea87-463d-b83f-a2e6f17b0667	6ed67e6f-2565-4437-b45e-07c61bc0cb42	\N
e28b96de-3b47-4eef-9224-a7b142f826a3	4000222b-ea87-463d-b83f-a2e6f17b0667	9349ba51-c0f8-46c7-b80b-fabeb2b3f1b3	\N
18d4c37d-f4a0-449b-b873-3467f9233ae4	4000222b-ea87-463d-b83f-a2e6f17b0667	a9e091d5-beca-4ffe-8701-2896a285af34	\N
7186f0c6-4db1-43a8-8f3a-f9151c27e1df	4000222b-ea87-463d-b83f-a2e6f17b0667	c9fb77cc-355d-4066-9be5-f296a08f6eee	\N
89fdf4fb-a741-4b7d-91e4-1b1fa8e00fa2	4000222b-ea87-463d-b83f-a2e6f17b0667	efbe9dde-5da8-4fe3-bdc7-5c3e3eff4171	\N
\.


--
-- Data for Name: matches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.matches (id, game_id, round, match_number, status, match_type, best_of, scheduled_at, locked, created_at, updated_at, venue) FROM stdin;
1e0d9c02-6dd4-42ae-bb8e-2ac0c9ffa225	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Semis	1	completed	standard	1	2026-11-11 11:11:00+00	t	2026-03-08 06:22:55.320894+00	2026-03-08 06:54:51.839824+00	\N
122cecac-6cd0-40c1-b033-8a22c6b179d0	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Round 1: 	1	upcoming	standard	1	2026-03-06 22:56:00+00	f	2026-03-06 22:56:39.106305+00	2026-03-07 03:03:34.427238+00	\N
f7d9edd7-161a-4ed6-a3f6-894b45b368e9	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	5	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 10:15:29.638185+00	\N
c529f1e7-d506-4068-8f58-4430dfee2aab	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Round 1: 	2	upcoming	standard	1	2026-03-06 22:56:00+00	f	2026-03-06 22:56:39.106305+00	2026-03-07 03:03:41.019196+00	\N
d10fe520-c630-411d-b3df-d67c3edccccf	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	2	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 10:15:32.899849+00	\N
a3d21764-5a65-4c31-add6-e6fe61172823	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	3	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 10:15:35.180452+00	\N
adffd857-649c-43a2-b7d9-afb75ae678cd	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Round 1: 	3	upcoming	standard	1	2026-03-06 22:56:00+00	f	2026-03-06 22:56:39.106305+00	2026-03-07 03:03:46.608432+00	\N
5c482e07-bf9f-4aaf-8fbb-c802feede07f	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round 1	1	completed	standard	1	131231-03-21 03:13:00+00	t	2026-03-08 05:07:40.877642+00	2026-03-08 05:07:53.677796+00	\N
b0da69f2-572c-42ac-a974-e04242aae9a2	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Quad	1	completed	standard	1	2026-11-11 11:11:00+00	t	2026-03-08 05:41:27.431843+00	2026-03-08 06:54:53.53216+00	\N
5b363c7a-a89b-4040-909f-291db81426b0	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Quad	1	completed	standard	1	66666-11-11 11:11:00+00	t	2026-03-08 05:20:18.87869+00	2026-03-08 06:54:54.836162+00	\N
e03f5958-8566-4ce0-99d1-f6a176c3e19e	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Semi	1	completed	standard	1	2026-11-11 11:11:00+00	t	2026-03-08 06:24:00.227603+00	2026-03-08 06:54:50.600902+00	\N
8982da35-15f4-4db7-8583-99428b755e15	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	4	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:02.139915+00	\N
667f105a-a13f-4fb8-a482-2024949f0968	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	8	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:18.740628+00	\N
61118d73-b931-459a-8d4b-1240dd2c3d53	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	7	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:24.553808+00	\N
75ec8738-f4b0-4888-a82c-0b812453cf82	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	6	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:30.782215+00	\N
514227cb-fbe0-43d4-8e5b-a579e000364b	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	9	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:34.918171+00	\N
a029633d-c548-462b-b994-ff046c092279	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round of 32	10	completed	standard	1	2026-03-06 22:36:00+00	t	2026-03-06 22:36:24.114292+00	2026-03-07 09:39:38.052248+00	\N
4000222b-ea87-463d-b83f-a2e6f17b0667	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Round 1	1	completed	standard	1	2026-03-07 12:30:00+00	f	2026-03-07 02:37:33.700341+00	2026-03-08 07:27:17.265048+00	\N
65066cd1-1dce-4dfc-ad4f-178952722d59	d5e2e87f-b319-4c36-8dbd-0570471ee455	Qualifiers (Time Trial)	1	completed	time_trial	1	2026-03-06 22:41:00+00	t	2026-03-06 22:41:14.28164+00	2026-03-07 09:55:54.407519+00	\N
67180e31-fd9c-424c-b25a-f4cbb9a50d3e	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Round 1	1	completed	standard	1	2026-03-07 15:26:00+00	t	2026-03-07 09:56:41.067959+00	2026-03-07 09:57:06.538697+00	\N
39474f6f-b9e2-432e-b886-4869a45e7925	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Semi	1	completed	standard	1	2026-11-11 11:11:00+00	t	2026-03-08 06:54:02.192127+00	2026-03-08 07:47:05.489661+00	\N
7fd2fbc5-79c1-4919-ae43-b0ea7b3365e7	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Semi	1	completed	standard	1	2026-11-11 11:11:00+00	t	2026-03-08 07:47:01.574143+00	2026-03-08 07:55:19.135773+00	\N
b2a9282f-63de-451b-9f14-7afc38fed60e	d379dcab-b19d-4dc9-9447-eaa173e3c96e	FINALS	1	completed	standard	1	2026-11-11 11:11:00+00	f	2026-03-08 07:57:01.596437+00	2026-03-08 07:57:01.596437+00	\N
\.


--
-- Data for Name: players; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.players (id, team_id, name, phone, year_of_study, in_game_name, created_at, updated_at, user_id, role) FROM stdin;
9e109b91-7fb2-4515-b886-ece15ccc7bdb	6990f292-0ba9-41cc-a20c-07780a8a27b2	Maharshi Prajapati	\N	\N	Maharshi Prajapati	2026-03-06 22:19:15.132844+00	2026-03-06 22:19:15.132844+00	4b40008f-abcc-4793-a280-3b1407cdb044	leader
4a10a48a-7a9f-48f6-a973-3d606ad51c6d	0c588117-c80a-4549-97a9-f1c4d7137107	Rehan	\N	\N	Rehan	2026-03-07 08:00:23.261412+00	2026-03-07 08:00:23.261412+00	e0a021fc-bcdb-4a3f-831f-b755f34937cd	leader
31893aad-e11f-4b5b-8683-c3f856c37e2a	6bb1896c-d706-4a9b-8e01-57d35fe863d0	Manav Pendalwad	\N	\N	Manav Pendalwad	2026-03-06 21:36:18.878013+00	2026-03-06 21:36:18.878013+00	965f3a72-0891-4e78-bea0-43dc9933d2cf	leader
a8cff79c-1eea-40f9-9aad-c75935fe5659	6ed67e6f-2565-4437-b45e-07c61bc0cb42	Arjun Nair	\N	\N	Arjun Nair	2026-03-06 21:36:32.52945+00	2026-03-06 21:36:32.52945+00	85f178e6-d0f6-4322-8968-7b66b9eaa0de	leader
98902efc-271e-43fe-acb7-bd6c443f9990	0b335c14-7114-4e06-84e8-e3f82d217b4c	Atharva Tanpure	\N	\N	Atharva Tanpure	2026-03-06 21:36:46.715341+00	2026-03-06 21:36:46.715341+00	aa8b5ffe-c211-4124-b178-6da96489038e	leader
8540110e-d634-4712-b709-5acd05da6a53	1235a35b-d032-451e-a40c-582ca8eefd70	ARYAN BHAKUNI	\N	\N	ARYAN BHAKUNI	2026-03-06 21:37:00.25356+00	2026-03-06 21:37:00.25356+00	5e431913-6b58-4617-ace5-4427cde50719	leader
6d9f2553-1e1b-4eca-bd34-ab153573c75b	26e5e4ae-51f5-4247-a5bd-6e72a2583020	Nigel Menezes	\N	\N	Nigel Menezes	2026-03-06 21:37:24.846323+00	2026-03-06 21:37:24.846323+00	f2035212-4b88-446a-84cc-c04c3ebb2128	leader
85459bd6-e916-4ff0-b113-2068008be20e	efbe9dde-5da8-4fe3-bdc7-5c3e3eff4171	krishna bhamare	\N	\N	krishna bhamare	2026-03-06 21:37:39.006645+00	2026-03-06 21:37:39.006645+00	96c36e58-36c3-4d1b-92db-59663cfd93ae	leader
c4ee4216-2a2f-491a-9f1e-2f5a331c100c	37e8dc0d-9f70-4d3b-8407-1b79b614288d	Piyush Jadhav	\N	\N	Piyush Jadhav	2026-03-06 21:37:47.085228+00	2026-03-06 21:37:47.085228+00	14dfefb0-f5fc-4dac-96b0-5e7099fbf8a0	leader
d812b9fc-a166-4d8a-86f4-106b14253473	a9e091d5-beca-4ffe-8701-2896a285af34	Aditya Jangid	\N	\N	Aditya Jangid	2026-03-06 21:37:58.896538+00	2026-03-06 21:37:58.896538+00	623986af-52a6-44b5-9ae6-7cd2db37c6cb	leader
910a46ec-3368-4b16-ab3a-9b85e2bc5252	10d5175b-55bc-4463-bdb7-2b51bb04c445	Atharva Chaudhari	\N	\N	Atharva Chaudhari	2026-03-06 21:38:41.693299+00	2026-03-06 21:38:41.693299+00	675cf1ea-9a72-40fb-b683-27f83d4a69cc	leader
17f2c52c-6966-4a90-a65b-686e4177d5a1	c9fb77cc-355d-4066-9be5-f296a08f6eee	Yuvraj	\N	\N	Yuvraj	2026-03-06 21:38:46.639827+00	2026-03-06 21:38:46.639827+00	8d0e8d1c-eb4c-4305-b619-0213ac73f24a	leader
8bd95873-be00-4099-abc5-6fabb3b5fde3	9349ba51-c0f8-46c7-b80b-fabeb2b3f1b3	Malhar Gorde	\N	\N	Malhar Gorde	2026-03-06 21:39:06.514832+00	2026-03-06 21:39:06.514832+00	668bc4b9-d6f4-4bc3-b067-1430a017b18d	leader
fcf0d644-2ba1-4ac5-8207-43a1c24b8dd9	65ee7087-4d43-4a0c-88e7-7b7e3a3b0cc4	Jay Patel	\N	\N	Jay Patel	2026-03-06 21:46:16.961888+00	2026-03-06 21:46:16.961888+00	90c218dc-2f80-47d6-bf34-e81b40887524	leader
e84a513c-6d67-4487-bc1d-c76553f34dd6	41c88bb3-ac01-4976-a34f-14364d5847e2	Shubham Jha	\N	\N	Shubham Jha	2026-03-06 21:46:44.311483+00	2026-03-06 21:46:44.311483+00	d92a0f94-3ff9-41e1-b5d5-72cd2b38b60d	leader
a4d8eab8-7671-4e33-a5eb-7f338f717e41	71678b2e-a79d-4e70-8c3c-23a71d7a432b	Sid	\N	\N	Sid	2026-03-06 21:46:51.562354+00	2026-03-06 21:46:51.562354+00	f619cf40-4412-4eab-bc49-f9f6db280c71	leader
75f5861a-7c65-4a63-b0ac-2945c71e2ef0	bc427e00-9095-4fe5-ab92-1483bd306db9	Harsh Bharuka	\N	\N	Harsh Bharuka	2026-03-06 21:47:12.872425+00	2026-03-06 21:47:12.872425+00	360d6d78-a47e-46e9-958e-b36600fae21e	leader
bf4e597e-c9bd-4f99-a90c-c71f02528294	1b77b920-2df1-492e-ab74-c6f2fb9a3c18	Garvit Nandwana	\N	\N	Garvit Nandwana	2026-03-06 21:47:26.07013+00	2026-03-06 21:47:26.07013+00	e29de3e4-88a0-4b0a-9c8e-abceac26ee29	leader
0a6c585e-76c9-40e9-b159-5caf43674eb7	30c72e95-c8b4-4681-b686-edc1cea3921b	Rujul yerne	\N	\N	Rujul yerne	2026-03-06 21:47:42.512502+00	2026-03-06 21:47:42.512502+00	122773a7-9411-4b8e-b97a-271bcfd78006	leader
d202f5db-8b92-4191-9eab-4dc14aa11e06	4b22a07d-a9bd-4d66-a342-c0a76e3b6011	Krish Prajapati	\N	\N	Krish Prajapati	2026-03-06 21:47:57.006141+00	2026-03-06 21:47:57.006141+00	ec970805-c740-4f1b-ab8e-580f0468b272	leader
57c5c255-b7e9-457d-87d3-46f37df79196	2ab64636-26cc-4aa8-a283-a58bd11c87b5	Deepankar Paul	\N	\N	Deepankar Paul	2026-03-06 22:03:27.308852+00	2026-03-06 22:03:27.308852+00	f2d47eb0-2761-4cc8-93bc-591950f813f8	leader
96a7240c-90d5-4998-bb4e-d107dcf1c38e	733a172f-b6a7-454a-9752-4ea13cc2c1ed	Shauryadeep Singh	\N	\N	Shauryadeep Singh	2026-03-06 22:03:40.375931+00	2026-03-06 22:03:40.375931+00	2e035d82-8836-476c-a816-7ba275701202	leader
3278546f-c761-4857-a97a-32089e61915a	bd380d9b-fc7f-4f19-9775-d1ec4be7c549	Nilansh Singhal	\N	\N	Nilansh Singhal	2026-03-06 22:03:51.879088+00	2026-03-06 22:03:51.879088+00	29bfc8df-fe4a-4592-b6c6-d72a8c06a884	leader
f66b6b86-edf8-4caa-859a-e53f0df6c277	de739ccb-f695-454d-8ffc-ce8fa7fb74c2	Nigel Menezes	\N	\N	Nigel Menezes	2026-03-06 22:04:06.725011+00	2026-03-06 22:04:06.725011+00	f2035212-4b88-446a-84cc-c04c3ebb2128	leader
669546d7-799e-452d-a337-38273347fa9e	a98be024-98de-47d8-b4ee-81ac979e68cc	Jay Patil	\N	\N	Jay Patil	2026-03-06 22:04:24.840637+00	2026-03-06 22:04:24.840637+00	f70a35b1-48e9-4bf0-88db-8a0fc5076e14	leader
22e180d8-244a-4345-a0a6-e03c8af24fbd	3094153b-b3c5-402f-9995-0bc0b503b95b	Rudrapratap Singh	\N	\N	Rudrapratap Singh	2026-03-06 22:04:46.329922+00	2026-03-06 22:04:46.329922+00	5d6a6675-b191-4444-811a-45efe9ad9268	leader
505a1e70-3dbc-4d26-8759-fb56cd2b8d11	85bba676-5457-473c-bc04-57ec51c50d83	Jayesh Mandloi	\N	\N	Jayesh Mandloi	2026-03-06 22:05:02.937553+00	2026-03-06 22:05:02.937553+00	96b3586c-1a86-4f2e-b65c-110e1d9f839c	leader
e783f92f-c4d4-4016-9892-7d2768ef7dca	19d61ac8-c437-46ab-95f2-a383e4e5569f	Rishabh Mehta	\N	\N	Rishabh Mehta	2026-03-06 22:05:18.060866+00	2026-03-06 22:05:18.060866+00	620c954f-f59d-48f9-b3e7-3be9b77b8ac9	leader
96547c8e-cbe8-42fb-a008-b29fee8d11bb	1c74fd33-ccfd-48a2-a16b-86c376af8ab6	Rakshit Pandey	\N	\N	Rakshit Pandey	2026-03-06 22:05:30.850131+00	2026-03-06 22:05:30.850131+00	e0c06eff-fd91-4ad3-a340-55f293872df1	leader
541da8f9-843b-4f70-a274-a4cc572ad8f2	e0ee6fe8-e915-4158-9568-fbd5ba69974f	Yash Patil	\N	\N	Yash Patil	2026-03-06 22:05:42.470837+00	2026-03-06 22:05:42.470837+00	e1c94e11-5396-4130-9ffa-1c76b6d7969c	leader
46edbd38-ab6d-4fc8-9ac5-8804eb08778f	39317674-6115-4075-aad8-5224044539d0	Nikhil Raulo	\N	\N	Nikhil Raulo	2026-03-06 22:05:55.215188+00	2026-03-06 22:05:55.215188+00	2a9de694-2dbc-4d17-b109-5a2e7e13f656	leader
4250fc01-98e1-4ea5-a9e6-4e8760d5406f	337648e5-2b97-4dfb-81b0-d113b94c3745	Shlok Katwate	\N	\N	Shlok Katwate	2026-03-06 22:06:08.093484+00	2026-03-06 22:06:08.093484+00	3356d2b0-32fc-486b-af7b-afcbf26ac7b3	leader
30c19d47-f390-4cab-91ca-31b75af2c076	978428dc-539b-413a-a9c7-a08b1f4fbc33	Nikunj Goyal	\N	\N	Nikunj Goyal	2026-03-06 22:06:19.720292+00	2026-03-06 22:06:19.720292+00	16c20803-c5a3-4b46-b263-0a9243e528cd	leader
b18094cd-5cf1-40d5-b4be-a1903f31a1cc	b642afd0-88a7-4eec-809b-61b1b75c6e7e	Jason Philip	\N	\N	Jason Philip	2026-03-06 22:06:29.967369+00	2026-03-06 22:06:29.967369+00	7e76c858-e523-4bc0-af1c-99db247c840a	leader
b7f0fb4a-65a5-4312-b1cd-2dda32e01b6a	aa4ab848-fda4-44b1-9875-690c46ac0d79	Arnab Chowdhury	\N	\N	Arnab Chowdhury	2026-03-06 22:06:42.590442+00	2026-03-06 22:06:42.590442+00	6a70988d-9044-47b9-bac7-cc839cf58556	leader
8dbc602d-4a0b-454e-8ec6-6b7cdaad5480	496413d3-13f1-483f-9ff3-73616550d122	Rohan Painter	\N	\N	Rohan Painter	2026-03-06 22:07:07.307445+00	2026-03-06 22:07:07.307445+00	d6786693-2e23-4fa8-902f-3287585eb336	leader
20b05619-8754-4c03-b250-e77643464fad	a1e42367-c38e-40d1-88cb-8ea7916ac3d4	Krish Prajapati	\N	\N	Krish Prajapati	2026-03-06 22:07:22.69611+00	2026-03-06 22:07:22.69611+00	ec970805-c740-4f1b-ab8e-580f0468b272	leader
180c0e6e-4b56-47a1-abb0-9481bde51a13	235cbc38-03e2-4845-a55c-1a8419cfc850	Hemant	\N	\N	Hemant	2026-03-06 22:08:25.312653+00	2026-03-06 22:08:25.312653+00	c89a4286-c785-477d-8f2f-694a92bda4e5	leader
d7243ac1-43b7-4077-93b0-58913eb91c36	4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	Jashraj	\N	\N	Jashraj	2026-03-06 22:08:58.85177+00	2026-03-06 22:08:58.85177+00	78894d49-24f3-43da-b4d6-3fd1b58101eb	leader
9814a5e8-75fe-4504-9fa0-eecdf0853193	6d8ce91a-6b8b-49a4-826d-1da46b46b2b8	Aryan	\N	\N	Aryan	2026-03-06 22:09:14.480445+00	2026-03-06 22:09:14.480445+00	b0507a12-afa1-4c01-9cdd-2d5fea199ca1	leader
69e52728-a4f9-445e-abd3-b1719a7f915d	84e94daf-e5be-49cd-b1ad-ec9f04e9326a	Shreyas Nair	\N	\N	Shreyas Nair	2026-03-06 22:18:22.668849+00	2026-03-06 22:18:22.668849+00	06a47237-f90a-40f3-9a5d-316701113d55	leader
e75888c9-03bc-426f-90b8-97d99cd6d72a	1df3fc25-a63d-4d49-9f8f-efd77bc12d58	Jay Patil	\N	\N	Jay Patil	2026-03-06 22:18:36.141824+00	2026-03-06 22:18:36.141824+00	f70a35b1-48e9-4bf0-88db-8a0fc5076e14	leader
060fa51e-40a1-4ad9-9949-8df25fad3e05	25f57276-dbf8-4e46-b083-cd5f89fde86d	Nigel Menezes	\N	\N	Nigel Menezes	2026-03-06 22:18:47.22328+00	2026-03-06 22:18:47.22328+00	f2035212-4b88-446a-84cc-c04c3ebb2128	leader
52f9f362-679e-4b8c-813f-5322fd33a0e9	7dba394c-40e0-4912-99ae-f402afce9647	Ankit Jangid	\N	\N	Ankit Jangid	2026-03-06 22:19:03.3721+00	2026-03-06 22:19:03.3721+00	90f5afde-deb1-4a0c-b330-9a485d39a305	leader
8aea6bf6-ef67-4977-99cc-087d36b2235e	27841588-dece-4e64-b6d5-ff47fe980c78	Arav	\N	\N	Arav	2026-03-07 08:00:34.421299+00	2026-03-07 08:00:34.421299+00	7f77c219-1b2e-4eec-ba2e-0051b3ecee13	leader
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.profiles (id, email, display_name, role, assigned_game_id, created_at, updated_at) FROM stdin;
94a14681-63d4-4771-b283-f2d65a2717d5	wwhheeeellss2006@gmail.com		admin	\N	2026-02-21 11:50:17.476082+00	2026-02-21 11:50:56.275148+00
9e5339c5-a706-4ae3-aaa7-beda00fc88ea	laveshpatil103@gmail.com	Lavesh	admin	\N	2026-03-04 04:54:10.43259+00	2026-03-04 04:54:10.43259+00
bfc601de-144e-4470-bc49-abba27e1654e	anantjha884@gmail.com	Anant	admin	\N	2026-03-04 04:54:53.964956+00	2026-03-04 04:54:53.964956+00
80e32448-e07e-4d7b-a543-7fb9b527413d	sharvinneve67@gmail.com	Sharvin	admin	\N	2026-03-05 18:22:14.986419+00	2026-03-05 18:22:14.986419+00
90c218dc-2f80-47d6-bf34-e81b40887524	jaypatelhd2005@gmail.com	Jay Patel	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:42:59.653495+00	2026-03-06 21:46:16.827444+00
d92a0f94-3ff9-41e1-b5d5-72cd2b38b60d	shubhanyways07@gmail.com	Shubham Jha	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:43:17.427036+00	2026-03-06 21:46:44.194454+00
f619cf40-4412-4eab-bc49-f9f6db280c71	bhatsiddhant1@gmail.com	Sid	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:43:50.041853+00	2026-03-06 21:46:51.431563+00
360d6d78-a47e-46e9-958e-b36600fae21e	bharukaharsh@gmail.com	Harsh Bharuka	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:44:13.334338+00	2026-03-06 21:47:12.74018+00
e29de3e4-88a0-4b0a-9c8e-abceac26ee29	garvitnandwana22@gmail.com	Garvit Nandwana	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:44:38.987071+00	2026-03-06 21:47:25.926789+00
122773a7-9411-4b8e-b97a-271bcfd78006	rujul.yerne276@nmims.in	Rujul yerne	game_leader	d5e2e87f-b319-4c36-8dbd-0570471ee455	2026-03-06 21:45:20.7162+00	2026-03-06 21:47:42.397858+00
bf18986c-e856-48aa-a3c8-565387234507	kavyansh@gmail.com	Kavyansh	admin	\N	2026-03-07 04:06:20.71642+00	2026-03-07 04:06:20.71642+00
7e76c858-e523-4bc0-af1c-99db247c840a	jason15th2007@gmail.com	Jason Philip	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:59:58.285822+00	2026-03-06 22:06:29.841443+00
965f3a72-0891-4e78-bea0-43dc9933d2cf	manavpendalwad456@gmail.com	Manav Pendalwad	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:28:13.780219+00	2026-03-06 21:36:18.698878+00
85f178e6-d0f6-4322-8968-7b66b9eaa0de	nairarjun915@gmail.com	Arjun Nair	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:29:00.975607+00	2026-03-06 21:36:32.397873+00
aa8b5ffe-c211-4124-b178-6da96489038e	atharvatanpure01@gmail.com	Atharva Tanpure	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:29:38.028607+00	2026-03-06 21:36:46.588676+00
5e431913-6b58-4617-ace5-4427cde50719	aryanbhakuni2006@gmail.com	ARYAN BHAKUNI	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:30:06.062241+00	2026-03-06 21:37:00.128017+00
6a70988d-9044-47b9-bac7-cc839cf58556	arnabchowdhury979@gmail.com	Arnab Chowdhury	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 22:00:41.56048+00	2026-03-06 22:06:42.470038+00
d6786693-2e23-4fa8-902f-3287585eb336	painterrohan@gmail.com	Rohan Painter	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 22:01:02.488304+00	2026-03-06 22:07:07.179685+00
96c36e58-36c3-4d1b-92db-59663cfd93ae	krishnabhamare60@gmail.com	krishna bhamare	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:30:54.640604+00	2026-03-06 21:37:38.883337+00
14dfefb0-f5fc-4dac-96b0-5e7099fbf8a0	jadhavpiyush868@gmail.com	Piyush Jadhav	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:31:21.008528+00	2026-03-06 21:37:46.95844+00
623986af-52a6-44b5-9ae6-7cd2db37c6cb	jangidaditya2304@gmail.com	Aditya Jangid	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:31:52.520883+00	2026-03-06 21:37:58.771591+00
675cf1ea-9a72-40fb-b683-27f83d4a69cc	atharva.charu.16@gmail.com	Atharva Chaudhari	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:32:18.172057+00	2026-03-06 21:38:41.565686+00
8d0e8d1c-eb4c-4305-b619-0213ac73f24a	yuvrajkale95@gmail.com	Yuvraj	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:32:50.921084+00	2026-03-06 21:38:46.5238+00
668bc4b9-d6f4-4bc3-b067-1430a017b18d	malhar@gmail.com	Malhar Gorde	game_leader	8b790a72-0135-48d2-8d4c-308ebf20d5d7	2026-03-06 21:33:14.351433+00	2026-03-06 21:39:06.389685+00
ec970805-c740-4f1b-ab8e-580f0468b272	krish1346p@gmail.com	Krish Prajapati	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:45:47.434809+00	2026-03-06 22:07:22.570711+00
c89a4286-c785-477d-8f2f-694a92bda4e5	hemant@gmail.com	Hemant	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 22:01:52.597436+00	2026-03-06 22:08:25.191117+00
78894d49-24f3-43da-b4d6-3fd1b58101eb	jashraj@gmail.com	Jashraj	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 22:02:12.986702+00	2026-03-06 22:08:58.720064+00
b0507a12-afa1-4c01-9cdd-2d5fea199ca1	aryan@gmail.com	Aryan	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 22:02:31.167785+00	2026-03-06 22:09:14.360804+00
e0a021fc-bcdb-4a3f-831f-b755f34937cd	rehan@gmail.com	Rehan	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-07 07:58:53.152672+00	2026-03-07 08:00:23.077205+00
7f77c219-1b2e-4eec-ba2e-0051b3ecee13	arav@gmail.com	Arav	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-07 07:59:14.119949+00	2026-03-07 08:00:34.292922+00
f2d47eb0-2761-4cc8-93bc-591950f813f8	dispanker2018@gmail.com	Deepankar Paul	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:54:05.868538+00	2026-03-06 22:03:27.016387+00
2e035d82-8836-476c-a816-7ba275701202	godspeeed@duck.com	Shauryadeep Singh	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:54:24.900232+00	2026-03-06 22:03:40.258374+00
29bfc8df-fe4a-4592-b6c6-d72a8c06a884	nilanshsinghal10@gmail.com	Nilansh Singhal	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:54:52.009426+00	2026-03-06 22:03:51.750531+00
5d6a6675-b191-4444-811a-45efe9ad9268	rps.rudu@gmail.com	Rudrapratap Singh	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:56:49.499326+00	2026-03-06 22:04:46.192941+00
96b3586c-1a86-4f2e-b65c-110e1d9f839c	jmandloi6638@gmail.com	Jayesh Mandloi	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:57:09.19902+00	2026-03-06 22:05:02.802316+00
620c954f-f59d-48f9-b3e7-3be9b77b8ac9	kunjdesai28@gmail.com	Rishabh Mehta	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:57:34.23117+00	2026-03-06 22:05:17.923043+00
e0c06eff-fd91-4ad3-a340-55f293872df1	rakshitpandey680@gmail.com	Rakshit Pandey	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:57:55.368055+00	2026-03-06 22:05:30.727249+00
e1c94e11-5396-4130-9ffa-1c76b6d7969c	yashnitinsingpatil.8@gmail.com	Yash Patil	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:58:45.063208+00	2026-03-06 22:05:42.34177+00
2a9de694-2dbc-4d17-b109-5a2e7e13f656	nikhilraulo70@gmail.com	Nikhil Raulo	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:59:00.808286+00	2026-03-06 22:05:55.088437+00
3356d2b0-32fc-486b-af7b-afcbf26ac7b3	shlokkatwate2705@gmail.com	Shlok Katwate	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:59:15.516023+00	2026-03-06 22:06:07.965092+00
16c20803-c5a3-4b46-b263-0a9243e528cd	nikunjgoyal681@gmail.com	Nikunj Goyal	game_leader	d379dcab-b19d-4dc9-9447-eaa173e3c96e	2026-03-06 21:59:34.070307+00	2026-03-06 22:06:19.599316+00
06a47237-f90a-40f3-9a5d-316701113d55	shreyasnair002@gmail.com	Shreyas Nair	game_leader	62bb5f98-4326-4364-b02e-8f58f85aa1b4	2026-03-06 22:13:49.393476+00	2026-03-06 22:18:22.54614+00
f70a35b1-48e9-4bf0-88db-8a0fc5076e14	jaypatilll20@gmail.com	Jay Patil	game_leader	62bb5f98-4326-4364-b02e-8f58f85aa1b4	2026-03-06 21:56:18.789843+00	2026-03-06 22:18:36.016814+00
f2035212-4b88-446a-84cc-c04c3ebb2128	nigelm524@gmail.com	Nigel Menezes	game_leader	62bb5f98-4326-4364-b02e-8f58f85aa1b4	2026-03-06 21:30:28.642022+00	2026-03-06 22:18:47.1065+00
90f5afde-deb1-4a0c-b330-9a485d39a305	ankitj2811@gmail.com	Ankit Jangid	game_leader	62bb5f98-4326-4364-b02e-8f58f85aa1b4	2026-03-06 22:15:23.876311+00	2026-03-06 22:19:03.253013+00
4b40008f-abcc-4793-a280-3b1407cdb044	m10prjpt@gmail.com	Maharshi Prajapati	game_leader	62bb5f98-4326-4364-b02e-8f58f85aa1b4	2026-03-06 22:16:01.315371+00	2026-03-06 22:19:15.009279+00
\.


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.teams (id, game_id, team_name, logo_url, created_by, created_at, updated_at, status) FROM stdin;
59f5eeef-aac5-407a-9caa-32293aef2624	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Sharvin Neve	\N	80e32448-e07e-4d7b-a543-7fb9b527413d	2026-03-06 22:18:03.887074+00	2026-03-06 22:18:03.887074+00	qualified
84e94daf-e5be-49cd-b1ad-ec9f04e9326a	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Shreyas Nair	\N	06a47237-f90a-40f3-9a5d-316701113d55	2026-03-06 22:18:22.295307+00	2026-03-06 22:18:22.295307+00	qualified
1df3fc25-a63d-4d49-9f8f-efd77bc12d58	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Jay Patil	\N	f70a35b1-48e9-4bf0-88db-8a0fc5076e14	2026-03-06 22:18:35.782433+00	2026-03-06 22:18:35.782433+00	qualified
25f57276-dbf8-4e46-b083-cd5f89fde86d	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Nigel Menezes	\N	f2035212-4b88-446a-84cc-c04c3ebb2128	2026-03-06 22:18:46.867994+00	2026-03-06 22:18:46.867994+00	qualified
7dba394c-40e0-4912-99ae-f402afce9647	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Ankit Jangid	\N	90f5afde-deb1-4a0c-b330-9a485d39a305	2026-03-06 22:19:03.020713+00	2026-03-06 22:19:03.020713+00	qualified
6990f292-0ba9-41cc-a20c-07780a8a27b2	62bb5f98-4326-4364-b02e-8f58f85aa1b4	Maharshi Prajapati	\N	4b40008f-abcc-4793-a280-3b1407cdb044	2026-03-06 22:19:14.769217+00	2026-03-06 22:19:14.769217+00	qualified
2ab64636-26cc-4aa8-a283-a58bd11c87b5	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Deepankar Paul	\N	f2d47eb0-2761-4cc8-93bc-591950f813f8	2026-03-06 22:03:26.7087+00	2026-03-07 10:15:05.942689+00	disqualified
6ed67e6f-2565-4437-b45e-07c61bc0cb42	8b790a72-0135-48d2-8d4c-308ebf20d5d7	4 Angry Men	\N	85f178e6-d0f6-4322-8968-7b66b9eaa0de	2026-03-06 21:36:32.150112+00	2026-03-06 21:36:32.150112+00	qualified
0b335c14-7114-4e06-84e8-e3f82d217b4c	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Apex Predators	\N	aa8b5ffe-c211-4124-b178-6da96489038e	2026-03-06 21:36:46.322511+00	2026-03-06 21:36:46.322511+00	qualified
1235a35b-d032-451e-a40c-582ca8eefd70	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Zero mercy	\N	5e431913-6b58-4617-ace5-4427cde50719	2026-03-06 21:36:59.880502+00	2026-03-06 21:36:59.880502+00	qualified
26e5e4ae-51f5-4247-a5bd-6e72a2583020	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Team Insanity	\N	f2035212-4b88-446a-84cc-c04c3ebb2128	2026-03-06 21:37:24.45344+00	2026-03-06 21:37:24.45344+00	qualified
37e8dc0d-9f70-4d3b-8407-1b79b614288d	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Team Maka Ladlleeeee	\N	14dfefb0-f5fc-4dac-96b0-5e7099fbf8a0	2026-03-06 21:37:46.705465+00	2026-03-06 21:37:46.705465+00	qualified
a9e091d5-beca-4ffe-8701-2896a285af34	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Team Santra	\N	623986af-52a6-44b5-9ae6-7cd2db37c6cb	2026-03-06 21:37:58.498462+00	2026-03-06 21:37:58.498462+00	qualified
10d5175b-55bc-4463-bdb7-2b51bb04c445	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Team.VNAND	\N	675cf1ea-9a72-40fb-b683-27f83d4a69cc	2026-03-06 21:38:36.405291+00	2026-03-06 21:38:36.405291+00	qualified
c9fb77cc-355d-4066-9be5-f296a08f6eee	8b790a72-0135-48d2-8d4c-308ebf20d5d7	fnatic	\N	8d0e8d1c-eb4c-4305-b619-0213ac73f24a	2026-03-06 21:38:46.26583+00	2026-03-06 21:38:46.26583+00	qualified
9349ba51-c0f8-46c7-b80b-fabeb2b3f1b3	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Malhar	\N	668bc4b9-d6f4-4bc3-b067-1430a017b18d	2026-03-06 21:39:06.105415+00	2026-03-06 21:39:06.105415+00	qualified
65ee7087-4d43-4a0c-88e7-7b7e3a3b0cc4	d5e2e87f-b319-4c36-8dbd-0570471ee455	Jay Patel	\N	90c218dc-2f80-47d6-bf34-e81b40887524	2026-03-06 21:46:16.555539+00	2026-03-06 21:46:16.555539+00	qualified
41c88bb3-ac01-4976-a34f-14364d5847e2	d5e2e87f-b319-4c36-8dbd-0570471ee455	Shubham Jha	\N	d92a0f94-3ff9-41e1-b5d5-72cd2b38b60d	2026-03-06 21:46:39.066202+00	2026-03-06 21:46:39.066202+00	qualified
71678b2e-a79d-4e70-8c3c-23a71d7a432b	d5e2e87f-b319-4c36-8dbd-0570471ee455	Sid	\N	f619cf40-4412-4eab-bc49-f9f6db280c71	2026-03-06 21:46:51.174459+00	2026-03-06 21:46:51.174459+00	qualified
bc427e00-9095-4fe5-ab92-1483bd306db9	d5e2e87f-b319-4c36-8dbd-0570471ee455	Harsh Bharuka	\N	360d6d78-a47e-46e9-958e-b36600fae21e	2026-03-06 21:47:12.494936+00	2026-03-06 21:47:12.494936+00	qualified
1b77b920-2df1-492e-ab74-c6f2fb9a3c18	d5e2e87f-b319-4c36-8dbd-0570471ee455	Garvit Nandwana	\N	e29de3e4-88a0-4b0a-9c8e-abceac26ee29	2026-03-06 21:47:25.674692+00	2026-03-06 21:47:25.674692+00	qualified
4b22a07d-a9bd-4d66-a342-c0a76e3b6011	d5e2e87f-b319-4c36-8dbd-0570471ee455	Krish Prajapati	\N	ec970805-c740-4f1b-ab8e-580f0468b272	2026-03-06 21:47:56.628728+00	2026-03-06 21:47:56.628728+00	qualified
aa4ab848-fda4-44b1-9875-690c46ac0d79	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Arnab Chowdhury	\N	6a70988d-9044-47b9-bac7-cc839cf58556	2026-03-06 22:06:42.210137+00	2026-03-06 22:06:42.210137+00	qualified
6d8ce91a-6b8b-49a4-826d-1da46b46b2b8	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Aryan	\N	b0507a12-afa1-4c01-9cdd-2d5fea199ca1	2026-03-06 22:09:14.113734+00	2026-03-07 10:37:01.197014+00	disqualified
337648e5-2b97-4dfb-81b0-d113b94c3745	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Shlok Katwate	\N	3356d2b0-32fc-486b-af7b-afcbf26ac7b3	2026-03-06 22:06:07.723346+00	2026-03-07 10:38:44.24826+00	disqualified
bd380d9b-fc7f-4f19-9775-d1ec4be7c549	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Nilansh Singhal	\N	29bfc8df-fe4a-4592-b6c6-d72a8c06a884	2026-03-06 22:03:51.479458+00	2026-03-08 05:08:14.096307+00	disqualified
978428dc-539b-413a-a9c7-a08b1f4fbc33	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Nikunj Goyal	\N	16c20803-c5a3-4b46-b263-0a9243e528cd	2026-03-06 22:06:19.247994+00	2026-03-08 05:28:04.606119+00	disqualified
235cbc38-03e2-4845-a55c-1a8419cfc850	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Hemant	\N	c89a4286-c785-477d-8f2f-694a92bda4e5	2026-03-06 22:08:24.943788+00	2026-03-08 06:20:39.431047+00	disqualified
85bba676-5457-473c-bc04-57ec51c50d83	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Jayesh Mandloi	\N	96b3586c-1a86-4f2e-b65c-110e1d9f839c	2026-03-06 22:05:02.537847+00	2026-03-08 06:20:44.830724+00	disqualified
733a172f-b6a7-454a-9752-4ea13cc2c1ed	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Shauryadeep Singh	\N	2e035d82-8836-476c-a816-7ba275701202	2026-03-06 22:03:40.005985+00	2026-03-08 06:21:03.856294+00	disqualified
6bb1896c-d706-4a9b-8e01-57d35fe863d0	8b790a72-0135-48d2-8d4c-308ebf20d5d7	Team OG	\N	965f3a72-0891-4e78-bea0-43dc9933d2cf	2026-03-06 21:36:18.415683+00	2026-03-06 23:12:21.689394+00	qualified
efbe9dde-5da8-4fe3-bdc7-5c3e3eff4171	8b790a72-0135-48d2-8d4c-308ebf20d5d7	9/11 PILOTS	\N	96c36e58-36c3-4d1b-92db-59663cfd93ae	2026-03-06 21:37:33.699489+00	2026-03-07 02:48:20.383719+00	qualified
30c72e95-c8b4-4681-b686-edc1cea3921b	d5e2e87f-b319-4c36-8dbd-0570471ee455	Rujul yerne	\N	122773a7-9411-4b8e-b97a-271bcfd78006	2026-03-06 21:47:42.126592+00	2026-03-07 05:59:11.516975+00	disqualified
0c588117-c80a-4549-97a9-f1c4d7137107	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Rehan	\N	e0a021fc-bcdb-4a3f-831f-b755f34937cd	2026-03-07 08:00:22.732973+00	2026-03-07 08:00:22.732973+00	qualified
a1e42367-c38e-40d1-88cb-8ea7916ac3d4	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Krish Prajapati	\N	ec970805-c740-4f1b-ab8e-580f0468b272	2026-03-06 22:07:22.303826+00	2026-03-07 08:26:51.127008+00	disqualified
a98be024-98de-47d8-b4ee-81ac979e68cc	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Jay Patil	\N	f70a35b1-48e9-4bf0-88db-8a0fc5076e14	2026-03-06 22:04:24.467009+00	2026-03-07 08:27:01.104126+00	disqualified
3094153b-b3c5-402f-9995-0bc0b503b95b	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Rudrapratap Singh	\N	5d6a6675-b191-4444-811a-45efe9ad9268	2026-03-06 22:04:45.410376+00	2026-03-07 08:27:11.31594+00	disqualified
39317674-6115-4075-aad8-5224044539d0	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Nikhil Raulo	\N	2a9de694-2dbc-4d17-b109-5a2e7e13f656	2026-03-06 22:05:54.829553+00	2026-03-07 08:28:11.536916+00	disqualified
1c74fd33-ccfd-48a2-a16b-86c376af8ab6	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Rakshit Pandey	\N	e0c06eff-fd91-4ad3-a340-55f293872df1	2026-03-06 22:05:30.45853+00	2026-03-07 08:28:20.004811+00	disqualified
19d61ac8-c437-46ab-95f2-a383e4e5569f	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Rishabh Mehta	\N	620c954f-f59d-48f9-b3e7-3be9b77b8ac9	2026-03-06 22:05:17.669561+00	2026-03-07 08:28:30.573436+00	disqualified
27841588-dece-4e64-b6d5-ff47fe980c78	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Arav	\N	7f77c219-1b2e-4eec-ba2e-0051b3ecee13	2026-03-07 08:00:34.004763+00	2026-03-07 10:04:55.830475+00	disqualified
b642afd0-88a7-4eec-809b-61b1b75c6e7e	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Jason Philip	\N	7e76c858-e523-4bc0-af1c-99db247c840a	2026-03-06 22:06:29.598362+00	2026-03-07 10:06:38.715339+00	disqualified
4fcf6b93-4e1b-4eb1-8d4f-7eba9947efaa	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Jashraj	\N	78894d49-24f3-43da-b4d6-3fd1b58101eb	2026-03-06 22:08:58.480598+00	2026-03-08 06:54:29.345376+00	disqualified
e0ee6fe8-e915-4158-9568-fbd5ba69974f	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Yash Patil	\N	e1c94e11-5396-4130-9ffa-1c76b6d7969c	2026-03-06 22:05:42.097353+00	2026-03-08 06:54:32.967173+00	disqualified
496413d3-13f1-483f-9ff3-73616550d122	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Rohan Painter	\N	d6786693-2e23-4fa8-902f-3287585eb336	2026-03-06 22:07:06.938249+00	2026-03-08 07:30:12.438896+00	disqualified
de739ccb-f695-454d-8ffc-ce8fa7fb74c2	d379dcab-b19d-4dc9-9447-eaa173e3c96e	Nigel Menezes	\N	f2035212-4b88-446a-84cc-c04c3ebb2128	2026-03-06 22:04:06.358782+00	2026-03-08 09:34:52.908691+00	qualified
\.


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: games games_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_name_key UNIQUE (name);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: games games_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_slug_key UNIQUE (slug);


--
-- Name: leaderboards leaderboards_game_id_team_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_game_id_team_id_key UNIQUE (game_id, team_id);


--
-- Name: leaderboards leaderboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_pkey PRIMARY KEY (id);


--
-- Name: match_results match_results_match_id_team_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_results
    ADD CONSTRAINT match_results_match_id_team_id_key UNIQUE (match_id, team_id);


--
-- Name: match_results match_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_results
    ADD CONSTRAINT match_results_pkey PRIMARY KEY (id);


--
-- Name: match_teams match_teams_match_id_team_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_teams
    ADD CONSTRAINT match_teams_match_id_team_id_key UNIQUE (match_id, team_id);


--
-- Name: match_teams match_teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_teams
    ADD CONSTRAINT match_teams_pkey PRIMARY KEY (id);


--
-- Name: matches matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_pkey PRIMARY KEY (id);


--
-- Name: players players_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: teams teams_game_id_team_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_game_id_team_name_key UNIQUE (game_id, team_name);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: players trg_check_player_limit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_player_limit BEFORE INSERT OR UPDATE ON public.players FOR EACH ROW EXECUTE FUNCTION public.check_one_team_per_game();


--
-- Name: teams trg_check_team_limit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_team_limit BEFORE INSERT OR UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.check_one_team_per_game();


--
-- Name: match_results update_match_results_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_match_results_updated_at BEFORE UPDATE ON public.match_results FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: matches update_matches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_matches_updated_at BEFORE UPDATE ON public.matches FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: players update_players_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_players_updated_at BEFORE UPDATE ON public.players FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: profiles update_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: teams update_teams_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: leaderboards leaderboards_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE;


--
-- Name: leaderboards leaderboards_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaderboards
    ADD CONSTRAINT leaderboards_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: match_results match_results_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_results
    ADD CONSTRAINT match_results_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.matches(id) ON DELETE CASCADE;


--
-- Name: match_results match_results_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_results
    ADD CONSTRAINT match_results_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: match_teams match_teams_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_teams
    ADD CONSTRAINT match_teams_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.matches(id) ON DELETE CASCADE;


--
-- Name: match_teams match_teams_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.match_teams
    ADD CONSTRAINT match_teams_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: matches matches_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.matches
    ADD CONSTRAINT matches_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE;


--
-- Name: players players_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: players players_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.players
    ADD CONSTRAINT players_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_assigned_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_assigned_game_id_fkey FOREIGN KEY (assigned_game_id) REFERENCES public.games(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: teams teams_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: teams teams_game_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id) ON DELETE CASCADE;


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_logs_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_admin_read ON public.audit_logs FOR SELECT USING ((public.get_user_role() = 'admin'::text));


--
-- Name: audit_logs audit_logs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_logs_insert ON public.audit_logs FOR INSERT WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: games; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;

--
-- Name: games games_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY games_admin_all ON public.games USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: games games_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY games_read_all ON public.games FOR SELECT USING (true);


--
-- Name: leaderboards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leaderboards ENABLE ROW LEVEL SECURITY;

--
-- Name: leaderboards leaderboards_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leaderboards_admin_all ON public.leaderboards USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: leaderboards leaderboards_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leaderboards_read_all ON public.leaderboards FOR SELECT USING (true);


--
-- Name: match_results; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.match_results ENABLE ROW LEVEL SECURITY;

--
-- Name: match_results match_results_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY match_results_admin_all ON public.match_results USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: match_results match_results_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY match_results_read_all ON public.match_results FOR SELECT USING (true);


--
-- Name: match_teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.match_teams ENABLE ROW LEVEL SECURITY;

--
-- Name: match_teams match_teams_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY match_teams_admin_all ON public.match_teams USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: match_teams match_teams_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY match_teams_read_all ON public.match_teams FOR SELECT USING (true);


--
-- Name: matches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

--
-- Name: matches matches_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY matches_admin_all ON public.matches USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: matches matches_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY matches_read_all ON public.matches FOR SELECT USING (true);


--
-- Name: players; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

--
-- Name: players players_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY players_admin_all ON public.players USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: players players_leader_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY players_leader_delete ON public.players FOR DELETE USING (((public.get_user_role() = 'game_leader'::text) AND (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.game_id = public.get_user_game_id())))) AND ((EXISTS ( SELECT 1
   FROM public.players p2
  WHERE ((p2.team_id = players.team_id) AND (p2.user_id = auth.uid()) AND (p2.role = 'leader'::text)))) OR (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.created_by = auth.uid())))))));


--
-- Name: players players_leader_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY players_leader_insert ON public.players FOR INSERT WITH CHECK (((public.get_user_role() = 'game_leader'::text) AND (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.game_id = public.get_user_game_id())))) AND ((EXISTS ( SELECT 1
   FROM public.players p2
  WHERE ((p2.team_id = players.team_id) AND (p2.user_id = auth.uid()) AND (p2.role = 'leader'::text)))) OR (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.created_by = auth.uid())))))));


--
-- Name: players players_leader_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY players_leader_update ON public.players FOR UPDATE USING (((public.get_user_role() = 'game_leader'::text) AND (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.game_id = public.get_user_game_id())))) AND ((EXISTS ( SELECT 1
   FROM public.players p2
  WHERE ((p2.team_id = players.team_id) AND (p2.user_id = auth.uid()) AND (p2.role = 'leader'::text)))) OR (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.created_by = auth.uid()))))))) WITH CHECK (((public.get_user_role() = 'game_leader'::text) AND (EXISTS ( SELECT 1
   FROM public.teams
  WHERE ((teams.id = players.team_id) AND (teams.game_id = public.get_user_game_id()))))));


--
-- Name: players players_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY players_read_all ON public.players FOR SELECT USING (true);


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_admin_all ON public.profiles USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: profiles profiles_self_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_self_read ON public.profiles FOR SELECT USING ((id = auth.uid()));


--
-- Name: teams; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

--
-- Name: teams teams_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_admin_all ON public.teams USING ((public.get_user_role() = 'admin'::text)) WITH CHECK ((public.get_user_role() = 'admin'::text));


--
-- Name: teams teams_leader_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_leader_delete ON public.teams FOR DELETE USING (((public.get_user_role() = 'game_leader'::text) AND (game_id = public.get_user_game_id()) AND (EXISTS ( SELECT 1
   FROM public.players
  WHERE ((players.team_id = players.id) AND (players.user_id = auth.uid()) AND (players.role = 'leader'::text))))));


--
-- Name: teams teams_leader_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_leader_insert ON public.teams FOR INSERT WITH CHECK (((public.get_user_role() = 'game_leader'::text) AND (game_id = public.get_user_game_id())));


--
-- Name: teams teams_leader_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_leader_update ON public.teams FOR UPDATE USING (((public.get_user_role() = 'game_leader'::text) AND (game_id = public.get_user_game_id()) AND (EXISTS ( SELECT 1
   FROM public.players
  WHERE ((players.team_id = players.id) AND (players.user_id = auth.uid()) AND (players.role = 'leader'::text)))))) WITH CHECK (((public.get_user_role() = 'game_leader'::text) AND (game_id = public.get_user_game_id())));


--
-- Name: teams teams_player_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_player_delete ON public.teams FOR DELETE USING (((public.get_user_role() = ANY (ARRAY['game_leader'::text, 'player'::text, 'viewer'::text])) AND (EXISTS ( SELECT 1
   FROM public.players
  WHERE ((players.team_id = players.id) AND (players.user_id = auth.uid()) AND (players.role = 'leader'::text))))));


--
-- Name: teams teams_player_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_player_insert ON public.teams FOR INSERT WITH CHECK (((public.get_user_role() = ANY (ARRAY['game_leader'::text, 'player'::text])) AND (created_by = auth.uid())));


--
-- Name: teams teams_player_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_player_update ON public.teams FOR UPDATE USING (((public.get_user_role() = ANY (ARRAY['game_leader'::text, 'player'::text, 'viewer'::text])) AND (EXISTS ( SELECT 1
   FROM public.players
  WHERE ((players.team_id = players.id) AND (players.user_id = auth.uid()) AND (players.role = 'leader'::text)))))) WITH CHECK ((public.get_user_role() = ANY (ARRAY['game_leader'::text, 'player'::text, 'viewer'::text])));


--
-- Name: teams teams_read_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY teams_read_all ON public.teams FOR SELECT USING (true);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION calculate_bgmi_leaderboard(p_game_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_bgmi_leaderboard(p_game_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_bgmi_leaderboard(p_game_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_bgmi_leaderboard(p_game_id uuid) TO service_role;


--
-- Name: FUNCTION calculate_f1_rankings(p_game_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_f1_rankings(p_game_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_f1_rankings(p_game_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_f1_rankings(p_game_id uuid) TO service_role;


--
-- Name: FUNCTION calculate_fifa25_bracket(p_game_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_fifa25_bracket(p_game_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_fifa25_bracket(p_game_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_fifa25_bracket(p_game_id uuid) TO service_role;


--
-- Name: FUNCTION calculate_valorant_standings(p_game_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.calculate_valorant_standings(p_game_id uuid) TO anon;
GRANT ALL ON FUNCTION public.calculate_valorant_standings(p_game_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_valorant_standings(p_game_id uuid) TO service_role;


--
-- Name: FUNCTION check_one_team_per_game(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.check_one_team_per_game() TO anon;
GRANT ALL ON FUNCTION public.check_one_team_per_game() TO authenticated;
GRANT ALL ON FUNCTION public.check_one_team_per_game() TO service_role;


--
-- Name: FUNCTION create_fixtures_batch(p_game_id uuid, p_round_name text, p_scheduled_at timestamp with time zone, p_matchups jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.create_fixtures_batch(p_game_id uuid, p_round_name text, p_scheduled_at timestamp with time zone, p_matchups jsonb) TO anon;
GRANT ALL ON FUNCTION public.create_fixtures_batch(p_game_id uuid, p_round_name text, p_scheduled_at timestamp with time zone, p_matchups jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.create_fixtures_batch(p_game_id uuid, p_round_name text, p_scheduled_at timestamp with time zone, p_matchups jsonb) TO service_role;


--
-- Name: FUNCTION get_user_game_id(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_user_game_id() TO anon;
GRANT ALL ON FUNCTION public.get_user_game_id() TO authenticated;
GRANT ALL ON FUNCTION public.get_user_game_id() TO service_role;


--
-- Name: FUNCTION get_user_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.get_user_role() TO anon;
GRANT ALL ON FUNCTION public.get_user_role() TO authenticated;
GRANT ALL ON FUNCTION public.get_user_role() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION log_audit(p_user_id uuid, p_action text, p_details jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.log_audit(p_user_id uuid, p_action text, p_details jsonb) TO anon;
GRANT ALL ON FUNCTION public.log_audit(p_user_id uuid, p_action text, p_details jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.log_audit(p_user_id uuid, p_action text, p_details jsonb) TO service_role;


--
-- Name: FUNCTION update_updated_at(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.update_updated_at() TO anon;
GRANT ALL ON FUNCTION public.update_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_at() TO service_role;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_logs TO anon;
GRANT ALL ON TABLE public.audit_logs TO authenticated;
GRANT ALL ON TABLE public.audit_logs TO service_role;


--
-- Name: TABLE games; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.games TO anon;
GRANT ALL ON TABLE public.games TO authenticated;
GRANT ALL ON TABLE public.games TO service_role;


--
-- Name: TABLE leaderboards; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.leaderboards TO anon;
GRANT ALL ON TABLE public.leaderboards TO authenticated;
GRANT ALL ON TABLE public.leaderboards TO service_role;


--
-- Name: TABLE match_results; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.match_results TO anon;
GRANT ALL ON TABLE public.match_results TO authenticated;
GRANT ALL ON TABLE public.match_results TO service_role;


--
-- Name: TABLE match_teams; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.match_teams TO anon;
GRANT ALL ON TABLE public.match_teams TO authenticated;
GRANT ALL ON TABLE public.match_teams TO service_role;


--
-- Name: TABLE matches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.matches TO anon;
GRANT ALL ON TABLE public.matches TO authenticated;
GRANT ALL ON TABLE public.matches TO service_role;


--
-- Name: TABLE players; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.players TO anon;
GRANT ALL ON TABLE public.players TO authenticated;
GRANT ALL ON TABLE public.players TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE teams; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.teams TO anon;
GRANT ALL ON TABLE public.teams TO authenticated;
GRANT ALL ON TABLE public.teams TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict CVBAsG2vhQ3rgmogTfOekEf89OD1DH9QRSJY8ewjLfatUfbOtSWMIW42YhdjVCh

