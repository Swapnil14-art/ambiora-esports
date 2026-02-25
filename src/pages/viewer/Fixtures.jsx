import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { Calendar } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function ViewerFixtures() {
    const [games, setGames] = useState([]);
    const [activeGame, setActiveGame] = useState(null);
    const [matches, setMatches] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        fetchGames();
    }, []);

    useEffect(() => {
        if (activeGame) fetchMatches();
    }, [activeGame]);

    // Realtime
    useEffect(() => {
        const channel = supabase
            .channel('viewer-fixtures')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, () => {
                if (activeGame) fetchMatches();
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

    const fetchMatches = async () => {
        setLoading(true);
        const { data } = await supabase
            .from('matches')
            .select('*, match_teams(team_id, teams(team_name))')
            .eq('game_id', activeGame.id)
            .order('scheduled_at', { ascending: true, nullsFirst: false });
        setMatches(data || []);
        setLoading(false);
    };

    return (
        <div>
            <div className="page-header">
                <h1 className="text-gradient">Fixtures</h1>
            </div>

            <div className="tabs">
                {games.map(g => (
                    <button key={g.id} className={`tab ${activeGame?.id === g.id ? 'active' : ''}`} onClick={() => setActiveGame(g)}>
                        {g.name}
                    </button>
                ))}
            </div>

            <div className="card" style={{ padding: 0 }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : matches.length === 0 ? (
                    <div className="empty-state"><Calendar size={32} /><p>No fixtures scheduled</p></div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Round</th>
                                    <th>#</th>
                                    <th>Matchup</th>
                                    <th>Status</th>
                                    <th>Type</th>
                                    <th>Scheduled</th>
                                </tr>
                            </thead>
                            <tbody>
                                {matches.map(m => (
                                    <tr key={m.id}>
                                        <td style={{ fontWeight: 600 }}>{m.round}</td>
                                        <td>{m.match_number}</td>
                                        <td style={{ fontSize: '0.85rem' }}>
                                            {m.match_teams?.map(mt => mt.teams?.team_name).join(' vs ') || 'TBD'}
                                        </td>
                                        <td><span className={`badge badge-${m.status}`}>{m.status}</span></td>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>
                                            {m.best_of > 1 ? `BO${m.best_of}` : m.match_type || 'Standard'}
                                        </td>
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
    );
}
