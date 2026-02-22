-- =================================================================================
-- ATOMIC FIXTURE GENERATION
-- Safely inserts an array of matches and their associated teams in a single transaction.
-- If any part fails, the entire batch rolls back, preventing orphaned or partial brackets.
-- =================================================================================

-- Type to describe the incoming JSON payload for matchups
-- { match_type: "standard", best_of: 1, team_ids: ["uuid1", "uuid2"] }

CREATE OR REPLACE FUNCTION public.create_fixtures_batch(
    p_game_id UUID,
    p_round_name TEXT,
    p_scheduled_at TIMESTAMPTZ,
    p_matchups JSONB -- Array of matchup objects
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Runs as elevated privileges, rely on RLS/caller checks
SET search_path = public
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
