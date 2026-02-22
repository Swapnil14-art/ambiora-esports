import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function LeaderTeams() {
    const { profile } = useAuth();
    const toast = useToast();
    const [teams, setTeams] = useState([]);
    const [loading, setLoading] = useState(true);
    const [modalOpen, setModalOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [form, setForm] = useState({ team_name: '' });

    const gameId = profile?.assigned_game_id;

    useEffect(() => {
        if (gameId) fetchTeams();
    }, [gameId]);

    const fetchTeams = async () => {
        const { data: memberRows } = await supabase
            .from('players')
            .select('teams(*, players(id))')
            .eq('user_id', profile.id)
            .eq('role', 'leader')
            .eq('teams.game_id', gameId);

        const validTeams = (memberRows || []).map(r => r.teams).filter(t => t !== null);

        // Sort alphabetically
        validTeams.sort((a, b) => a.team_name.localeCompare(b.team_name));

        setTeams(validTeams);
        setLoading(false);
    };

    const openCreate = () => {
        setEditing(null);
        setForm({ team_name: '' });
        setModalOpen(true);
    };

    const openEdit = (team) => {
        setEditing(team);
        setForm({ team_name: team.team_name });
        setModalOpen(true);
    };

    const handleSave = async () => {
        if (!form.team_name.trim()) { toast.error('Team name required'); return; }

        if (editing) {
            const { error } = await supabase
                .from('teams')
                .update({ team_name: form.team_name.trim() })
                .eq('id', editing.id);

            if (error) { toast.error(error.message); return; }
            await supabase.from('audit_logs').insert({ user_id: profile.id, action: `Leader updated team: ${form.team_name}`, details: { team_id: editing.id } });
            toast.success('Team updated');
        } else {
            const { data: newTeam, error } = await supabase.from('teams').insert({ team_name: form.team_name.trim(), game_id: gameId, created_by: profile.id }).select('id').single();
            if (error) { toast.error(error.message); return; }

            const { error: rosterErr } = await supabase.from('players').insert({
                team_id: newTeam.id,
                user_id: profile.id,
                name: profile.display_name || profile.email || 'Leader',
                in_game_name: profile.display_name || 'Captain',
                role: 'leader'
            });

            if (rosterErr) {
                console.error("Failed to add leader to roster:", rosterErr);
                toast.error('Team created but failed to assign leadership role.');
            }

            await supabase.from('audit_logs').insert({ user_id: profile.id, action: `Leader created team: ${form.team_name}`, details: { game_id: gameId } });
            toast.success('Team created');
        }
        setModalOpen(false);
        fetchTeams();
    };

    const handleDelete = async (team) => {
        if (!window.confirm(`Delete "${team.team_name}"?`)) return;
        const { error } = await supabase
            .from('teams')
            .delete()
            .eq('id', team.id);

        if (error) { toast.error(error.message); return; }
        toast.success('Team deleted');
        fetchTeams();
    };

    return (
        <div>
            <div className="page-header">
                <h1>My Teams</h1>
                <button className="btn btn-primary" onClick={openCreate}><Plus size={14} /> Create Team</button>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : teams.length === 0 ? (
                    <div className="empty-state"><p>No teams yet. Create your first team.</p></div>
                ) : (
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>Team Name</th>
                                <th>Players</th>
                                <th>Created</th>
                                <th style={{ textAlign: 'right' }}>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {teams.map(t => (
                                <tr key={t.id}>
                                    <td style={{ fontWeight: 600 }}>{t.team_name}</td>
                                    <td style={{ color: 'var(--neon-cyan)' }}>{t.players?.length || 0}</td>
                                    <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{new Date(t.created_at).toLocaleDateString()}</td>
                                    <td className="cell-actions">
                                        <button className="btn-icon" onClick={() => openEdit(t)}><Pencil size={14} /></button>
                                        <button className="btn-icon" onClick={() => handleDelete(t)} style={{ color: 'var(--neon-red)' }}><Trash2 size={14} /></button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>

            <Modal
                isOpen={modalOpen}
                onClose={() => setModalOpen(false)}
                title={editing ? 'Edit Team' : 'Create Team'}
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
                        <button className="btn btn-primary" onClick={handleSave}>{editing ? 'Update' : 'Create'}</button>
                    </>
                }
            >
                <div className="form-group">
                    <label className="form-label">Team Name</label>
                    <input className="form-input" value={form.team_name} onChange={e => setForm({ team_name: e.target.value })} placeholder="Team name" autoFocus />
                </div>
            </Modal>
        </div>
    );
}
