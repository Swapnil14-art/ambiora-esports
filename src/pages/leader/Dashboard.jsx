import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { Link } from 'react-router-dom';
import { Users, UserPlus, Calendar, Trophy, Gamepad2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderDashboard() {
    const { profile, fetchProfile, setProfile } = useAuth(); // Added setProfile if it exists, otherwise we'll just refetch 
    // Wait, useAuth doesn't expose setProfile directly, but we can just use `window.location.href = '/leader'` or something. 
    // Actually, forcing a reload after a timeout is still failing because the session JWT claims are stale.
    // Let's check `AuthContext.jsx` to see if we can expose a `refreshSession` method.
    const [stats, setStats] = useState({ teams: 0, players: 0, matches: 0, live: 0 });
    const [gameName, setGameName] = useState('');
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!profile?.assigned_game_id) return;
        fetchStats();
    }, [profile]);

    const fetchStats = async () => {
        const gameId = profile.assigned_game_id;

        const [gameRes, teamsRes, matchesRes, liveRes] = await Promise.all([
            supabase.from('games').select('name').eq('id', gameId).single(),
            supabase.from('teams').select('id, players(id)').eq('game_id', gameId),
            supabase.from('matches').select('id', { count: 'exact', head: true }).eq('game_id', gameId),
            supabase.from('matches').select('id', { count: 'exact', head: true }).eq('game_id', gameId).eq('status', 'live'),
        ]);

        setGameName(gameRes.data?.name || 'Unknown');
        const teamData = teamsRes.data || [];
        const playerCount = teamData.reduce((acc, t) => acc + (t.players?.length || 0), 0);

        setStats({
            teams: teamData.length,
            players: playerCount,
            matches: matchesRes.count || 0,
            live: liveRes.count || 0,
        });
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="dashboard-stats" count={4} /></div>;

    return (
        <div>
            <div className="page-header">
                <h1 className="text-gradient">{gameName} — Dashboard</h1>
            </div>

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
    );
}
