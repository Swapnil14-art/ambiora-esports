import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { Gamepad2, Users, Plus, ShieldAlert } from 'lucide-react';
import { useToast } from '../Toast';
import { useNavigate } from 'react-router-dom';

export default function Gatekeeper({ children }) {
    const { profile, setProfile, isViewer, isAdmin } = useAuth();
    const toast = useToast();
    const navigate = useNavigate();
    const [loading, setLoading] = useState(true);
    const [hasTeam, setHasTeam] = useState(false);
    const [availableGames, setAvailableGames] = useState([]);
    const [assigningLoading, setAssigningLoading] = useState(false);
    const [teamName, setTeamName] = useState('');
    const [showTeamCreation, setShowTeamCreation] = useState(false);

    useEffect(() => {
        // Viewers and Admins don't need to pass the Game Leader gate
        if (isViewer || isAdmin || !profile) {
            setLoading(false);
            return;
        }

        async function checkGates() {
            try {
                // 1. Check if they need to select a game
                if (!profile?.assigned_game_id) {
                    const { data } = await supabase.from('games').select('*').order('name');
                    setAvailableGames(data || []);
                    setLoading(false);
                    return;
                }

                // 2. Check if they have a team
                const { count } = await supabase
                    .from('teams')
                    .select('id', { count: 'exact', head: true })
                    .eq('created_by', profile.id)
                    .eq('game_id', profile.assigned_game_id);

                setHasTeam((count || 0) > 0);
            } catch (err) {
                console.error('Error checking gates:', err);
            } finally {
                setLoading(false);
            }
        }

        checkGates();
    }, [profile, isViewer]);

    const handleAssignGame = async (gameId) => {
        setAssigningLoading(true);
        try {
            const { supabaseAdmin } = await import('../../lib/supabase');
            if (!supabaseAdmin) throw new Error("Service role key missing.");

            const { error } = await supabaseAdmin
                .from('profiles')
                .update({ assigned_game_id: gameId })
                .eq('id', profile.id);

            if (error) throw error;

            if (setProfile) {
                setProfile({ ...profile, assigned_game_id: gameId });
            } else {
                window.location.reload();
            }

            setAssigningLoading(false);
        } catch (err) {
            console.error('Failed to assign game', err);
            toast.error('Failed to select game');
            setAssigningLoading(false);
        }
    };

    const handleCreateTeam = async (e) => {
        e.preventDefault();
        if (!teamName.trim()) {
            toast.error("Team name required");
            return;
        }
        setAssigningLoading(true);
        try {
            const { error } = await supabase.from('teams').insert({
                team_name: teamName.trim(),
                game_id: profile.assigned_game_id,
                created_by: profile.id
            });

            if (error) throw error;

            await supabase.from('audit_logs').insert({
                user_id: profile.id,
                action: `Mandatory setup: Created team ${teamName}`,
                details: { game_id: profile.assigned_game_id }
            });

            toast.success("Team created successfully!");
            setHasTeam(true);

            setTimeout(() => {
                navigate('/leader');
            }, 500);
        } catch (err) {
            console.error('Failed to create team', err);
            toast.error(err.message || 'Failed to create team');
            setAssigningLoading(false);
        }
    };

    const handleAssignRole = async (isPlayerDecision) => {
        setAssigningLoading(true);
        try {
            const { supabaseAdmin } = await import('../../lib/supabase');
            if (!supabaseAdmin) throw new Error("Service role key missing.");

            // Setting the actual role now, not just is_player boolean
            const { error } = await supabaseAdmin
                .from('profiles')
                .update({ role: 'player' })
                .eq('id', profile.id);

            if (error) throw error;

            if (setProfile) {
                setProfile({ ...profile, role: 'player' });
            }

            toast.success('Joined as Player!');
            navigate('/player');
        } catch (err) {
            console.error('Failed to assign role', err);
            toast.error('Failed to update role');
        } finally {
            setAssigningLoading(false);
        }
    };

    if (loading) {
        return (
            <div className="loading-screen" style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div className="loader"></div>
            </div>
        );
    }

    // Viewers, Admins, and full Players bypass all this
    if (isViewer || isAdmin || profile?.role === 'player' || !profile) {
        return children;
    }

    // GATE 1: MUST SELECT A GAME
    if (!profile.assigned_game_id) {
        return (
            <div className="app-layout">
                <main className="main-content" style={{ marginLeft: 0, width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
                    <div className="card" style={{ maxWidth: '600px', width: '100%', textAlign: 'center', padding: 'clamp(20px, 5vw, 40px)', boxSizing: 'border-box' }}>
                        <Gamepad2 size={48} style={{ color: 'var(--neon-purple)', margin: '0 auto 20px', display: 'block' }} />
                        <h2 className="text-gradient" style={{ fontSize: 'clamp(1.4rem, 5vw, 2rem)', marginBottom: '10px' }}>Step 1: Game Selection</h2>
                        <p style={{ color: 'var(--text-secondary)', marginBottom: '30px', lineHeight: '1.6', fontSize: 'clamp(0.85rem, 2.5vw, 1rem)' }}>
                            Welcome to the tournament operations center. To proceed, you must choose the game bracket you are managing. This action is final.
                        </p>

                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 140px), 1fr))', gap: '12px' }}>
                            {availableGames.map(game => (
                                <button
                                    key={game.id}
                                    className="btn btn-secondary"
                                    style={{ padding: '16px 12px', fontSize: '1rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', minWidth: 0 }}
                                    onClick={() => handleAssignGame(game.id)}
                                    disabled={assigningLoading}
                                >
                                    {game.name}
                                </button>
                            ))}
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    // GATE 1.5: MUST SELECT ROLE (Player or Team Leader)
    // Technically if they are here, they are still 'game_leader'. So we don't need !profile.is_player.
    // If they have no team, they might just be a player who signed up default.
    if (profile.role === 'game_leader' && !hasTeam && !showTeamCreation) {
        return (
            <div className="app-layout">
                <main className="main-content" style={{ marginLeft: 0, width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
                    <div className="card" style={{ maxWidth: '600px', width: '100%', textAlign: 'center', padding: 'clamp(20px, 5vw, 40px)', boxSizing: 'border-box' }}>
                        <Users size={48} style={{ color: 'var(--neon-cyan)', margin: '0 auto 20px', display: 'block' }} />
                        <h2 className="text-gradient" style={{ fontSize: 'clamp(1.4rem, 5vw, 2rem)', marginBottom: '10px' }}>Step 2: Account Role</h2>
                        <p style={{ color: 'var(--text-secondary)', marginBottom: '30px', lineHeight: '1.6', fontSize: 'clamp(0.85rem, 2.5vw, 1rem)' }}>
                            Please select your role for this tournament. Are you joining an existing team as a player, or are you registering a new team as a Team Leader?
                        </p>

                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 200px), 1fr))', gap: '12px' }}>
                            <button
                                className="btn btn-secondary"
                                style={{ padding: '16px 12px', fontSize: '1rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', minWidth: 0 }}
                                onClick={() => handleAssignRole(true)}
                                disabled={assigningLoading}
                            >
                                <Users size={24} />
                                <span>I am a Player</span>
                                <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>I want to join a team</span>
                            </button>
                            <button
                                className="btn btn-primary"
                                style={{ padding: '16px 12px', fontSize: '1rem', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', minWidth: 0 }}
                                onClick={() => setShowTeamCreation(true)}
                                disabled={assigningLoading}
                            >
                                <ShieldAlert size={24} />
                                <span>I am a Team Leader</span>
                                <span style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.7)' }}>I want to register a team</span>
                            </button>
                        </div>
                    </div>
                </main>
            </div>
        );
    }

    // GATE 2: MUST CREATE A TEAM (Only reached if they clicked Team Leader OR they are an old leader without a team)
    if (!hasTeam) {
        return (
            <div className="app-layout">
                <main className="main-content" style={{ marginLeft: 0, width: '100%', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px' }}>
                    <div className="card" style={{ maxWidth: '600px', width: '100%', textAlign: 'center', padding: 'clamp(20px, 5vw, 40px)', boxSizing: 'border-box' }}>
                        <Users size={48} style={{ color: 'var(--neon-cyan)', margin: '0 auto 20px', display: 'block' }} />
                        <h2 className="text-gradient" style={{ fontSize: 'clamp(1.4rem, 5vw, 2rem)', marginBottom: '10px' }}>Step 2: Initialize Roster</h2>
                        <p style={{ color: 'var(--text-secondary)', marginBottom: '30px', lineHeight: '1.6', fontSize: 'clamp(0.85rem, 2.5vw, 1rem)' }}>
                            You have successfully claimed your game. Before accessing the control panel operations, you must create at least one active team to initialize the bracket.
                        </p>

                        <form onSubmit={handleCreateTeam} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                            <div className="form-group" style={{ textAlign: 'left' }}>
                                <label className="form-label">Team Name</label>
                                <input
                                    className="form-input"
                                    value={teamName}
                                    onChange={e => setTeamName(e.target.value)}
                                    placeholder="Enter official team name..."
                                    style={{ padding: '14px', fontSize: '1rem' }}
                                    autoFocus
                                />
                            </div>
                            <button
                                type="submit"
                                className="btn btn-primary"
                                style={{ padding: '14px', fontSize: '1rem', display: 'flex', justifyContent: 'center', gap: '10px' }}
                                disabled={assigningLoading}
                            >
                                <Plus size={20} /> Deploy Team
                            </button>
                        </form>
                    </div>
                </main>
            </div>
        );
    }

    // All gates passed, render standard application children (AppLayout)
    return children;
}
