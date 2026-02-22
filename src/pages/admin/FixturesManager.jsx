import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { CalendarSync, Plus, Trash2, ShieldAlert } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';
import { RULEBOOKS, generateRulebookFixtures } from '../../lib/fixtureGenerator';

export default function FixturesManager() {
    const { profile } = useAuth();
    const toast = useToast();

    const [games, setGames] = useState([]);
    const [selectedGame, setSelectedGame] = useState(null);
    const [fixtures, setFixtures] = useState([]);
    const [loading, setLoading] = useState(true);

    // Modal State
    const [modalOpen, setModalOpen] = useState(false);
    const [isGenerating, setIsGenerating] = useState(false);

    // FIFA Mode Toggle (Singles vs Doubles)
    const [fifaMode, setFifaMode] = useState('fifa25_singles');

    // Derived Rulebook info
    const rulebookSlug = selectedGame?.slug === 'fifa25' ? fifaMode : selectedGame?.slug;
    const currentRulebook = RULEBOOKS[rulebookSlug];

    // Generator Form State
    const [form, setForm] = useState({
        phaseName: ''
    });

    useEffect(() => {
        fetchGames();
    }, []);

    useEffect(() => {
        if (selectedGame) {
            fetchFixtures(selectedGame.id);
            fetchTeams(selectedGame.id);
        }
    }, [selectedGame]);

    const fetchGames = async () => {
        const { data, error } = await supabase.from('games').select('*').order('name');
        if (error) {
            toast.error('Failed to load games');
            return;
        }
        setGames(data || []);
        if (data?.length > 0) setSelectedGame(data[0]);
    };

    const fetchFixtures = async (gameId) => {
        setLoading(true);
        // Only fetch 'upcoming' matches for the fixtures view, though any match without results fits
        const { data, error } = await supabase
            .from('matches')
            .select('*, match_teams(team_id, teams(team_name))')
            .eq('game_id', gameId)
            .order('round')
            .order('match_number');

        if (error) {
            toast.error('Failed to load fixtures');
        } else {
            setFixtures(data || []);
        }
        setLoading(false);
    };

    const fetchTeams = async (gameId) => {
        const { data } = await supabase
            .from('teams')
            .select('id, team_name')
            .eq('game_id', gameId)
            .order('team_name');
        setAvailableTeams(data || []);
    };

    const openGenerator = () => {
        setForm({
            phaseName: currentRulebook?.phases[0] || ''
        });
        setModalOpen(true);
    };

    const handleGenerate = async () => {
        if (!form.phaseName) {
            toast.error('Phase/Round name is required');
            return;
        }

        setIsGenerating(true);

        try {
            // 1. Calculate the deterministic match fixtures via Rulebook Engine
            const matchupsPayload = await generateRulebookFixtures(
                rulebookSlug,
                selectedGame.id,
                form.phaseName
            );

            // 2. Call the Atomic Supabase RPC Function (Phase 13/14)
            const { data, error } = await supabase.rpc('create_fixtures_batch', {
                p_game_id: selectedGame.id,
                p_round_name: form.phaseName,
                p_scheduled_at: new Date().toISOString(),
                p_matchups: matchupsPayload
            });

            if (error) throw error;

            toast.success(`Successfully generated ${data.inserted_count} fixtures for ${form.phaseName}!`);
            setModalOpen(false);
            fetchFixtures(selectedGame.id);

        } catch (error) {
            console.error('Fixture Generation Error:', error);
            toast.error(error.message || 'Generation failed. transaction safely aborted.');
        } finally {
            setIsGenerating(false);
        }
    };

    // Group fixtures by round
    const groupedFixtures = fixtures.reduce((acc, match) => {
        if (!acc[match.round]) acc[match.round] = [];
        acc[match.round].push(match);
        return acc;
    }, {});

    return (
        <div>
            <div className="page-header">
                <div>
                    <h1 style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                        <CalendarSync size={24} style={{ color: 'var(--neon-purple)' }} />
                        Tournament Fixtures
                    </h1>
                    <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginTop: '4px' }}>
                        Admin Module: Atomically generate brackets and matches safely.
                    </p>
                </div>
            </div>

            <div className="tabs">
                {games.map(g => (
                    <button
                        key={g.id}
                        className={`tab ${selectedGame?.id === g.id ? 'active' : ''}`}
                        onClick={() => setSelectedGame(g)}
                    >
                        {g.name}
                    </button>
                ))}
            </div>

            {selectedGame && (
                <>
                    <div style={{ marginBottom: '20px', display: 'flex', justifyContent: 'flex-end' }}>
                        <button className="btn btn-primary" onClick={openGenerator}>
                            <Plus size={16} /> Create Fixture For {selectedGame.name}
                        </button>
                    </div>

                    {loading ? (
                        <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={5} /></div>
                    ) : Object.keys(groupedFixtures).length === 0 ? (
                        <div className="empty-state">
                            <CalendarSync size={48} style={{ color: 'var(--border-strong)', marginBottom: '16px' }} />
                            <h3>No Fixtures Generated</h3>
                            <p style={{ maxWidth: '400px', margin: '0 auto' }}>
                                No matchups have been scheduled for <strong>{selectedGame.name}</strong> yet.
                                Click "Create Fixture" above to build the bracket atomically.
                            </p>
                        </div>
                    ) : (
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
                            {Object.entries(groupedFixtures).map(([roundName, roundMatches]) => (
                                <div key={roundName} className="card" style={{ padding: '0' }}>
                                    <div style={{
                                        padding: '16px 24px',
                                        borderBottom: '1px solid var(--border)',
                                        background: 'rgba(255,255,255,0.02)',
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'space-between'
                                    }}>
                                        <h3 style={{ margin: 0, color: 'var(--neon-cyan)' }}>{roundName}</h3>
                                        <span className="badge badge-upcoming">{roundMatches.length} Matches</span>
                                    </div>
                                    <div className="table-responsive">
                                        <table className="data-table">
                                            <thead>
                                                <tr>
                                                    <th style={{ width: '80px' }}>Match #</th>
                                                    <th>Matchup</th>
                                                    <th>Format</th>
                                                    <th>Status</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                {roundMatches.map(m => (
                                                    <tr key={m.id}>
                                                        <td style={{ color: 'var(--text-muted)' }}>#{m.match_number}</td>
                                                        <td style={{ fontWeight: 600 }}>
                                                            {m.match_teams?.map(mt => mt.teams?.team_name).join(' vs ') || 'TBD'}
                                                        </td>
                                                        <td style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                                                            {m.best_of > 1 ? `BO${m.best_of}` : m.match_type}
                                                        </td>
                                                        <td>
                                                            <span className={`badge badge-${m.status}`}>{m.status}</span>
                                                        </td>
                                                    </tr>
                                                ))}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </>
            )}

            <Modal
                isOpen={modalOpen}
                onClose={() => setModalOpen(false)}
                title={`Generate Rulebook Fixtures`}
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
                        <button
                            className="btn btn-primary"
                            onClick={handleGenerate}
                            disabled={isGenerating || !currentRulebook}
                        >
                            {isGenerating ? 'Computing Safely...' : 'Generate Deterministically'}
                        </button>
                    </>
                }
            >
                <div style={{ background: 'rgba(255, 0, 51, 0.05)', border: '1px solid rgba(255,0,51,0.2)', padding: '12px', borderRadius: '8px', marginBottom: '20px', display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
                    <ShieldAlert size={20} style={{ color: 'var(--neon-red)', flexShrink: 0 }} />
                    <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                        <strong>Strict Automation Enabled:</strong> Manual match combinations have been completely disabled. The bracket will be generated automatically and perfectly according to the global rulebook.
                    </p>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginBottom: '10px' }}>
                    {selectedGame?.slug === 'fifa25' && (
                        <div className="form-group" style={{ marginBottom: 0 }}>
                            <label className="form-label">FIFA Tournament Type</label>
                            <select
                                className="form-select"
                                value={fifaMode}
                                onChange={e => {
                                    setFifaMode(e.target.value);
                                    setForm({ phaseName: RULEBOOKS[e.target.value]?.phases[0] });
                                }}
                            >
                                <option value="fifa25_singles">FIFA Singles (32 Player Knockout)</option>
                                <option value="fifa25_doubles">FIFA Doubles (20 Team Knockout + Byes)</option>
                            </select>
                        </div>
                    )}

                    {currentRulebook ? (
                        <div className="form-group" style={{ marginBottom: 0 }}>
                            <label className="form-label">Tournament Phase</label>
                            <select
                                className="form-select"
                                value={form.phaseName}
                                onChange={e => setForm({ phaseName: e.target.value })}
                            >
                                {currentRulebook.phases.map(p => (
                                    <option key={p} value={p}>{p}</option>
                                ))}
                            </select>
                        </div>
                    ) : (
                        <div className="empty-state">No rulebook implemented for this game yet.</div>
                    )}
                </div>
            </Modal>
        </div>
    );
}
