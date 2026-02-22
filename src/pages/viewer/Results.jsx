import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { ClipboardList } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function ViewerResults() {
    const [games, setGames] = useState([]);
    const [activeGame, setActiveGame] = useState(null);
    const [matches, setMatches] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => { fetchGames(); }, []);

    useEffect(() => {
        if (activeGame) fetchResults();
    }, [activeGame]);

    useEffect(() => {
        const channel = supabase
            .channel('viewer-results')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'match_results' }, () => {
                if (activeGame) fetchResults();
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

    const fetchResults = async () => {
        setLoading(true);
        const { data } = await supabase
            .from('matches')
            .select('*, match_results(*, teams(team_name))')
            .eq('game_id', activeGame.id)
            .eq('status', 'completed')
            .order('updated_at', { ascending: false });
        setMatches(data || []);
        setLoading(false);
    };

    const isF1 = activeGame?.slug === 'f1';

    const formatTime = (ms) => {
        if (!ms) return '—';
        const m = Math.floor(ms / 60000);
        const s = Math.floor((ms % 60000) / 1000);
        const mil = ms % 1000;
        return `${m}:${String(s).padStart(2, '0')}.${String(mil).padStart(3, '0')}`;
    };

    return (
        <div>
            <div className="page-header"><h1 className="text-gradient">Results</h1></div>

            <div className="tabs">
                {games.map(g => (
                    <button key={g.id} className={`tab ${activeGame?.id === g.id ? 'active' : ''}`} onClick={() => setActiveGame(g)}>
                        {g.name}
                    </button>
                ))}
            </div>

            {loading ? (
                <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="card" count={3} /></div>
            ) : matches.length === 0 ? (
                <div className="empty-state"><ClipboardList size={32} /><p>No completed matches</p></div>
            ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-md)' }}>
                    {matches.map(m => (
                        <div key={m.id} className="card">
                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '10px' }}>
                                <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase' }}>
                                    {m.round} #{m.match_number}
                                </span>
                                <span className="badge badge-completed">Completed</span>
                            </div>
                            {m.match_results?.length > 0 ? (
                                <div className="table-responsive">
                                    <table className="data-table" style={{ fontSize: '0.8rem' }}>
                                        <thead>
                                            <tr>
                                                <th>Team</th>
                                                <th>Score</th>
                                                {!isF1 && <th>Placement</th>}
                                                {!isF1 && <th>Kills</th>}
                                                {isF1 && <th>Lap Time</th>}
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {m.match_results.sort((a, b) => (a.placement || 99) - (b.placement || 99)).map(r => (
                                                <tr key={r.id}>
                                                    <td style={{ fontWeight: 600 }}>{r.teams?.team_name || '—'}</td>
                                                    <td style={{ color: 'var(--neon-purple)' }}>{r.score}</td>
                                                    {!isF1 && <td>{r.placement || '—'}</td>}
                                                    {!isF1 && <td style={{ color: 'var(--neon-red)' }}>{r.kills}</td>}
                                                    {isF1 && <td style={{ color: 'var(--neon-cyan)', fontFamily: 'var(--font-display)' }}>{formatTime(r.time_ms)}</td>}
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            ) : (
                                <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>No results recorded</p>
                            )}
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
