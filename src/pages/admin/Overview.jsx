import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { fetchWithCache, hasValidCache, invalidateCache } from '../../lib/cache';
import { useAuth } from '../../contexts/AuthContext';
import {
    Users, UserPlus, Calendar, Trophy, Activity, AlertCircle,
} from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function AdminOverview() {
    const navigate = useNavigate();
    const { profile } = useAuth();
    const [stats, setStats] = useState({
        totalTeams: 0,
        totalPlayers: 0,
        totalMatches: 0,
        liveMatches: 0,
        gameStats: [],
    });
    const [recentLogs, setRecentLogs] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        fetchStats();
    }, []);

    const fetchStats = async () => {
        if (!hasValidCache('admin_teams_count')) {
            setLoading(true);
        }

        try {
            const [teamsRes, playersRes, matchesRes, liveRes, gamesRes, logsRes] = await Promise.all([
                fetchWithCache('admin_teams_count', async () => await supabase.from('teams').select('id', { count: 'exact', head: true })),
                fetchWithCache('admin_players_count', async () => await supabase.from('players').select('id', { count: 'exact', head: true })),
                fetchWithCache('admin_matches_count', async () => await supabase.from('matches').select('id', { count: 'exact', head: true })),
                fetchWithCache('admin_live_matches_count', async () => await supabase.from('matches').select('id', { count: 'exact', head: true }).eq('status', 'live')),
                fetchWithCache('admin_games_stats', async () => await supabase.from('games').select('id, name, slug, teams(id), matches(id)')),
                fetchWithCache('admin_recent_logs', async () => await supabase.from('audit_logs').select('*, profiles(display_name, email)').order('created_at', { ascending: false }).limit(10), 60000), // Cache logs for 1 min max
            ]);

            const gameStats = (gamesRes.data || []).map(g => ({
                id: g.id,
                name: g.name,
                slug: g.slug,
                teams: g.teams?.length || 0,
                matches: g.matches?.length || 0,
            }));

            setStats({
                totalTeams: teamsRes.count || 0,
                totalPlayers: playersRes.count || 0,
                totalMatches: matchesRes.count || 0,
                liveMatches: liveRes.count || 0,
                gameStats,
            });

            setRecentLogs(logsRes.data || []);
        } catch (err) {
            console.error('Error fetching stats:', err);
        }
        setLoading(false);
    };

    if (loading) {
        return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="dashboard-stats" count={4} /></div>;
    }

    return (
        <div>
            <div className="page-header">
                <h1 className="text-gradient">Command Center</h1>
            </div>

            <div className="stats-grid">
                <div className="card hud-card stat-card" style={{ cursor: 'pointer' }} onClick={() => navigate('/admin/teams')}>
                    <div className="stat-label">Total Teams</div>
                    <div className="stat-value" style={{ color: 'var(--neon-cyan)' }}>{stats.totalTeams}</div>
                    <Users size={16} style={{ color: 'var(--text-muted)' }} />
                </div>
                <div className="card hud-card stat-card" style={{ cursor: 'pointer' }} onClick={() => navigate('/admin/users')}>
                    <div className="stat-label">Total Players</div>
                    <div className="stat-value" style={{ color: 'var(--neon-purple)' }}>{stats.totalPlayers}</div>
                    <UserPlus size={16} style={{ color: 'var(--text-muted)' }} />
                </div>
                <div className="card hud-card stat-card" style={{ cursor: 'pointer' }} onClick={() => navigate('/admin/matches')}>
                    <div className="stat-label">Total Matches</div>
                    <div className="stat-value" style={{ color: 'var(--neon-green)' }}>{stats.totalMatches}</div>
                    <Calendar size={16} style={{ color: 'var(--text-muted)' }} />
                </div>
                <div className="card hud-card stat-card" style={{ cursor: 'pointer' }} onClick={() => navigate('/admin/matches', { state: { defaultStatus: 'live' } })}>
                    <div className="stat-label">Live Now</div>
                    <div className="stat-value" style={{ color: 'var(--neon-red)' }}>
                        {stats.liveMatches}
                        {stats.liveMatches > 0 && <span style={{ display: 'inline-block', width: 8, height: 8, background: 'var(--neon-red)', borderRadius: '50%', marginLeft: 8, animation: 'pulse-live 2s infinite' }}></span>}
                    </div>
                    <Activity size={16} style={{ color: 'var(--text-muted)' }} />
                </div>
            </div>

            {/* Per-Game Breakdown */}
            <h2 style={{ marginBottom: 'var(--space-md)', fontSize: '0.9rem' }}>Game Breakdown</h2>
            <div className="stats-grid" style={{ marginBottom: 'var(--space-xl)' }}>
                {stats.gameStats.map((g, index) => (
                    <div key={g.slug} className={`card hud-card hover-parallax stagger-${Math.min(index + 1, 5)}`} style={{ padding: 'var(--space-md)', cursor: 'pointer' }}
                        onClick={() => navigate('/admin/teams', { state: { defaultGameId: g.id } })}
                    >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                            <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px' }}>{g.name}</span>
                            <Trophy size={14} style={{ color: 'var(--neon-orange)' }} />
                        </div>
                        <div style={{ display: 'flex', gap: 'var(--space-lg)' }}>
                            <div
                                className="hover-text-cyan"
                                onClick={(e) => { e.stopPropagation(); navigate('/admin/teams', { state: { defaultGameId: g.id } }); }}
                            >
                                <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '1px' }}>Teams</div>
                                <div style={{ fontFamily: 'var(--font-display)', fontSize: '1.1rem', fontWeight: 700 }}>{g.teams}</div>
                            </div>
                            <div
                                className="hover-text-cyan"
                                onClick={(e) => { e.stopPropagation(); navigate('/admin/matches', { state: { defaultGameId: g.id } }); }}
                            >
                                <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '1px' }}>Matches</div>
                                <div style={{ fontFamily: 'var(--font-display)', fontSize: '1.1rem', fontWeight: 700 }}>{g.matches}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Recent Audit Logs */}
            <h2 style={{ marginBottom: 'var(--space-md)', fontSize: '0.9rem' }}>Recent Activity</h2>
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {recentLogs.length === 0 ? (
                    <div className="empty-state">
                        <AlertCircle size={24} />
                        <p>No recent activity</p>
                    </div>
                ) : (
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>Action</th>
                                <th>User</th>
                                <th>Time</th>
                            </tr>
                        </thead>
                        <tbody>
                            {recentLogs.map(log => (
                                <tr key={log.id}>
                                    <td style={{ fontSize: '0.8rem' }}>{log.action}</td>
                                    <td style={{ color: 'var(--text-secondary)', fontSize: '0.8rem' }}>
                                        {log.profiles?.display_name || log.profiles?.email || '—'}
                                    </td>
                                    <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>
                                        {new Date(log.created_at).toLocaleString()}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>
        </div>
    );
}
