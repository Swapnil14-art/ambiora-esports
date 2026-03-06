import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderPlayers() {
    const { profile } = useAuth();
    const toast = useToast();
    const [players, setPlayers] = useState([]);
    const [teams, setTeams] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filterTeam, setFilterTeam] = useState('');
    const [modalOpen, setModalOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [form, setForm] = useState({ name: '', phone: '', year_of_study: '', in_game_name: '', team_id: '' });

    const gameId = profile?.assigned_game_id;

    useEffect(() => {
        if (gameId) {
            fetchTeams();
            fetchPlayers();
        }
    }, [gameId, filterTeam]);

    const fetchTeams = async () => {
        const { data } = await supabase
            .from('teams')
            .select('*')
            .eq('game_id', gameId)
            .eq('created_by', profile.id) // Security constraint
            .order('team_name');
        setTeams(data || []);
    };

    const fetchPlayers = async () => {
        let query = supabase
            .from('players')
            .select('*, teams!inner(team_name, game_id, created_by)')
            .order('name');

        if (filterTeam) {
            query = query.eq('team_id', filterTeam);
        } else {
            // Only fetch players whose team was created by THIS user
            query = query.eq('teams.created_by', profile.id);
        }

        const { data } = await query;
        // Filter to only this game's teams (redundant if teams.created_by is enforced and they only made teams for 1 game, but safe)
        const filtered = (data || []).filter(p => p.teams?.game_id === gameId);
        setPlayers(filtered);
        setLoading(false);
    };

    const openCreate = () => {
        setEditing(null);
        setForm({ name: '', phone: '', year_of_study: '', in_game_name: '', team_id: teams[0]?.id || '' });
        setModalOpen(true);
    };

    const openEdit = (player) => {
        setEditing(player);
        setForm({
            name: player.name,
            phone: player.phone || '',
            year_of_study: player.year_of_study || '',
            in_game_name: player.in_game_name || '',
            team_id: player.team_id,
        });
        setModalOpen(true);
    };

    const handleSave = async () => {
        if (!form.name.trim() || !form.team_id) { toast.error('Name and team required'); return; }

        // Security check: Make sure they actually own the team they are assigning the player to
        const ownsTeam = teams.some(t => t.id === form.team_id);
        if (!ownsTeam) {
            toast.error('You do not have permission to modify this team.');
            return;
        }

        const payload = {
            name: form.name.trim(),
            phone: form.phone || null,
            year_of_study: form.year_of_study || null,
            in_game_name: form.in_game_name || null,
            team_id: form.team_id,
        };

        if (editing) {
            // Editing an existing player: The player MUST belong to a team they own
            const ownsExistingTeam = teams.some(t => t.id === editing.team_id);
            if (!ownsExistingTeam) {
                toast.error('Permission denied.');
                return;
            }

            const { error } = await supabase.from('players').update(payload).eq('id', editing.id);
            if (error) { toast.error(error.message); return; }
            await supabase.from('audit_logs').insert({ user_id: profile.id, action: `Leader updated player: ${form.name}`, details: { player_id: editing.id } });
            toast.success('Player updated');
        } else {
            const { error } = await supabase.from('players').insert(payload);
            if (error) { toast.error(error.message); return; }
            await supabase.from('audit_logs').insert({ user_id: profile.id, action: `Leader added player: ${form.name}`, details: { team_id: form.team_id } });
            toast.success('Player added');
        }
        setModalOpen(false);
        fetchPlayers();
    };

    const handleDelete = async (player) => {
        if (!window.confirm(`Delete "${player.name}"?`)) return;

        // Security check: Ensure they own the team this player belongs to
        const ownsTeam = teams.some(t => t.id === player.team_id);
        if (!ownsTeam) {
            toast.error('Permission denied.');
            return;
        }

        const { error } = await supabase.from('players').delete().eq('id', player.id);
        if (error) { toast.error(error.message); return; }
        toast.success('Player deleted');
        fetchPlayers();
    };

    return (
        <div>
            <div className="page-header">
                <h1>Players</h1>
            </div>

            <div className="filters-bar">
                <select className="form-select" value={filterTeam} onChange={e => setFilterTeam(e.target.value)}>
                    <option value="">All My Teams</option>
                    {teams.map(t => <option key={t.id} value={t.id}>{t.team_name}</option>)}
                </select>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : players.length === 0 ? (
                    <div className="empty-state"><p>No players found.</p></div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Name</th>
                                    <th>IGN</th>
                                    <th>Team</th>
                                    <th>Phone</th>
                                    <th>Year</th>
                                </tr>
                            </thead>
                            <tbody>
                                {players.map(p => (
                                    <tr key={p.id}>
                                        <td style={{ fontWeight: 600 }}>{p.name}</td>
                                        <td style={{ color: 'var(--neon-cyan)' }}>{p.in_game_name || '—'}</td>
                                        <td>{p.teams?.team_name}</td>
                                        <td style={{ color: 'var(--text-secondary)' }}>{p.phone || '—'}</td>
                                        <td style={{ color: 'var(--text-secondary)' }}>{p.year_of_study || '—'}</td>
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
