import { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { supabase, supabaseAdmin } from '../../lib/supabase';
import { fetchWithCache, invalidateCache, hasValidCache } from '../../lib/cache';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2, Search, ArrowLeft, Gamepad2, Users, UserMinus, ShieldCheck, ShieldX } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function TeamsManager() {
    const { profile } = useAuth();
    const location = useLocation();
    const toast = useToast();

    const [games, setGames] = useState([]);
    const [selectedGame, setSelectedGame] = useState(null);

    const [teams, setTeams] = useState([]);
    const [searchTeam, setSearchTeam] = useState('');
    const [loadingTeams, setLoadingTeams] = useState(false);

    // Team CRUD Modal
    const [teamModalOpen, setTeamModalOpen] = useState(false);
    const [editingTeam, setEditingTeam] = useState(null);
    const [teamForm, setTeamForm] = useState({ team_name: '', logo_url: '', assigned_leader_id: '' });
    const [eligibleLeaders, setEligibleLeaders] = useState([]);

    // Roster / Player View
    const [selectedTeamForRoster, setSelectedTeamForRoster] = useState(null);
    const [players, setPlayers] = useState([]);
    const [loadingPlayers, setLoadingPlayers] = useState(false);
    const [showAddPlayer, setShowAddPlayer] = useState(false);
    const [newPlayerForm, setNewPlayerForm] = useState({ in_game_name: '', is_leader: false });

    useEffect(() => {
        fetchGames();
    }, []);

    const fetchGames = async () => {
        const data = await fetchWithCache('admin_games', async () => {
            const res = await supabase.from('games').select('*').order('name');
            return res.data;
        });
        setGames(data || []);

        if (data && location.state?.defaultGameId) {
            const game = data.find(g => g.id === location.state.defaultGameId);
            if (game) {
                handleSelectGame(game);
                // remove state to prevent re-triggering
                window.history.replaceState({}, '');
            }
        }
    };

    const handleSelectGame = async (game) => {
        setSelectedGame(game);
        const cacheKey = `admin_teams_${game.id}`;

        // Only show loading state if data is NOT in memory
        if (!hasValidCache(cacheKey)) {
            setLoadingTeams(true);
        }

        try {
            const data = await fetchWithCache(cacheKey, async () => {
                const res = await supabase
                    .from('teams')
                    .select('*, profiles(display_name, email)')
                    .eq('game_id', game.id)
                    .order('created_at', { ascending: false });
                if (res.error) throw res.error;
                return res.data;
            });
            setTeams(data || []);
        } catch (error) {
            toast.error('Failed to load teams');
            console.error(error);
        }
        setLoadingTeams(false);
    };

    // --- Team CRUD ---
    const openCreateTeam = async () => {
        setEditingTeam(null);
        setTeamForm({ team_name: '', logo_url: '', assigned_leader_id: '' });

        // Fetch eligible players (all non-admins)
        const { data } = await supabase
            .from('profiles')
            .select('id, display_name, email, role')
            .neq('role', 'admin');
        setEligibleLeaders(data || []);

        setTeamModalOpen(true);
    };

    const openEditTeam = (team) => {
        setEditingTeam(team);
        setTeamForm({ team_name: team.team_name, logo_url: team.logo_url || '' });
        setTeamModalOpen(true);
    };

    const handleSaveTeam = async () => {
        if (!teamForm.team_name.trim()) {
            toast.error('Team name is required');
            return;
        }

        if (editingTeam) {
            const { error } = await supabase.from('teams').update({
                team_name: teamForm.team_name.trim(),
                logo_url: teamForm.logo_url || null,
            }).eq('id', editingTeam.id);

            if (error) { toast.error(error.message); return; }

            await supabase.from('audit_logs').insert({
                user_id: profile.id, action: `Updated team: ${teamForm.team_name}`, details: { team_id: editingTeam.id },
            });
            toast.success('Team updated');
        } else {
            const designatedCreatorId = teamForm.assigned_leader_id ? teamForm.assigned_leader_id : profile.id;

            const { data: newTeam, error } = await supabase.from('teams').insert({
                team_name: teamForm.team_name.trim(),
                game_id: selectedGame.id,
                logo_url: teamForm.logo_url || null,
                created_by: designatedCreatorId,
            }).select('id').single();

            if (error) { toast.error(error.message); return; }

            await supabase.from('audit_logs').insert({
                user_id: profile.id, action: `Created team: ${teamForm.team_name}`, details: { game_id: selectedGame.id },
            });

            // Upgrade role if we assigned to someone else
            if (designatedCreatorId !== profile.id && supabaseAdmin) {
                const { error: roleErr } = await supabaseAdmin
                    .from('profiles')
                    .update({ role: 'game_leader', assigned_game_id: selectedGame.id })
                    .eq('id', designatedCreatorId);

                // Also assign them to the team's roster automatically
                const leaderProfile = eligibleLeaders.find(p => p.id === designatedCreatorId);
                const ign = leaderProfile ? (leaderProfile.display_name || leaderProfile.email.split('@')[0]) : 'Captain';

                const { error: rosterErr } = await supabaseAdmin
                    .from('players')
                    .insert({
                        team_id: newTeam.id,
                        user_id: designatedCreatorId,
                        name: leaderProfile ? (leaderProfile.display_name || leaderProfile.email) : 'Leader',
                        in_game_name: ign,
                        role: 'leader'
                    });

                if (roleErr) {
                    toast.error("Team created, but failed to upgrade user to Team Leader.");
                } else if (rosterErr) {
                    toast.error("Team created & user upgraded, but failed to auto-add them to roster.");
                } else {
                    toast.success('Team created, user upgraded, and auto-added to roster!');
                }
            } else {
                toast.success('Team created');
            }
        }

        setTeamModalOpen(false);
        handleSelectGame(selectedGame); // Refresh
    };

    const handleDeleteTeam = async (team) => {
        if (!window.confirm(`Delete team "${team.team_name}"? This will also delete all its players.`)) return;

        const { error } = await supabase.from('teams').delete().eq('id', team.id);
        if (error) { toast.error(error.message); return; }

        await supabase.from('audit_logs').insert({
            user_id: profile.id, action: `Deleted team: ${team.team_name}`, details: { team_id: team.id, game: selectedGame.name },
        });

        toast.success('Team deleted');
        handleSelectGame(selectedGame); // Refresh
    };

    const handleToggleStatus = async (team) => {
        const newStatus = team.status === 'disqualified' ? 'qualified' : 'disqualified';
        const { error } = await supabase
            .from('teams')
            .update({ status: newStatus })
            .eq('id', team.id);

        if (error) { toast.error(error.message); return; }

        await supabase.from('audit_logs').insert({
            user_id: profile.id,
            action: `${newStatus === 'disqualified' ? 'Disqualified' : 'Re-qualified'} team: ${team.team_name}`,
            details: { team_id: team.id, game: selectedGame.name, new_status: newStatus },
        });

        toast.success(`Team ${newStatus === 'disqualified' ? 'disqualified' : 're-qualified'}`);
        invalidateCache(`admin_teams_${selectedGame.id}`);
        invalidateCache('admin_all_teams');
        handleSelectGame(selectedGame);
    };

    // --- Roster Viewing ---
    const handleViewRoster = async (team) => {
        setSelectedTeamForRoster(team);
        setLoadingPlayers(true);
        const { data, error } = await supabase
            .from('players')
            .select('*')
            .eq('team_id', team.id)
            .order('created_at', { ascending: true });

        if (error) {
            toast.error('Failed to load roster');
        } else {
            setPlayers(data || []);
        }
        setLoadingPlayers(false);
    };

    const handleRemovePlayer = async (player) => {
        if (!window.confirm(`Remove ${player.in_game_name} from the roster?`)) return;
        const { error } = await supabase.from('players').delete().eq('id', player.id);
        if (error) {
            toast.error(error.message);
        } else {
            toast.success('Player removed');
            setPlayers(players.filter(p => p.id !== player.id));
        }
    };

    const handleAddPlayer = async (e) => {
        e.preventDefault();
        if (!newPlayerForm.in_game_name.trim()) {
            toast.error('In-game name is required');
            return;
        }

        const { data, error } = await supabase
            .from('players')
            .insert({
                team_id: selectedTeamForRoster.id,
                name: newPlayerForm.in_game_name.trim(),
                in_game_name: newPlayerForm.in_game_name.trim(),
                role: newPlayerForm.is_leader ? 'leader' : 'member'
            })
            .select()
            .single();

        if (error) {
            toast.error(error.message);
        } else {
            toast.success('Player added');
            setPlayers([...players, data]);
            setNewPlayerForm({ in_game_name: '', is_leader: false });
            setShowAddPlayer(false);
        }
    };


    // --- Render Helpers ---
    const filteredTeams = teams.filter(t => t.team_name.toLowerCase().includes(searchTeam.toLowerCase()));

    // LEVEL 1: Game Selection View
    if (!selectedGame) {
        return (
            <div>
                <div className="page-header">
                    <h1>Select a Game</h1>
                    <p style={{ color: 'var(--text-secondary)' }}>Choose a game bracket to view and manage its teams.</p>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))', gap: '20px', marginTop: '20px' }}>
                    {games.map(game => (
                        <div
                            key={game.id}
                            className="card"
                            style={{ cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px 20px', transition: 'transform 0.2s', border: '1px solid rgba(255,255,255,0.05)' }}
                            onClick={() => handleSelectGame(game)}
                            onMouseEnter={(e) => e.currentTarget.style.transform = 'translateY(-5px)'}
                            onMouseLeave={(e) => e.currentTarget.style.transform = 'translateY(0)'}
                        >
                            <Gamepad2 size={40} style={{ color: 'var(--neon-purple)', marginBottom: '16px' }} />
                            <h3 style={{ margin: 0, fontSize: '1.2rem' }}>{game.name}</h3>
                        </div>
                    ))}
                </div>
            </div>
        );
    }

    // LEVEL 2: Teams View
    return (
        <div>
            <div className="page-header" style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <button className="btn-icon" onClick={() => setSelectedGame(null)} title="Back to Games" style={{ background: 'rgba(255,255,255,0.05)', padding: '8px', borderRadius: '8px' }}>
                    <ArrowLeft size={20} />
                </button>
                <div style={{ flex: 1 }}>
                    <h1 style={{ margin: 0 }}>{selectedGame.name} Teams</h1>
                </div>
                <div className="page-header-actions">
                    <button className="btn btn-primary" onClick={openCreateTeam}>
                        <Plus size={14} /> Create Team
                    </button>
                </div>
            </div>

            <div className="filters-bar">
                <div style={{ position: 'relative', flex: 1, maxWidth: '400px' }}>
                    <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                    <input
                        className="form-input"
                        placeholder="Search teams in this bracket..."
                        value={searchTeam}
                        onChange={e => setSearchTeam(e.target.value)}
                        style={{ paddingLeft: 30, width: '100%' }}
                    />
                </div>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loadingTeams ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : filteredTeams.length === 0 ? (
                    <div className="empty-state"><p>No teams found for {selectedGame.name}</p></div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Team Name</th>
                                    <th>Status</th>
                                    <th>Led By</th>
                                    <th>Created</th>
                                    <th style={{ textAlign: 'right' }}>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {filteredTeams.map(team => (
                                    <tr key={team.id} style={team.status === 'disqualified' ? { opacity: 0.6, background: 'rgba(255, 62, 62, 0.04)' } : {}}>
                                        <td style={{ fontWeight: 600 }}>{team.team_name}</td>
                                        <td>
                                            {team.status === 'disqualified' ? (
                                                <span className="badge" style={{ background: 'rgba(255, 62, 62, 0.15)', color: 'var(--neon-red)', border: '1px solid rgba(255, 62, 62, 0.3)', fontSize: '0.7rem' }}>DISQUALIFIED</span>
                                            ) : (
                                                <span className="badge" style={{ background: 'rgba(0, 255, 136, 0.1)', color: 'var(--neon-green)', border: '1px solid rgba(0, 255, 136, 0.3)', fontSize: '0.7rem' }}>QUALIFIED</span>
                                            )}
                                        </td>
                                        <td style={{ color: 'var(--text-secondary)' }}>{team.profiles?.display_name || team.profiles?.email || '—'}</td>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>{new Date(team.created_at).toLocaleDateString()}</td>
                                        <td className="cell-actions">
                                            <button
                                                className="btn btn-secondary"
                                                onClick={() => handleToggleStatus(team)}
                                                title={team.status === 'disqualified' ? 'Re-qualify Team' : 'Disqualify Team'}
                                                style={{
                                                    padding: '5px 10px',
                                                    fontSize: '0.75rem',
                                                    color: team.status === 'disqualified' ? 'var(--neon-green)' : 'var(--neon-red)',
                                                    borderColor: team.status === 'disqualified' ? 'rgba(0, 255, 136, 0.3)' : 'rgba(255, 62, 62, 0.3)',
                                                    gap: '4px',
                                                }}
                                            >
                                                {team.status === 'disqualified' ? <ShieldCheck size={13} /> : <ShieldX size={13} />}
                                                {team.status === 'disqualified' ? 'Qualify' : 'DQ'}
                                            </button>
                                            <button className="btn btn-secondary" onClick={() => handleViewRoster(team)} style={{ padding: '6px 12px', fontSize: '0.85rem' }}>
                                                <Users size={14} style={{ marginRight: '6px' }} /> Roster
                                            </button>
                                            <button className="btn-icon" onClick={() => openEditTeam(team)} title="Edit Team">
                                                <Pencil size={18} />
                                            </button>
                                            <button className="btn-icon" onClick={() => handleDeleteTeam(team)} title="Delete Team" style={{ color: 'var(--neon-red)' }}>
                                                <Trash2 size={18} />
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {/* TEAM CRUD MODAL */}
            <Modal
                isOpen={teamModalOpen}
                onClose={() => setTeamModalOpen(false)}
                title={editingTeam ? 'Edit Team' : 'Create Team in ' + selectedGame.name}
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setTeamModalOpen(false)}>Cancel</button>
                        <button className="btn btn-primary" onClick={handleSaveTeam}>
                            {editingTeam ? 'Update' : 'Create'}
                        </button>
                    </>
                }
            >
                <div className="form-group">
                    <label className="form-label">Team Name <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                    <input
                        className="form-input"
                        value={teamForm.team_name}
                        onChange={e => setTeamForm({ ...teamForm, team_name: e.target.value })}
                        placeholder="Enter team name"
                        autoFocus
                    />
                </div>

                {!editingTeam && (
                    <div className="form-group">
                        <label className="form-label">Assign Team Leader (Optional)</label>
                        <select
                            className="form-select"
                            value={teamForm.assigned_leader_id}
                            onChange={e => setTeamForm({ ...teamForm, assigned_leader_id: e.target.value })}
                        >
                            <option value="">-- Set Myself as Leader --</option>
                            {eligibleLeaders.map(p => (
                                <option key={p.id} value={p.id}>{p.display_name || p.email}</option>
                            ))}
                        </select>
                        <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '4px' }}>
                            If you assign a player, they will become the owner and 'Team Leader' of this team.
                        </p>
                    </div>
                )}
                <div className="form-group">
                    <label className="form-label">Logo URL (optional)</label>
                    <input
                        className="form-input"
                        value={teamForm.logo_url}
                        onChange={e => setTeamForm({ ...teamForm, logo_url: e.target.value })}
                        placeholder="https://..."
                    />
                </div>
            </Modal>

            {/* ROSTER VIEW MODAL */}
            <Modal
                isOpen={!!selectedTeamForRoster}
                onClose={() => setSelectedTeamForRoster(null)}
                title={selectedTeamForRoster ? `${selectedTeamForRoster.team_name} Roster` : 'Roster'}
                footer={
                    <button className="btn btn-primary" onClick={() => setSelectedTeamForRoster(null)}>Done</button>
                }
            >
                <div className="roster-view" style={{ minHeight: '200px' }}>
                    {loadingPlayers ? (
                        <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="row" count={4} /></div>
                    ) : (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                            {/* 2. Show the Players */}
                            {players.length === 0 ? (
                                <div className="empty-state" style={{ padding: '20px 0' }}><p>No registered players found.</p></div>
                            ) : (
                                players.map(player => (
                                    <div key={player.id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px', background: 'rgba(255,255,255,0.03)', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.05)' }}>
                                        <div>
                                            <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{player.in_game_name || player.name}</div>
                                            {player.role === 'leader' && <div style={{ fontSize: '0.75rem', color: 'var(--neon-cyan)', marginTop: '4px' }}>TEAM LEADER</div>}
                                        </div>
                                        <button className="btn-icon" onClick={() => handleRemovePlayer(player)} title="Remove Player" style={{ color: 'var(--neon-red)' }}>
                                            <UserMinus size={16} />
                                        </button>
                                    </div>
                                ))
                            )}
                        </div>
                    )}

                    {/* 3. Add Player Form */}
                    <div style={{ marginTop: '20px', borderTop: '1px solid rgba(255,255,255,0.1)', paddingTop: '20px' }}>
                        {!showAddPlayer ? (
                            <button className="btn btn-secondary" onClick={() => setShowAddPlayer(true)} style={{ width: '100%' }}>
                                <Plus size={14} /> Manually Add Player
                            </button>
                        ) : (
                            <form onSubmit={handleAddPlayer} style={{ background: 'rgba(255,255,255,0.02)', padding: '16px', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.05)' }}>
                                <h4 style={{ margin: '0 0 12px 0', fontSize: '0.9rem', color: 'var(--text-secondary)' }}>Add New Player</h4>
                                <div className="form-group">
                                    <input
                                        className="form-input"
                                        placeholder="In-Game Name"
                                        value={newPlayerForm.in_game_name}
                                        onChange={e => setNewPlayerForm({ ...newPlayerForm, in_game_name: e.target.value })}
                                        autoFocus
                                    />
                                </div>
                                <div className="form-group" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                    <input
                                        type="checkbox"
                                        id="is_leader_admin"
                                        checked={newPlayerForm.is_leader}
                                        onChange={e => setNewPlayerForm({ ...newPlayerForm, is_leader: e.target.checked })}
                                    />
                                    <label htmlFor="is_leader_admin" style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Make Team Leader</label>
                                </div>
                                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                                    <button type="button" className="btn btn-secondary" onClick={() => setShowAddPlayer(false)} style={{ flex: 1 }}>Cancel</button>
                                    <button type="submit" className="btn btn-primary" style={{ flex: 1 }}>Add</button>
                                </div>
                            </form>
                        )}
                    </div>
                </div>
            </Modal>

        </div>
    );
}
