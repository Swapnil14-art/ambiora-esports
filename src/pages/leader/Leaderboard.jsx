import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { Trophy, Clock } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

function formatTime(ms) {
    if (!ms) return '—';
    const m = Math.floor(ms / 60000);
    const s = Math.floor((ms % 60000) / 1000);
    const mil = ms % 1000;
    return `${m}:${String(s).padStart(2, '0')}.${String(mil).padStart(3, '0')}`;
}

export default function LeaderLeaderboard() {
    const { profile } = useAuth();
    const gameId = profile?.assigned_game_id;
    const [leaderboard, setLeaderboard] = useState([]);
    const [game, setGame] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (gameId) fetchData();
    }, [gameId]);

    useEffect(() => {
        if (!gameId) return;
        const channel = supabase
            .channel('leader-leaderboard')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'leaderboards' }, () => fetchData())
            .subscribe();
        return () => supabase.removeChannel(channel);
    }, [gameId]);

    const fetchData = async () => {
        const [gameRes, lbRes] = await Promise.all([
            supabase.from('games').select('*').eq('id', gameId).single(),
            supabase.from('leaderboards').select('*, teams(team_name)').eq('game_id', gameId).order('rank'),
        ]);
        setGame(gameRes.data);
        setLeaderboard(lbRes.data || []);
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="table" count={5} /></div>;

    const isF1 = game?.slug === 'f1';

    return (
        <div>
            <div className="page-header"><h1>Leaderboard</h1></div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {leaderboard.length === 0 ? (
                    <div className="empty-state"><Trophy size={32} /><p>Leaderboard not yet calculated</p></div>
                ) : (
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th style={{ width: 60 }}>Rank</th>
                                <th>Team</th>
                                {isF1 ? <th>Best Lap</th> : <><th>Points</th><th>Wins</th></>}
                                <th>Played</th>
                            </tr>
                        </thead>
                        <tbody>
                            {leaderboard.map((e, i) => (
                                <tr key={e.id}>
                                    <td>
                                        <span style={{
                                            fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '1rem',
                                            color: i === 0 ? 'var(--neon-yellow)' : i === 1 ? '#c0c0c0' : i === 2 ? 'var(--neon-orange)' : 'var(--text-primary)',
                                        }}>#{e.rank || i + 1}</span>
                                    </td>
                                    <td style={{ fontWeight: 600 }}>{e.teams?.team_name}</td>
                                    {isF1 ? (
                                        <td style={{ fontFamily: 'var(--font-display)', color: 'var(--neon-cyan)' }}>
                                            <Clock size={12} style={{ display: 'inline', marginRight: 4 }} />
                                            {formatTime(e.extra_data?.best_time_ms)}
                                        </td>
                                    ) : (
                                        <>
                                            <td style={{ fontFamily: 'var(--font-display)', fontWeight: 700, color: 'var(--neon-purple)' }}>{e.total_points}</td>
                                            <td>{e.wins || 0}</td>
                                        </>
                                    )}
                                    <td style={{ color: 'var(--text-muted)' }}>{e.matches_played}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>
        </div>
    );
}
