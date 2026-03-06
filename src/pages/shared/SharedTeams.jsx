import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase, supabaseAdmin } from '../../lib/supabase';
import { fetchWithCache, hasValidCache, invalidateCache } from '../../lib/cache';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2 } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function SharedTeams() {
    const { profile, isPlayer, isAdmin, refreshProfile } = useAuth();
    const toast = useToast();
    const navigate = useNavigate();

    const [teams, setTeams] = useState([]);
    const [games, setGames] = useState([]);
    const [loading, setLoading] = useState(true);

    // Modal State
    const [modalOpen, setModalOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [createStep, setCreateStep] = useState(1); // 1 = Select Game, 'blocked' = Validation Failed, 2 = Enter Details
    const [verifying, setVerifying] = useState(false);
    const [form, setForm] = useState({ team_name: '', game_id: '', assigned_leader_id: '' });
    const [eligibleLeaders, setEligibleLeaders] = useState([]);

    // The user's assigned game (if they are a leader)
    const assignedGameId = profile?.assigned_game_id;

    useEffect(() => {
        fetchData();
    }, [profile]);

    const fetchData = async () => {
        const cacheKey = `shared_teams_${profile.id}`;

        if (!hasValidCache(cacheKey) || !hasValidCache('admin_games')) {
            setLoading(true);
        }

        try {
            // 1. Fetch all games for the dropdown
            const gamesData = await fetchWithCache('admin_games', async () => {
                const { data } = await supabase.from('games').select('*').order('name');
                return data || [];
            });
            setGames(gamesData);

            // Fetch Teams where the user is ANY kind of member (leader or member)
            const teamMapArray = await fetchWithCache(cacheKey, async () => {
                const { data: memberRows, error: err } = await supabase
                    .from('players')
                    .select('role, teams(*, games(name), players(id))')
                    .eq('user_id', profile.id);

                if (err) throw err;

                const tMap = new Map();
                (memberRows || []).forEach(row => {
                    if (row.teams) {
                        tMap.set(row.teams.id, { ...row.teams, is_owner: row.role === 'leader' });
                    }
                });

                // Add teams created by them if they somehow aren't in players (edge case / legacy admin)
                if (isAdmin && profile.role === 'admin') {
                    const { data: ownedTeams } = await supabase
                        .from('teams')
                        .select('*, games(name), players(id)')
                        .eq('created_by', profile.id);
                    (ownedTeams || []).forEach(t => {
                        if (!tMap.has(t.id)) tMap.set(t.id, { ...t, is_owner: true });
                    });
                }

                return Array.from(tMap.values()).sort((a, b) => a.team_name.localeCompare(b.team_name));
            });

            setTeams(teamMapArray);
        } catch (error) {
            console.error("Error fetching shared teams:", error);
            toast.error("Failed to load teams");
        }
        setLoading(false);
    };

    const openCreate = async () => {
        setEditing(null);
        setCreateStep(1); // ALWAYS step 1 for new
        setForm({
            team_name: '',
            game_id: '', // Do NOT pre-fill, force explicit selection
            assigned_leader_id: ''
        });

        // Fetch eligible players if Admin (everyone except admins)
        if (isAdmin) {
            const { data } = await supabase
                .from('profiles')
                .select('id, display_name, email, role')
                .neq('role', 'admin');
            setEligibleLeaders(data || []);
        }

        setModalOpen(true);
    };

    const openEdit = (team) => {
        setEditing(team);
        setCreateStep(2); // Skip straight to the form since it's an edit
        setForm({
            team_name: team.team_name,
            game_id: team.game_id
        });
        setModalOpen(true);
    };

    const handleNextStep = async () => {
        if (!form.game_id) {
            toast.error('Please select a game first');
            return;
        }
        setVerifying(true);

        try {
            // Check: Is user a member of ANY team in this game? (Leader or Member)
            const { count: memberCount, error: memberErr } = await supabase
                .from('players')
                .select('id, teams!inner(game_id)', { count: 'exact', head: true })
                .eq('user_id', profile.id)
                .eq('teams.game_id', form.game_id);

            if (memberErr) throw memberErr;

            if (memberCount > 0) {
                // REJECTION PATH
                setCreateStep('blocked');
            } else {
                // ALLOWED PATH
                setCreateStep(2);
            }
        } catch (error) {
            console.error('Validation error:', error);
            toast.error('Failed to verify game association status');
        } finally {
            setVerifying(false);
        }
    };

    const handleSave = async () => {
        if (!form.team_name.trim()) {
            toast.error('Team name is required');
            return;
        }
        if (!form.game_id) {
            toast.error('Please select a game');
            return;
        }

        if (editing) {
            // Updating existing team
            const { error } = await supabase
                .from('teams')
                .update({ team_name: form.team_name.trim(), game_id: form.game_id })
                .eq('id', editing.id);

            if (error) {
                toast.error(error.message);
                return;
            }
            invalidateCache(`shared_teams_${profile.id}`);
            invalidateCache('admin_teams_count');
            invalidateCache(`admin_teams_${form.game_id}`);
            toast.success('Team updated');

        } else {
            // Determine who the creator/leader is. If Admin and explicit selection, use that.
            const designatedCreatorId = (isAdmin && form.assigned_leader_id) ? form.assigned_leader_id : profile.id;

            // Creating a new team
            const { data: newTeam, error } = await supabase
                .from('teams')
                .insert({
                    team_name: form.team_name.trim(),
                    game_id: form.game_id,
                    created_by: designatedCreatorId
                }).select('id').single();

            if (error) {
                if (error.message.includes('User is already a member')) {
                    toast.error('You are already associated with a team in this game.');
                } else {
                    toast.error(error.message);
                }
                return;
            }

            // Immediately insert the creator as the 'leader' in the players table
            const leaderProfile = (isAdmin && form.assigned_leader_id)
                ? eligibleLeaders.find(p => p.id === designatedCreatorId) || profile
                : profile;

            const ign = leaderProfile?.display_name || leaderProfile?.email?.split('@')[0] || 'Captain';

            const { error: rosterErr } = await supabase
                .from('players')
                .insert({
                    team_id: newTeam.id,
                    user_id: designatedCreatorId,
                    name: leaderProfile?.display_name || leaderProfile?.email || 'Leader',
                    in_game_name: ign,
                    role: 'leader'
                });

            if (rosterErr) {
                console.error("Failed to add leader to roster:", rosterErr);
                toast.error("Team created but failed to assign leadership role. Please contact Admin.");
                return;
            }

            invalidateCache(`shared_teams_${profile.id}`);
            invalidateCache('admin_teams_count');
            invalidateCache(`admin_teams_${form.game_id}`);
            toast.success('Team created successfully!');

            // Upgrade profile role so they can still see the /leader dashboard
            const isSelfUpgrade = designatedCreatorId === profile.id;

            if ((isSelfUpgrade && isPlayer) || (!isSelfUpgrade && isAdmin)) {
                if (!supabaseAdmin) {
                    console.error("Missing supabaseAdmin! Cannot upgrade role.");
                } else {
                    const { error: roleErr } = await supabaseAdmin
                        .from('profiles')
                        .update({ role: 'game_leader', assigned_game_id: form.game_id })
                        .eq('id', designatedCreatorId);

                    if (!roleErr) {
                        if (isSelfUpgrade) {
                            await refreshProfile();
                            navigate('/leader');
                        }
                    } else {
                        console.error("Role upgrade failed:", roleErr);
                    }
                }
            }
        }

        setModalOpen(false);
        fetchData();
    };

    const handleDelete = async (team) => {
        if (!window.confirm(`Delete "${team.team_name}"?`)) return;
        const { error } = await supabase
            .from('teams')
            .delete()
            .eq('id', team.id);

        if (error) {
            toast.error(error.message);
            return;
        }
        invalidateCache(`shared_teams_${profile.id}`);
        invalidateCache('admin_teams_count');
        invalidateCache(`admin_teams_${team.game_id}`);
        toast.success('Team deleted');
        fetchData();
    };

    return (
        <div>
            <div className="page-header">
                <h1>My Teams</h1>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                ) : teams.length === 0 ? (
                    <div className="empty-state">
                        <p>No teams found.</p>
                    </div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Team Name</th>
                                    <th>Game</th>
                                    <th>Players</th>
                                    <th>My Role</th>
                                </tr>
                            </thead>
                            <tbody>
                                {teams.map(t => (
                                    <tr key={t.id}>
                                        <td style={{ fontWeight: 600 }}>{t.team_name}</td>
                                        <td><span className="badge badge-upcoming">{t.games?.name}</span></td>
                                        <td style={{ color: 'var(--neon-cyan)' }}>{t.players?.length || 0}</td>
                                        <td>
                                            {t.is_owner ? (
                                                <span style={{ color: 'var(--neon-purple)', fontSize: '0.85rem' }}>Creator</span>
                                            ) : (
                                                <span style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Member</span>
                                            )}
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
