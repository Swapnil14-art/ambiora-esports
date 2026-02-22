import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderResults() {
    const { profile } = useAuth();
    const gameId = profile?.assigned_game_id;
    const [matches, setMatches] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (gameId) fetchResults();
    }, [gameId]);

    useEffect(() => {
        if (!gameId) return;
        const channel = supabase
            .channel('leader-results')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'match_results' }, () => fetchResults())
            .subscribe();
        return () => supabase.removeChannel(channel);
    }, [gameId]);

    const fetchResults = async () => {
        const { data } = await supabase
            .from('matches')
            .select('*, match_teams(team_id, teams(team_name)), match_results(*, teams(team_name))')
            .eq('game_id', gameId)
            .eq('status', 'completed')
            .order('updated_at', { ascending: false });
        setMatches(data || []);
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="card" count={4} /></div>;

    return (
        <div>
            <div className="page-header"><h1>Results</h1></div>

            {matches.length === 0 ? (
                <div className="empty-state"><p>No completed matches yet</p></div>
            ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-md)' }}>
                    {matches.map(m => (
                        <div key={m.id} className="card">
                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                                <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.8rem', fontWeight: 700 }}>
                                    {m.round} #{m.match_number}
                                </span>
                                <span className="badge badge-completed">Completed</span>
                            </div>
                            {m.match_results?.length > 0 ? (
                                <table className="data-table" style={{ fontSize: '0.8rem' }}>
                                    <thead>
                                        <tr>
                                            <th>Team</th>
                                            <th>Score</th>
                                            <th>Placement</th>
                                            <th>Kills</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {m.match_results.sort((a, b) => (a.placement || 99) - (b.placement || 99)).map(r => (
                                            <tr key={r.id}>
                                                <td style={{ fontWeight: 600 }}>{r.teams?.team_name || '—'}</td>
                                                <td style={{ color: 'var(--neon-purple)' }}>{r.score}</td>
                                                <td>{r.placement || '—'}</td>
                                                <td style={{ color: 'var(--neon-red)' }}>{r.kills}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            ) : (
                                <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>No results entered</p>
                            )}
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
