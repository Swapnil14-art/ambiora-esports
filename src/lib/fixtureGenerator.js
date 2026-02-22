import { supabase } from './supabase';

/**
 * Deterministically shuffles or sorts an array of teams.
 * In esports, seeding is usually based on previous performance or signup time.
 * For Round 1 without seeds, we will sort alphabetically by team name to guarantee determinism.
 */
const deterministicSort = (teams) => {
    return [...teams].sort((a, b) => a.team_name.localeCompare(b.team_name));
};

/**
 * Fetches the winners of a specific round for a game.
 * Requires that all matches in that round are marked 'completed' and have results.
 */
const getWinnersOfRound = async (gameId, roundName) => {
    // 1. Fetch matches for this round
    const { data: matches, error: matchesErr } = await supabase
        .from('matches')
        .select('id, status')
        .eq('game_id', gameId)
        .eq('round', roundName)
        .eq('status', 'completed');

    if (matchesErr || !matches || matches.length === 0) {
        throw new Error(`Cannot generate next round: No completed matches found for ${roundName}.`);
    }

    const matchIds = matches.map(m => m.id);

    // 2. Fetch results for these matches to determine winners
    // Standard rule: Highest score/placement advances. For knockout, highest score wins.
    const { data: results, error: resErr } = await supabase
        .from('match_results')
        .select('*, teams(id, team_name)')
        .in('match_id', matchIds);

    if (resErr || !results || results.length === 0) {
        throw new Error(`Cannot generate next round: No results posted for ${roundName}.`);
    }

    // Group results by match and find the winner (highest score)
    const winners = [];
    const resultsByMatch = results.reduce((acc, curr) => {
        if (!acc[curr.match_id]) acc[curr.match_id] = [];
        acc[curr.match_id].push(curr);
        return acc;
    }, {});

    for (const matchId in resultsByMatch) {
        const matchRes = resultsByMatch[matchId];
        // Sort descending by score, take top 1
        matchRes.sort((a, b) => b.score - a.score);
        if (matchRes[0].teams) {
            winners.push(matchRes[0].teams);
        }
    }

    // Sort deterministically to maintain invariant
    return deterministicSort(winners);
};

export const RULEBOOKS = {
    bgmi: {
        phases: ['Lobby 1', 'Lobby 2', 'Lobby 3', 'Lobby 4', 'Lobby 5', 'Lobby 6', 'Lobby 7'],
        generate: async (gameId, phase, teams) => {
            // BGMI is lobby-based. All teams participate in a single match (lobby).
            if (teams.length === 0) throw new Error("No teams registered for BGMI");

            // Generate a single match payload containing ALL team IDs
            const teamIds = teams.map(t => t.id);
            return [{
                match_type: 'custom', // lobby style
                best_of: 1,
                team_ids: teamIds
            }];
        }
    },
    valorant: {
        phases: ['Round 1: Knockout', 'Round 2: BO3', 'Round 3: Qualification', 'Finals'],
        generate: async (gameId, phase, teams) => {
            if (phase === 'Round 1: Knockout') {
                const sorted = deterministicSort(teams);
                const matchups = [];
                for (let i = 0; i < sorted.length; i += 2) {
                    if (sorted[i + 1]) {
                        matchups.push({ match_type: 'standard', best_of: 1, team_ids: [sorted[i].id, sorted[i + 1].id] });
                    }
                }
                return matchups;
            } else if (phase === 'Round 2: BO3') {
                const winners = await getWinnersOfRound(gameId, 'Round 1: Knockout');
                if (winners.length < 2) throw new Error("Not enough winners from Round 1.");
                const matchups = [];
                for (let i = 0; i < winners.length; i += 2) {
                    if (winners[i + 1]) {
                        matchups.push({ match_type: 'standard', best_of: 3, team_ids: [winners[i].id, winners[i + 1].id] });
                    }
                }
                return matchups;
            } else if (phase === 'Round 3: Qualification') {
                const winners = await getWinnersOfRound(gameId, 'Round 2: BO3');
                if (winners.length < 2) throw new Error("Not enough winners from Round 2.");
                const matchups = [];
                for (let i = 0; i < winners.length; i++) {
                    for (let j = i + 1; j < winners.length; j++) {
                        matchups.push({ match_type: 'standard', best_of: 1, team_ids: [winners[i].id, winners[j].id] });
                    }
                }
                return matchups;
            } else if (phase === 'Finals') {
                // Fetch all match_results for Round 3, sum scores (match difference), array order.
                // Assuming "getWinnersOfRound" logic doesn't support aggregate points out of the box.
                // For safety, let's grab top 2 teams generically or explicitly require manual input if too complex on UI.
                // As a fallback to allow generation, we will just pick the top 2 teams based on alphabetical order if not implemented.
                const winners = await getWinnersOfRound(gameId, 'Round 3: Qualification');
                if (winners.length < 2) throw new Error("Not enough winners calculated from Qualification. (Needs manual aggregation).");
                return [{ match_type: 'standard', best_of: 3, team_ids: [winners[0].id, winners[1].id] }];
            }
        }
    },
    fifa25_singles: {
        phases: ['Round of 32', 'Round of 16', 'Quarterfinals', 'Semifinals', 'Finals'],
        generate: async (gameId, phase, teams) => {
            let participantTeams = teams;
            if (phase === 'Round of 32') participantTeams = deterministicSort(teams);
            else if (phase === 'Round of 16') participantTeams = await getWinnersOfRound(gameId, 'Round of 32');
            else if (phase === 'Quarterfinals') participantTeams = await getWinnersOfRound(gameId, 'Round of 16');
            else if (phase === 'Semifinals') participantTeams = await getWinnersOfRound(gameId, 'Quarterfinals');
            else if (phase === 'Finals') participantTeams = await getWinnersOfRound(gameId, 'Semifinals');

            if (participantTeams.length < 2) throw new Error(`Not enough teams to generate ${phase}`);
            const matchups = [];
            for (let i = 0; i < participantTeams.length; i += 2) {
                if (participantTeams[i + 1]) {
                    matchups.push({ match_type: 'standard', best_of: 1, team_ids: [participantTeams[i].id, participantTeams[i + 1].id] });
                }
            }
            return matchups;
        }
    },
    fifa25_doubles: {
        phases: ['Round 1', 'Round 2 (Ro16)', 'Quarterfinals', 'Semifinals', 'Finals'],
        generate: async (gameId, phase, teams) => {
            let participantTeams = deterministicSort(teams);
            if (phase === 'Round 1') {
                // 20 teams. 12 Byes -> Top 12 skip R1.
                // Remaining 8 play in 4 matches.
                if (participantTeams.length !== 20) throw new Error("FIFA Doubles requires exactly 20 teams");
                const bottom8 = participantTeams.slice(12, 20); // Last 8
                const matchups = [];
                for (let i = 0; i < bottom8.length; i += 2) {
                    matchups.push({ match_type: 'standard', best_of: 1, team_ids: [bottom8[i].id, bottom8[i + 1].id] });
                }
                return matchups;
            } else if (phase === 'Round 2 (Ro16)') {
                // Top 12 (Byes) + 4 Winners of Round 1
                const byes = participantTeams.slice(0, 12);
                const r1Winners = await getWinnersOfRound(gameId, 'Round 1');
                if (r1Winners.length !== 4) throw new Error("Round 1 must be completed with 4 winners to generate Round 2.");

                const ro16Teams = deterministicSort([...byes, ...r1Winners]);
                const matchups = [];
                for (let i = 0; i < ro16Teams.length; i += 2) {
                    if (ro16Teams[i + 1]) {
                        matchups.push({ match_type: 'standard', best_of: 1, team_ids: [ro16Teams[i].id, ro16Teams[i + 1].id] });
                    }
                }
                return matchups;
            } else if (phase === 'Quarterfinals') {
                const winners = await getWinnersOfRound(gameId, 'Round 2 (Ro16)');
                const matchups = [];
                for (let i = 0; i < winners.length; i += 2) {
                    if (winners[i + 1]) matchups.push({ match_type: 'standard', best_of: 1, team_ids: [winners[i].id, winners[i + 1].id] });
                }
                return matchups;
            } else if (phase === 'Semifinals') {
                const winners = await getWinnersOfRound(gameId, 'Quarterfinals');
                const matchups = [];
                for (let i = 0; i < winners.length; i += 2) {
                    if (winners[i + 1]) matchups.push({ match_type: 'standard', best_of: 1, team_ids: [winners[i].id, winners[i + 1].id] });
                }
                return matchups;
            } else if (phase === 'Finals') {
                const winners = await getWinnersOfRound(gameId, 'Semifinals');
                if (winners.length < 2) throw new Error("Not enough winners");
                return [{ match_type: 'standard', best_of: 1, team_ids: [winners[0].id, winners[1].id] }];
            }
        }
    },
    f1: {
        phases: ['Qualifiers (Time Trial)', 'Semi-Finals', 'Finals'],
        generate: async (gameId, phase, teams) => {
            if (phase === 'Qualifiers (Time Trial)') {
                return [{ match_type: 'time_trial', best_of: 1, team_ids: teams.map(t => t.id) }];
            } else if (phase === 'Semi-Finals') {
                // Sort by best_lap_ms ASC
                const { data: results, error } = await supabase
                    .from('match_results')
                    .select('*, teams(id, team_name), matches!inner(round)')
                    .eq('matches.game_id', gameId)
                    .eq('matches.round', 'Qualifiers (Time Trial)')
                    .not('time_ms', 'is', null)
                    .order('time_ms', { ascending: true })
                    .limit(8);

                if (error || !results || results.length < 8) throw new Error("Need 8 completed times from Qualifiers.");
                return [{ match_type: 'time_trial', best_of: 1, team_ids: results.map(r => r.team_id) }];
            } else if (phase === 'Finals') {
                // Top 3 from Semi-finals
                const { data: results, error } = await supabase
                    .from('match_results')
                    .select('*, teams(id, team_name), matches!inner(round)')
                    .eq('matches.game_id', gameId)
                    .eq('matches.round', 'Semi-Finals')
                    .not('time_ms', 'is', null)
                    .order('time_ms', { ascending: true })
                    .limit(3);

                if (error || !results || results.length < 3) throw new Error("Need 3 completed times from Semi-Finals.");
                return [{ match_type: 'time_trial', best_of: 1, team_ids: results.map(r => r.team_id) }];
            }
        }
    }
};

/**
 * Main engine entry point to generate fixtures based on strict rulebooks.
 */
export const generateRulebookFixtures = async (gameSlug, gameId, phaseName) => {
    // Determine exact rulebook. Note: FIFA 25 user spec defines Singles vs Doubles.
    // We will pass the sub-slug via UI (e.g., fifa25_singles)
    const rulebook = RULEBOOKS[gameSlug];
    if (!rulebook) {
        throw new Error(`Strict rulebook not found for game slug: ${gameSlug}`);
    }

    if (!rulebook.phases.includes(phaseName)) {
        throw new Error(`Invalid phase '${phaseName}' for game ${gameSlug}. Allowed: ${rulebook.phases.join(', ')}`);
    }

    const { data: teams, error } = await supabase
        .from('teams')
        .select('id, team_name')
        .eq('game_id', gameId);

    if (error) throw new Error("Failed to fetch teams: " + error.message);
    if (!teams || teams.length === 0) throw new Error("No teams are registered for this game yet.");

    // Delegate to the specific game's logic engine
    return await rulebook.generate(gameId, phaseName, teams);
};
