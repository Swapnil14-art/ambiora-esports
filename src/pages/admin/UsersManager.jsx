import { useState, useEffect } from 'react';
import { supabase, supabaseAdmin } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2, UserPlus, Shield, Eye, Gamepad2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function UsersManager() {
    const { profile } = useAuth();
    const toast = useToast();
    const [users, setUsers] = useState([]);
    const [games, setGames] = useState([]);
    const [loading, setLoading] = useState(true);
    const [modalOpen, setModalOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [form, setForm] = useState({
        email: '',
        password: '',
        display_name: '',
        role: 'game_leader',
        assigned_game_id: '',
    });

    useEffect(() => {
        fetchUsers();
        fetchGames();
    }, []);

    const fetchGames = async () => {
        const { data } = await supabase.from('games').select('*').order('name');
        setGames(data || []);
    };

    const fetchUsers = async () => {
        const { data, error } = await supabase
            .from('profiles')
            .select('*, games(name, slug)')
            .order('created_at', { ascending: false });
        if (error) console.error(error);
        setUsers(data || []);
        setLoading(false);
    };

    const openCreate = () => {
        setEditing(null);
        setForm({
            email: '',
            password: '',
            display_name: '',
            role: 'game_leader',
            assigned_game_id: '',
        });
        setModalOpen(true);
    };

    const openEdit = (user) => {
        setEditing(user);
        setForm({
            email: user.email,
            password: '',
            display_name: user.display_name || '',
            role: user.role,
            assigned_game_id: user.assigned_game_id || '',
        });
        setModalOpen(true);
    };

    const handleCreate = async () => {
        if (!form.email || !form.password || !form.display_name) {
            toast.error('Email, password, and name are required');
            return;
        }

        if (form.password.length < 6) {
            toast.error('Password must be at least 6 characters');
            return;
        }

        if (form.role === 'game_leader' && !form.assigned_game_id) {
            toast.error('Game leaders must be assigned to a game');
            return;
        }

        if (!supabaseAdmin) {
            toast.error('Service role key not configured in .env');
            return;
        }

        try {
            // Create auth user via admin API (won't affect current session)
            const { data: newUser, error: authError } = await supabaseAdmin.auth.admin.createUser({
                email: form.email,
                password: form.password,
                email_confirm: true,
                user_metadata: {
                    display_name: form.display_name,
                    role: form.role,
                    assigned_game_id: form.role === 'game_leader' ? form.assigned_game_id : null,
                },
            });

            if (authError) {
                toast.error(authError.message);
                return;
            }

            await supabase.from('audit_logs').insert({
                user_id: profile.id,
                action: `Created user: ${form.email} (${form.role})`,
                details: { new_user_id: newUser.user.id, role: form.role },
            });

            toast.success(`User ${form.email} created successfully`);
            setModalOpen(false);
            // Wait a moment for the trigger to create the profile
            setTimeout(fetchUsers, 1000);
        } catch (err) {
            toast.error(err.message);
        }
    };

    const handleUpdate = async () => {
        if (!editing) return;

        // Update profile in the profiles table
        const updates = {
            display_name: form.display_name,
            role: form.role,
            assigned_game_id: form.role === 'game_leader' ? form.assigned_game_id : null,
        };

        const { error: profileError } = await supabase
            .from('profiles')
            .update(updates)
            .eq('id', editing.id);

        if (profileError) {
            toast.error(profileError.message);
            return;
        }

        // Update password if provided
        if (form.password && supabaseAdmin) {
            const { error: passError } = await supabaseAdmin.auth.admin.updateUserById(editing.id, {
                password: form.password,
            });
            if (passError) {
                toast.error(`Profile updated but password change failed: ${passError.message}`);
                return;
            }
        }

        await supabase.from('audit_logs').insert({
            user_id: profile.id,
            action: `Updated user: ${editing.email} (role → ${form.role})`,
            details: { target_user_id: editing.id },
        });

        toast.success('User updated');
        setModalOpen(false);
        fetchUsers();
    };

    const handleDelete = async (user) => {
        if (user.id === profile.id) {
            toast.error("You can't delete your own account");
            return;
        }
        if (!window.confirm(`Delete user "${user.email}"? This cannot be undone.`)) return;

        if (!supabaseAdmin) {
            toast.error('Service role key not configured');
            return;
        }

        // Delete from auth (profile will cascade delete via trigger)
        const { error } = await supabaseAdmin.auth.admin.deleteUser(user.id);
        if (error) {
            toast.error(error.message);
            return;
        }

        await supabase.from('audit_logs').insert({
            user_id: profile.id,
            action: `Deleted user: ${user.email}`,
            details: { deleted_user_id: user.id },
        });

        toast.success('User deleted');
        fetchUsers();
    };

    const getRoleBadge = (role) => {
        switch (role) {
            case 'admin': return <span className="badge badge-admin"><Shield size={10} /> Admin</span>;
            case 'game_leader': return <span className="badge badge-leader"><Gamepad2 size={10} /> Game Leader</span>;
            default: return <span className="badge badge-viewer"><Eye size={10} /> Viewer</span>;
        }
    };

    return (
        <div>
            <div className="page-header">
                <h1>User Management</h1>
                <div className="page-header-actions">
                    <button className="btn btn-primary" onClick={openCreate}>
                        <UserPlus size={14} /> Create User
                    </button>
                </div>
            </div>

            {!supabaseAdmin && (
                <div style={{
                    padding: 'var(--space-md)',
                    background: 'rgba(255, 62, 62, 0.1)',
                    border: '1px solid rgba(255, 62, 62, 0.3)',
                    borderRadius: 'var(--radius-sm)',
                    marginBottom: 'var(--space-lg)',
                    fontSize: '0.85rem',
                    color: 'var(--neon-red)',
                }}>
                    ⚠️ Service Role Key not configured. Add <code>VITE_SUPABASE_SERVICE_ROLE_KEY</code> to your <code>.env</code> file to enable user creation and deletion.
                    You can find it in Supabase Dashboard → Settings → API → <strong>service_role</strong> (secret).
                </div>
            )}

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : users.length === 0 ? (
                    <div className="empty-state"><p>No users found</p></div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Name</th>
                                    <th>Email</th>
                                    <th>Role</th>
                                    <th>Assigned Game</th>
                                    <th>Created</th>
                                    <th style={{ textAlign: 'right' }}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {users.map(u => (
                                    <tr key={u.id}>
                                        <td style={{ fontWeight: 600 }}>{u.display_name || '—'}</td>
                                        <td style={{ color: 'var(--text-secondary)' }}>{u.email}</td>
                                        <td>{getRoleBadge(u.role)}</td>
                                        <td>
                                            {u.games ? (
                                                <span className="badge badge-upcoming">{u.games.name}</span>
                                            ) : (
                                                <span style={{ color: 'var(--text-muted)' }}>—</span>
                                            )}
                                        </td>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>
                                            {new Date(u.created_at).toLocaleDateString()}
                                        </td>
                                        <td className="cell-actions">
                                            <button className="btn-icon" onClick={() => openEdit(u)} title="Edit">
                                                <Pencil size={14} />
                                            </button>
                                            {u.id !== profile.id && (
                                                <button className="btn-icon" onClick={() => handleDelete(u)} title="Delete" style={{ color: 'var(--neon-red)' }}>
                                                    <Trash2 size={14} />
                                                </button>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            <Modal
                isOpen={modalOpen}
                onClose={() => setModalOpen(false)}
                title={editing ? 'Edit User' : 'Create User'}
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
                        <button className="btn btn-primary" onClick={editing ? handleUpdate : handleCreate}>
                            {editing ? 'Update' : 'Create User'}
                        </button>
                    </>
                }
            >
                <div className="form-group">
                    <label className="form-label">Display Name</label>
                    <input
                        className="form-input"
                        value={form.display_name}
                        onChange={e => setForm({ ...form, display_name: e.target.value })}
                        placeholder="e.g. BGMI Lead, Admin"
                        autoFocus
                    />
                </div>
                <div className="form-group">
                    <label className="form-label">Email</label>
                    <input
                        className="form-input"
                        type="email"
                        value={form.email}
                        onChange={e => setForm({ ...form, email: e.target.value })}
                        placeholder="user@ambiora.in"
                        disabled={!!editing}
                    />
                    {editing && (
                        <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>Email cannot be changed after creation</span>
                    )}
                </div>
                <div className="form-group">
                    <label className="form-label">{editing ? 'New Password (leave blank to keep current)' : 'Password'}</label>
                    <input
                        className="form-input"
                        type="password"
                        value={form.password}
                        onChange={e => setForm({ ...form, password: e.target.value })}
                        placeholder={editing ? 'Leave blank to keep current' : 'Min 6 characters'}
                    />
                </div>
                <div className="form-group">
                    <label className="form-label">Role</label>
                    <select
                        className="form-select"
                        value={form.role}
                        onChange={e => setForm({ ...form, role: e.target.value })}
                    >
                        <option value="admin">Admin — Full access to everything</option>
                        <option value="game_leader">Game Leader — Manages one game</option>
                    </select>
                </div>
                {form.role === 'game_leader' && (
                    <div className="form-group">
                        <label className="form-label">Assigned Game</label>
                        <select
                            className="form-select"
                            value={form.assigned_game_id}
                            onChange={e => setForm({ ...form, assigned_game_id: e.target.value })}
                        >
                            <option value="">Select a game</option>
                            {games.map(g => (
                                <option key={g.id} value={g.id}>{g.name}</option>
                            ))}
                        </select>
                    </div>
                )}
            </Modal>
        </div>
    );
}
