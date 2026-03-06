import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { Users, UserPlus, Calendar, Trophy, Gamepad2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderDashboard() {
    const { profile } = useAuth();
    const [gameStats, setGameStats] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (profile?.id) fetchAllGameStats();
    }, [profile]);

    const fetchAllGameStats = async () => {
        try {
            // 1. Find all games where this user is a leader (via players table)
            const { data: leaderRows, error: leaderErr } = await supabase
                .from('players')
                .select('team_id, teams!inner(game_id)')
                .eq('user_id', profile.id)
                .eq('role', 'leader');

            if (leaderErr) throw leaderErr;

            // Get distinct game IDs
            const gameIdSet = new Set();
            (leaderRows || []).forEach(r => {
                if (r.teams?.game_id) gameIdSet.add(r.teams.game_id);
            });
            const gameIds = Array.from(gameIdSet);

            if (gameIds.length === 0) {
                // Fallback: try the assigned_game_id from profile
                if (profile.assigned_game_id) {
                    gameIds.push(profile.assigned_game_id);
                } else {
                    setGameStats([]);
                    setLoading(false);
                    return;
                }
            }

            // 2. Fetch stats for each game in parallel
            const statsPromises = gameIds.map(async (gameId) => {
                const [gameRes, teamsRes, matchesRes, liveRes] = await Promise.all([
                    supabase.from('games').select('name').eq('id', gameId).single(),
                    supabase.from('teams').select('id, players(id)').eq('game_id', gameId),
                    supabase.from('matches').select('id', { count: 'exact', head: true }).eq('game_id', gameId),
                    supabase.from('matches').select('id', { count: 'exact', head: true }).eq('game_id', gameId).eq('status', 'live'),
                ]);

                const teamData = teamsRes.data || [];
                const playerCount = teamData.reduce((acc, t) => acc + (t.players?.length || 0), 0);

                return {
                    gameId,
                    gameName: gameRes.data?.name || 'Unknown',
                    stats: {
                        teams: teamData.length,
                        players: playerCount,
                        matches: matchesRes.count || 0,
                        live: liveRes.count || 0,
                    }
                };
            });

            const allStats = await Promise.all(statsPromises);
            // Sort alphabetically by game name
            allStats.sort((a, b) => a.gameName.localeCompare(b.gameName));
            setGameStats(allStats);
        } catch (error) {
            console.error('Error fetching dashboard stats:', error);
        }
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="dashboard-stats" count={4} /></div>;

    if (gameStats.length === 0) {
        return (
            <div>
                <div className="page-header">
                    <h1 className="text-gradient">Leader Dashboard</h1>
                </div>
                <div className="empty-state"><p>No games assigned yet.</p></div>
            </div>
        );
    }

    return (
        <div>
            <div className="page-header">
                <h1 className="text-gradient">
                    {gameStats.length === 1 ? `${gameStats[0].gameName} — Dashboard` : 'Leader Dashboard'}
                </h1>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-xl)' }}>
                {gameStats.map(({ gameId, gameName, stats }) => (
                    <div key={gameId}>
                        {gameStats.length > 1 && (
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
                        <div className="stats-grid">
                            <div className="card stat-card">
                                <div className="stat-label">Teams</div>
                                <div className="stat-value" style={{ color: 'var(--neon-cyan)' }}>{stats.teams}</div>
                                <Users size={16} style={{ color: 'var(--text-muted)' }} />
                            </div>
                            <div className="card stat-card">
                                <div className="stat-label">Players</div>
                                <div className="stat-value" style={{ color: 'var(--neon-purple)' }}>{stats.players}</div>
                                <UserPlus size={16} style={{ color: 'var(--text-muted)' }} />
                            </div>
                            <div className="card stat-card">
                                <div className="stat-label">Total Matches</div>
                                <div className="stat-value" style={{ color: 'var(--neon-green)' }}>{stats.matches}</div>
                                <Calendar size={16} style={{ color: 'var(--text-muted)' }} />
                            </div>
                            <div className="card stat-card">
                                <div className="stat-label">Live Now</div>
                                <div className="stat-value" style={{ color: 'var(--neon-red)' }}>{stats.live}</div>
                                <Trophy size={16} style={{ color: 'var(--text-muted)' }} />
                            </div>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
}
