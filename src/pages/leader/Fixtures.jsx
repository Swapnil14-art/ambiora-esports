import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { Calendar, Clock, Gamepad2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderFixtures() {
    const { profile } = useAuth();
    const [gameFixtures, setGameFixtures] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (profile?.id) fetchAllFixtures();
    }, [profile]);

    // Realtime subscription for matches (refreshes all)
    useEffect(() => {
        if (!profile?.id) return;
        const channel = supabase
            .channel('leader-matches')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, () => fetchAllFixtures())
            .subscribe();
        return () => supabase.removeChannel(channel);
    }, [profile]);

    const fetchAllFixtures = async () => {
        try {
            // Find all games where this user is a leader
            const { data: leaderRows, error: leaderErr } = await supabase
                .from('players')
                .select('team_id, teams!inner(game_id)')
                .eq('user_id', profile.id)
                .eq('role', 'leader');

            if (leaderErr) throw leaderErr;

            const gameIdSet = new Set();
            (leaderRows || []).forEach(r => {
                if (r.teams?.game_id) gameIdSet.add(r.teams.game_id);
            });
            const gameIds = Array.from(gameIdSet);

            // Fallback to assigned_game_id
            if (gameIds.length === 0 && profile.assigned_game_id) {
                gameIds.push(profile.assigned_game_id);
            }

            if (gameIds.length === 0) {
                setGameFixtures([]);
                setLoading(false);
                return;
            }

            // Fetch fixtures for each game in parallel
            const fixturesPromises = gameIds.map(async (gameId) => {
                const [gameRes, matchesRes] = await Promise.all([
                    supabase.from('games').select('name').eq('id', gameId).single(),
                    supabase
                        .from('matches')
                        .select('*, match_teams(team_id, teams(team_name))')
                        .eq('game_id', gameId)
                        .order('scheduled_at', { ascending: true, nullsFirst: false }),
                ]);

                return {
                    gameId,
                    gameName: gameRes.data?.name || 'Unknown',
                    matches: matchesRes.data || [],
                };
            });

            const allFixtures = await Promise.all(fixturesPromises);
            allFixtures.sort((a, b) => a.gameName.localeCompare(b.gameName));
            setGameFixtures(allFixtures);
        } catch (error) {
            console.error('Error fetching fixtures:', error);
        }
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="table" count={5} /></div>;

    return (
        <div>
            <div className="page-header">
                <h1>Fixtures</h1>
            </div>

            {gameFixtures.length === 0 ? (
                <div className="empty-state"><Calendar size={32} /><p>No fixtures yet</p></div>
            ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-xl)' }}>
                    {gameFixtures.map(({ gameId, gameName, matches }) => (
                        <div key={gameId}>
                            {gameFixtures.length > 1 && (
                                <div style={{
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '8px',
                                    marginBottom: 'var(--space-md)',
                                    paddingBottom: 'var(--space-sm)',
                                    borderBottom: '1px solid var(--border-secondary)',
                                }}>
                                    <Gamepad2 size={18} style={{ color: 'var(--neon-purple)' }} />
                                    <h2 style={{
                                        fontSize: '1rem',
                                        fontFamily: 'var(--font-display)',
                                        fontWeight: 700,
                                        textTransform: 'uppercase',
                                        letterSpacing: '1px',
                                        margin: 0,
                                    }}>{gameName}</h2>
                                </div>
                            )}

                            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                                {matches.length === 0 ? (
                                    <div className="empty-state" style={{ padding: 'var(--space-lg)' }}>
                                        <p style={{ margin: 0 }}>No fixtures for this game</p>
                                    </div>
                                ) : (
                                    <div className="table-responsive">
                                        <table className="data-table">
                                            <thead>
                                                <tr>
                                                    <th>Round</th>
                                                    <th>#</th>
                                                    <th>Teams</th>
                                                    <th>Status</th>
                                                    <th>Scheduled</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                {matches.map(m => (
                                                    <tr key={m.id}>
                                                        <td style={{ fontWeight: 600 }}>{m.round}</td>
                                                        <td>{m.match_number}</td>
                                                        <td style={{ fontSize: '0.85rem' }}>
                                                            {m.match_teams?.map(mt => mt.teams?.team_name).join(' vs ') || '—'}
                                                        </td>
                                                        <td><span className={`badge badge-${m.status}`}>{m.status}</span></td>
                                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>
                                                            {m.scheduled_at ? new Date(m.scheduled_at).toLocaleString() : '—'}
                                                        </td>
                                                    </tr>
                                                ))}
                                            </tbody>
                                        </table>
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
