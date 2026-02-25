import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useRealtimeSubscription } from '../../hooks/useRealtimeSubscription';
import { Calendar, Clock } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderFixtures() {
    const { profile } = useAuth();
    const gameId = profile?.assigned_game_id;
    const [matches, setMatches] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (gameId) fetchMatches();
    }, [gameId]);

    // Realtime subscription for matches
    useEffect(() => {
        if (!gameId) return;
        const channel = supabase
            .channel('leader-matches')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, () => fetchMatches())
            .subscribe();
        return () => supabase.removeChannel(channel);
    }, [gameId]);

    const fetchMatches = async () => {
        const { data } = await supabase
            .from('matches')
            .select('*, match_teams(team_id, teams(team_name))')
            .eq('game_id', gameId)
            .order('scheduled_at', { ascending: true, nullsFirst: false });
        setMatches(data || []);
        setLoading(false);
    };

    if (loading) return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="table" count={5} /></div>;

    return (
        <div>
            <div className="page-header">
                <h1>Fixtures</h1>
            </div>

            <div className="card" style={{ padding: 0 }}>
                {matches.length === 0 ? (
                    <div className="empty-state"><Calendar size={32} /><p>No fixtures yet</p></div>
                ) : (
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
                )}
            </div>
        </div>
    );
}
