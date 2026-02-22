import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useToast } from '../../components/Toast';
import { Trophy, RefreshCw, Clock } from 'lucide-react';

const BGMI_PLACEMENT = { 1: 10, 2: 6, 3: 5, 4: 4, 5: 3, 6: 2, 7: 1, 8: 1 };

function formatTime(ms) {
    if (!ms) return '—';
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    const millis = ms % 1000;
    return `${minutes}:${String(seconds).padStart(2, '0')}.${String(millis).padStart(3, '0')}`;
}

export default function AdminLeaderboards() {
    const toast = useToast();
    const [games, setGames] = useState([]);
    const [activeGame, setActiveGame] = useState(null);
    const [leaderboard, setLeaderboard] = useState([]);
    const [loading, setLoading] = useState(true);
    const [recalculating, setRecalculating] = useState(false);

    useEffect(() => {
        fetchGames();
    }, []);

    useEffect(() => {
        if (activeGame) fetchLeaderboard();
    }, [activeGame]);

    const fetchGames = async () => {
        const { data } = await supabase.from('games').select('*').order('name');
        setGames(data || []);
        if (data?.length > 0) setActiveGame(data[0]);
        setLoading(false);
    };

    const fetchLeaderboard = async () => {
        setLoading(true);
        const { data, error } = await supabase
            .from('leaderboards')
            .select('*, teams(team_name)')
            .eq('game_id', activeGame.id)
            .order('rank', { ascending: true });
        if (error) console.error(error);
        setLeaderboard(data || []);
        setLoading(false);
    };

    const recalculate = async () => {
        if (!activeGame) return;
        setRecalculating(true);

        const funcMap = {
            bgmi: 'calculate_bgmi_leaderboard',
            valorant: 'calculate_valorant_standings',
            fifa25: 'calculate_fifa25_bracket',
            f1: 'calculate_f1_rankings',
        };

        const funcName = funcMap[activeGame.slug];
        if (funcName) {
            const { error } = await supabase.rpc(funcName, { p_game_id: activeGame.id });
            if (error) {
                toast.error(`Recalculation failed: ${error.message}`);
            } else {
                toast.success('Leaderboard recalculated');
                fetchLeaderboard();
            }
        }
        setRecalculating(false);
    };

    const isF1 = activeGame?.slug === 'f1';

    return (
        <div>
            <div className="page-header">
                <h1>Leaderboards</h1>
                <div className="page-header-actions">
                    <button className="btn btn-secondary" onClick={recalculate} disabled={recalculating}>
                        <RefreshCw size={14} className={recalculating ? 'spin' : ''} />
                        {recalculating ? 'Calculating...' : 'Recalculate'}
                    </button>
                </div>
            </div>

            <div className="tabs">
                {games.map(g => (
                    <button
                        key={g.id}
                        className={`tab ${activeGame?.id === g.id ? 'active' : ''}`}
                        onClick={() => setActiveGame(g)}
                    >
                        {g.name}
                    </button>
                ))}
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div className="loading-inline"><div className="loader"></div></div>
                ) : leaderboard.length === 0 ? (
                    <div className="empty-state">
                        <Trophy size={32} />
                        <p>No leaderboard data. Run matches and recalculate.</p>
                    </div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th style={{ width: 60 }}>Rank</th>
                                    <th>Team</th>
                                    {isF1 ? (
                                        <th>Best Lap</th>
                                    ) : (
                                        <>
                                            <th>Points</th>
                                            {activeGame?.slug === 'bgmi' && <th>Kills</th>}
                                            <th>Wins</th>
                                        </>
                                    )}
                                    <th>Played</th>
                                </tr>
                            </thead>
                            <tbody>
                                {leaderboard.map((entry, idx) => (
                                    <tr key={entry.id}>
                                        <td>
                                            <span style={{
                                                fontFamily: 'var(--font-display)',
                                                fontWeight: 800,
                                                fontSize: '1rem',
                                                color: idx === 0 ? 'var(--neon-yellow)' : idx === 1 ? 'var(--text-secondary)' : idx === 2 ? 'var(--neon-orange)' : 'var(--text-primary)',
                                            }}>
                                                #{entry.rank || idx + 1}
                                            </span>
                                        </td>
                                        <td style={{ fontWeight: 600, fontSize: '0.9rem' }}>{entry.teams?.team_name || '—'}</td>
                                        {isF1 ? (
                                            <td>
                                                <span style={{ fontFamily: 'var(--font-display)', color: 'var(--neon-cyan)' }}>
                                                    <Clock size={12} style={{ display: 'inline', marginRight: 4 }} />
                                                    {formatTime(entry.extra_data?.best_time_ms)}
                                                </span>
                                            </td>
                                        ) : (
                                            <>
                                                <td style={{ fontFamily: 'var(--font-display)', fontWeight: 700, color: 'var(--neon-purple)' }}>
                                                    {entry.total_points}
                                                </td>
                                                {activeGame?.slug === 'bgmi' && (
                                                    <td style={{ color: 'var(--neon-red)' }}>{entry.total_kills || 0}</td>
                                                )}
                                                <td>{entry.wins || 0}</td>
                                            </>
                                        )}
                                        <td style={{ color: 'var(--text-muted)' }}>{entry.matches_played || 0}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}
