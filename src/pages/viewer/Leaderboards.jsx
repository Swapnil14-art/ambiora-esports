import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { Trophy, Clock } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

function formatTime(ms) {
    if (!ms) return '—';
    const m = Math.floor(ms / 60000);
    const s = Math.floor((ms % 60000) / 1000);
    const mil = ms % 1000;
    return `${m}:${String(s).padStart(2, '0')}.${String(mil).padStart(3, '0')}`;
}

export default function ViewerLeaderboards() {
    const [games, setGames] = useState([]);
    const [activeGame, setActiveGame] = useState(null);
    const [leaderboard, setLeaderboard] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => { fetchGames(); }, []);

    useEffect(() => {
        if (activeGame) fetchLeaderboard();
    }, [activeGame]);

    useEffect(() => {
        const channel = supabase
            .channel('viewer-leaderboards')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'leaderboards' }, () => {
                if (activeGame) fetchLeaderboard();
            })
            .subscribe();
        return () => supabase.removeChannel(channel);
    }, [activeGame]);

    const fetchGames = async () => {
        const { data } = await supabase.from('games').select('*').order('name');
        setGames(data || []);
        if (data?.length > 0) setActiveGame(data[0]);
        setLoading(false);
    };

    const fetchLeaderboard = async () => {
        setLoading(true);
        const { data } = await supabase
            .from('leaderboards')
            .select('*, teams(team_name)')
            .eq('game_id', activeGame.id)
            .order('rank');
        setLeaderboard(data || []);
        setLoading(false);
    };

    const isF1 = activeGame?.slug === 'f1';
    const isBGMI = activeGame?.slug === 'bgmi';

    return (
        <div>
            <div className="page-header"><h1 className="text-gradient">Leaderboards</h1></div>

            <div className="tabs">
                {games.map(g => (
                    <button key={g.id} className={`tab ${activeGame?.id === g.id ? 'active' : ''}`} onClick={() => setActiveGame(g)}>
                        {g.name}
                    </button>
                ))}
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : leaderboard.length === 0 ? (
                    <div className="empty-state"><Trophy size={32} /><p>Leaderboard not yet available</p></div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th style={{ width: 70 }}>Rank</th>
                                    <th>Team</th>
                                    {isF1 ? (
                                        <th>Best Lap</th>
                                    ) : (
                                        <>
                                            <th>Points</th>
                                            {isBGMI && <th>Total Kills</th>}
                                            <th>Wins</th>
                                        </>
                                    )}
                                    <th>Matches</th>
                                </tr>
                            </thead>
                            <tbody>
                                {leaderboard.map((e, i) => {
                                    const rankColors = ['var(--neon-yellow)', '#c0c0c0', 'var(--neon-orange)'];
                                    return (
                                        <tr key={e.id} style={i < 3 ? { background: 'rgba(181, 55, 242, 0.03)' } : {}}>
                                            <td>
                                                <span style={{
                                                    fontFamily: 'var(--font-display)',
                                                    fontWeight: 900,
                                                    fontSize: i < 3 ? '1.2rem' : '0.9rem',
                                                    color: rankColors[i] || 'var(--text-primary)',
                                                }}>
                                                    #{e.rank || i + 1}
                                                </span>
                                            </td>
                                            <td style={{ fontWeight: 700, fontSize: i < 3 ? '0.95rem' : '0.85rem' }}>{e.teams?.team_name}</td>
                                            {isF1 ? (
                                                <td style={{ fontFamily: 'var(--font-display)', color: 'var(--neon-cyan)', fontWeight: 700 }}>
                                                    <Clock size={12} style={{ display: 'inline', marginRight: 4 }} />
                                                    {formatTime(e.extra_data?.best_time_ms)}
                                                </td>
                                            ) : (
                                                <>
                                                    <td style={{ fontFamily: 'var(--font-display)', fontWeight: 800, fontSize: '1rem', color: 'var(--neon-purple)' }}>
                                                        {e.total_points}
                                                    </td>
                                                    {isBGMI && (
                                                        <td style={{ color: 'var(--neon-red)', fontWeight: 600 }}>{e.total_kills || 0}</td>
                                                    )}
                                                    <td>{e.wins || 0}</td>
                                                </>
                                            )}
                                            <td style={{ color: 'var(--text-muted)' }}>{e.matches_played}</td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}
