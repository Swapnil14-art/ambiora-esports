import { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { supabase } from '../../lib/supabase';
import { fetchWithCache, invalidateCache, hasValidCache } from '../../lib/cache';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import Modal from '../../components/Modal';
import { Plus, Pencil, Trash2, Lock, Unlock, Play, CheckCircle, Search } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

const STATUS_OPTIONS = ['upcoming', 'live', 'completed'];

export default function MatchesManager() {
    const { profile } = useAuth();
    const location = useLocation();
    const toast = useToast();
    const [matches, setMatches] = useState([]);
    const [games, setGames] = useState([]);
    const [teams, setTeams] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filterGame, setFilterGame] = useState(location.state?.defaultGameId || '');
    const [filterStatus, setFilterStatus] = useState(location.state?.defaultStatus || '');
    const [modalOpen, setModalOpen] = useState(false);
    const [resultModalOpen, setResultModalOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [selectedMatch, setSelectedMatch] = useState(null);
    const [matchTeams, setMatchTeams] = useState([]);
    const [results, setResults] = useState([]);
    const [form, setForm] = useState({
        game_id: '', round: 'Round 1', match_number: 1, status: 'upcoming',
        match_type: 'standard', best_of: 1, scheduled_at: '', team_ids: [],
    });

    useEffect(() => {
        if (location.state?.defaultGameId || location.state?.defaultStatus) {
            // clear state so it doesn't linger on subsequent navigations via sidebar
            window.history.replaceState({}, '');
        }
    }, [location.state]);

    useEffect(() => {
        fetchGames();
        fetchAllTeams();
    }, []);

    useEffect(() => {
        fetchMatches();
    }, [filterGame, filterStatus]);

    const fetchGames = async () => {
        const data = await fetchWithCache('admin_games', async () => {
            const res = await supabase.from('games').select('*').order('name');
            return res.data;
        });
        setGames(data || []);
    };

    const fetchAllTeams = async () => {
        const data = await fetchWithCache('admin_all_teams', async () => {
            const res = await supabase.from('teams').select('*, games(name)').order('team_name');
            return res.data;
        });
        setTeams(data || []);
    };

    const fetchMatches = async () => {
        const cacheKey = `admin_matches_${filterGame || 'all'}_${filterStatus || 'all'}`;

        if (!hasValidCache(cacheKey)) {
            setLoading(true);
        }

        const data = await fetchWithCache(cacheKey, async () => {
            let query = supabase.from('matches').select('*, games(name, slug), match_teams(team_id, teams(team_name))').order('created_at', { ascending: false });
            if (filterGame) query = query.eq('game_id', filterGame);
            if (filterStatus) query = query.eq('status', filterStatus);
            const res = await query;
            if (res.error) console.error(res.error);
            return res.data;
        });

        setMatches(data || []);
        setLoading(false);
    };

    const openCreate = () => {
        setEditing(null);
        setForm({
            game_id: games[0]?.id || '', round: 'Round 1', match_number: 1,
            status: 'upcoming', match_type: 'standard', best_of: 1,
            scheduled_at: '', team_ids: [],
        });
        setModalOpen(true);
    };

    const openEdit = (match) => {
        setEditing(match);
        const teamIds = match.match_teams?.map(mt => mt.team_id) || [];
        setForm({
            game_id: match.game_id,
            round: match.round,
            match_number: match.match_number || 1,
            status: match.status,
            match_type: match.match_type || 'standard',
            best_of: match.best_of || 1,
            scheduled_at: match.scheduled_at ? new Date(match.scheduled_at).toISOString().slice(0, 16) : '',
            venue: match.venue || '',
            team_ids: teamIds,
        });
        setModalOpen(true);
    };

    const handleSave = async () => {
        if (!isFormValid()) { toast.error('Check match configuration errors'); return; }

        const matchPayload = {
            game_id: form.game_id,
            round: form.round,
            match_number: form.match_number,
            status: form.status,
            match_type: form.match_type,
            best_of: form.best_of,
            scheduled_at: form.scheduled_at || null,
            venue: form.venue || null,
        };

        if (editing) {
            const { error } = await supabase.from('matches').update(matchPayload).eq('id', editing.id);
            if (error) { toast.error(error.message); return; }

            // Update match teams
            await supabase.from('match_teams').delete().eq('match_id', editing.id);
            if (form.team_ids.length > 0) {
                await supabase.from('match_teams').insert(form.team_ids.map(tid => ({ match_id: editing.id, team_id: tid })));
            }

            await supabase.from('audit_logs').insert({
                user_id: profile.id,
                action: `Updated match: ${form.round} #${form.match_number}`,
                details: { match_id: editing.id },
            });
            toast.success('Match updated');
        } else {
            const { data: newMatch, error } = await supabase.from('matches').insert(matchPayload).select().single();
            if (error) { toast.error(error.message); return; }

            if (form.team_ids.length > 0) {
                await supabase.from('match_teams').insert(form.team_ids.map(tid => ({ match_id: newMatch.id, team_id: tid })));
            }

            await supabase.from('audit_logs').insert({
                user_id: profile.id,
                action: `Created match: ${form.round} #${form.match_number}`,
                details: { match_id: newMatch.id, game_id: form.game_id },
            });
            toast.success('Match created');
        }

        setModalOpen(false);
        invalidateCache(k => typeof k === 'string' && k.startsWith('admin_matches_'));
        invalidateCache('admin_games_stats');
        fetchMatches();
    };

    const handleDelete = async (match) => {
        if (!window.confirm('Delete this match?')) return;
        await supabase.from('matches').delete().eq('id', match.id);
        await supabase.from('audit_logs').insert({
            user_id: profile.id,
            action: `Deleted match: ${match.round} #${match.match_number}`,
            details: { match_id: match.id },
        });
        toast.success('Match deleted');
        invalidateCache(k => typeof k === 'string' && k.startsWith('admin_matches_'));
        invalidateCache('admin_games_stats');
        fetchMatches();
    };

    const toggleLock = async (match) => {
        await supabase.from('matches').update({ locked: !match.locked }).eq('id', match.id);
        toast.info(match.locked ? 'Match unlocked' : 'Match locked');
        invalidateCache(k => typeof k === 'string' && k.startsWith('admin_matches_'));
        fetchMatches();
    };

    const openResults = async (match) => {
        setSelectedMatch(match);
        const { data: mt } = await supabase.from('match_teams').select('team_id, teams(team_name)').eq('match_id', match.id);
        setMatchTeams(mt || []);

        const { data: res } = await supabase.from('match_results').select('*').eq('match_id', match.id);
        const existingResults = res || [];

        // Build results array from match teams
        const resultsArr = (mt || []).map(t => {
            const existing = existingResults.find(r => r.team_id === t.team_id);
            return {
                team_id: t.team_id,
                team_name: t.teams?.team_name || '—',
                score: existing?.score || 0,
                placement: existing?.placement || null,
                kills: existing?.kills || 0,
                deaths: existing?.deaths || 0,
                time_ms: existing?.time_ms || null,
                id: existing?.id || null,
            };
        });

        setResults(resultsArr);
        setResultModalOpen(true);
    };

    const updateResult = (idx, field, value) => {
        setResults(prev => prev.map((r, i) => i === idx ? { ...r, [field]: value } : r));
    };

    const saveResults = async () => {
        if (!selectedMatch) return;

        for (const r of results) {
            const payload = {
                match_id: selectedMatch.id,
                team_id: r.team_id,
                score: parseInt(r.score) || 0,
                placement: r.placement ? parseInt(r.placement) : null,
                kills: parseInt(r.kills) || 0,
                deaths: parseInt(r.deaths) || 0,
                time_ms: r.time_ms ? parseInt(r.time_ms) : null,
            };

            if (r.id) {
                await supabase.from('match_results').update(payload).eq('id', r.id);
            } else {
                await supabase.from('match_results').insert(payload);
            }
        }

        await supabase.from('audit_logs').insert({
            user_id: profile.id,
            action: `Updated results for: ${selectedMatch.round} #${selectedMatch.match_number}`,
            details: { match_id: selectedMatch.id },
        });

        toast.success('Results saved');
        invalidateCache(k => typeof k === 'string' && k.startsWith('admin_matches_'));
        setResultModalOpen(false);
    };

    const gameSlug = games.find(g => g.id === form.game_id)?.slug;
    const gameTeams = teams.filter(t => t.game_id === form.game_id && t.status !== 'disqualified');

    // Validation Rules
    const isMultiTeamGame = gameSlug === 'bgmi' || gameSlug === 'f1';
    const isTeamCountValid = () => {
        if (!gameSlug) return false;
        const count = form.team_ids.length;
        if (isMultiTeamGame) return count >= 1;
        return count === 2; // Valorant, FIFA require exactly 2
    };

    const isFormValid = () => {
        if (!form.game_id) return false;
        if (!form.match_type.trim() || !form.scheduled_at) return false;
        return isTeamCountValid();
    };

    const toggleTeam = (teamId) => {
        setForm(prev => {
            const isSelected = prev.team_ids.includes(teamId);

            // If we are deselecting, always allow
            if (isSelected) {
                return { ...prev, team_ids: prev.team_ids.filter(id => id !== teamId) };
            }

            // If we are selecting, check constraints
            if (!isMultiTeamGame && prev.team_ids.length >= 2) {
                toast.error(`Maximum 2 teams allowed for ${gameSlug?.toUpperCase() || 'this game'}`);
                return prev; // Do not update
            }

            return { ...prev, team_ids: [...prev.team_ids, teamId] };
        });
    };

    return (
        <div>
            <div className="page-header">
                <h1>Matches</h1>
                <div className="page-header-actions">
                    <button className="btn btn-primary" onClick={openCreate}><Plus size={14} /> Create Match</button>
                </div>
            </div>

            <div className="filters-bar">
                <select className="form-select" value={filterGame} onChange={e => setFilterGame(e.target.value)}>
                    <option value="">All Games</option>
                    {games.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                </select>
                <select className="form-select" value={filterStatus} onChange={e => setFilterStatus(e.target.value)}>
                    <option value="">All Statuses</option>
                    {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s.charAt(0).toUpperCase() + s.slice(1)}</option>)}
                </select>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-md)' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="card" count={5} /></div>
                ) : matches.length === 0 ? (
                    <div className="empty-state"><p>No matches found</p></div>
                ) : (
                    matches.map(m => {
                        const teams = m.match_teams?.map(mt => mt.teams?.team_name) || [];
                        const isMultiplayer = teams.length > 2;

                        return (
                            <div key={m.id} className="broadcast-panel clip-angle" style={{ padding: 'var(--space-sm) var(--space-md)', display: 'flex', alignItems: 'center', gap: 'var(--space-md)' }}>
                                {/* Match Info */}
                                <div style={{ width: '180px', flexShrink: 0 }}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px' }}>
                                        <span className={`badge badge-${m.status}`} style={{ fontSize: '0.65rem' }}>{m.status}</span>
                                        <span style={{ fontSize: '0.75rem', color: 'var(--neon-purple)', fontWeight: 700, textTransform: 'uppercase' }}>{m.games?.name}</span>
                                    </div>
                                    <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                                        {m.round} - Match {m.match_number}
                                        {m.locked && <Lock size={12} style={{ color: 'var(--neon-red)', marginLeft: 6, verticalAlign: '-2px' }} />}
                                    </div>
                                </div>

                                {/* Teams Section */}
                                <div style={{ flexGrow: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,0.2)', padding: 'var(--space-sm)', borderRadius: '4px' }}>
                                    {isMultiplayer ? (
                                        <div style={{ fontWeight: 800, fontSize: '1.2rem', fontFamily: 'var(--font-display)', color: 'var(--neon-cyan)', letterSpacing: '1px' }}>
                                            {teams.length} Team Battle Royale
                                        </div>
                                    ) : (
                                        <>
                                            <div style={{ flex: 1, textAlign: 'right', fontWeight: 800, fontSize: '1.2rem', fontFamily: 'var(--font-display)', color: '#fff', textTransform: 'uppercase' }}>
                                                {teams[0] || 'TBD'}
                                            </div>
                                            <div className="vs-separator" style={{ margin: '0 var(--space-lg)' }}>VS</div>
                                            <div style={{ flex: 1, textAlign: 'left', fontWeight: 800, fontSize: '1.2rem', fontFamily: 'var(--font-display)', color: '#fff', textTransform: 'uppercase' }}>
                                                {teams[1] || 'TBD'}
                                            </div>
                                        </>
                                    )}
                                </div>

                                {/* Actions */}
                                <div className="cell-actions" style={{ paddingLeft: 'var(--space-md)', borderLeft: '1px solid var(--border-primary)' }}>
                                    <button className="btn btn-sm btn-secondary" onClick={() => openResults(m)} style={{ borderRadius: '0', clipPath: 'polygon(8px 0, 100% 0, 100% 100%, 0 100%, 0 8px)' }}>Results</button>
                                    <button className="btn-icon" onClick={() => toggleLock(m)} title={m.locked ? 'Unlock' : 'Lock'}>
                                        {m.locked ? <Unlock size={16} /> : <Lock size={16} />}
                                    </button>
                                    <button className="btn-icon" onClick={() => openEdit(m)}><Pencil size={16} /></button>
                                    <button className="btn-icon" onClick={() => handleDelete(m)} style={{ color: 'var(--neon-red)' }}><Trash2 size={16} /></button>
                                </div>
                            </div>
                        );
                    })
                )}
            </div>

            {/* Create/Edit Match Modal (WIZARD) */}
            <Modal
                isOpen={modalOpen}
                onClose={() => setModalOpen(false)}
                title={editing ? 'Edit Match Widget' : 'Match Creation Wizard'}
                size="lg"
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setModalOpen(false)}>Cancel</button>
                        <button
                            className="btn btn-primary"
                            onClick={handleSave}
                            disabled={!isFormValid()}
                            style={{ opacity: isFormValid() ? 1 : 0.5, cursor: isFormValid() ? 'pointer' : 'not-allowed' }}
                        >
                            {editing ? 'Update Match' : 'Deploy Match'}
                        </button>
                    </>
                }
            >
                <div style={{ marginBottom: '24px', paddingBottom: '16px', borderBottom: '1px solid var(--border-primary)' }}>
                    <span style={{ fontSize: '0.8rem', color: 'var(--neon-cyan)', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 600, display: 'block', marginBottom: '8px' }}>Step 1: Game Specification</span>
                    <div className="form-group" style={{ margin: 0 }}>
                        <select className="form-select" value={form.game_id} onChange={e => setForm({ ...form, game_id: e.target.value, team_ids: [] })} style={{ background: 'var(--bg-card)', fontSize: '1.1rem', padding: '12px' }}>
                            <option value="" disabled>-- Select Official Game Bracket --</option>
                            {games.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                        </select>
                    </div>
                </div>

                {!form.game_id ? (
                    <div className="empty-state" style={{ padding: '40px 20px' }}>
                        <Lock size={32} style={{ color: 'var(--text-muted)', marginBottom: '16px' }} />
                        <h3 style={{ color: 'var(--text-secondary)' }}>Awaiting Configuration</h3>
                        <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>You must select a game to unlock the dynamic match configuration form.</p>
                    </div>
                ) : (
                    <div className="match-wizard-fields fade-in">
                        <span style={{ fontSize: '0.8rem', color: 'var(--neon-purple)', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 600, display: 'block', marginBottom: '16px' }}>Step 2: Match Parameters</span>

                        <div className="form-row">
                            <div className="form-group">
                                <label className="form-label">Round Identifier <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                                <input className="form-input" value={form.round} onChange={e => setForm({ ...form, round: e.target.value })} placeholder="e.g. Semi Finals" />
                            </div>
                            <div className="form-group">
                                <label className="form-label">Match ID # <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                                <input className="form-input" type="number" min="1" value={form.match_number} onChange={e => setForm({ ...form, match_number: parseInt(e.target.value) || 1 })} />
                            </div>
                        </div>

                        <div className="form-row">
                            <div className="form-group">
                                <label className="form-label">Match Format / Type <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                                <input className="form-input" value={form.match_type} onChange={e => setForm({ ...form, match_type: e.target.value })} placeholder="e.g. standard, knockout" />
                            </div>
                            <div className="form-group">
                                <label className="form-label">Venue / Location</label>
                                <input className="form-input" value={form.venue || ''} onChange={e => setForm({ ...form, venue: e.target.value })} placeholder="e.g. Main Stage, Room 101" />
                            </div>
                        </div>

                        <div className="form-row">
                            <div className="form-group">
                                <label className="form-label">Status</label>
                                <select className="form-select" value={form.status} onChange={e => setForm({ ...form, status: e.target.value })}>
                                    {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
                                </select>
                            </div>
                            <div className="form-group">
                                <label className="form-label">Date & Time <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                                <input className="form-input" type="datetime-local" value={form.scheduled_at} onChange={e => setForm({ ...form, scheduled_at: e.target.value })} required />
                            </div>
                        </div>

                        <div className="form-group" style={{ marginTop: '24px', background: 'var(--bg-card)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-primary)' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                                <label className="form-label" style={{ margin: 0 }}>Team Roster Selection <span style={{ color: 'var(--neon-red)' }}>*</span></label>
                                <span style={{ fontSize: '0.8rem', color: isTeamCountValid() ? 'var(--neon-cyan)' : 'var(--neon-red)', fontWeight: 600 }}>
                                    {isMultiTeamGame
                                        ? `Selected: ${form.team_ids.length} (1 or more)`
                                        : `Selected: ${form.team_ids.length} (Requires EXACTLY 2)`}
                                    {isTeamCountValid() && <CheckCircle size={12} style={{ marginLeft: '4px', verticalAlign: '-2px' }} />}
                                </span>
                            </div>

                            {gameTeams.length === 0 ? (
                                <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', fontStyle: 'italic' }}>No teams exist for this game yet.</p>
                            ) : (
                                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '8px', maxHeight: '250px', overflow: 'auto', paddingRight: '8px' }}>
                                    {gameTeams.map(t => (
                                        <label key={t.id} style={{
                                            display: 'flex', alignItems: 'center', gap: '8px', padding: '8px 12px',
                                            background: form.team_ids.includes(t.id) ? 'rgba(181, 55, 242, 0.1)' : 'var(--bg-input)',
                                            border: `1px solid ${form.team_ids.includes(t.id) ? 'var(--neon-purple)' : 'var(--border-secondary)'}`,
                                            borderRadius: '6px', cursor: 'pointer', fontSize: '0.85rem', transition: 'all 0.2s',
                                            opacity: (!form.team_ids.includes(t.id) && !isMultiTeamGame && form.team_ids.length >= 2) ? 0.5 : 1
                                        }}>
                                            <input type="checkbox" checked={form.team_ids.includes(t.id)} onChange={() => toggleTeam(t.id)} style={{ display: 'none' }} />
                                            <div style={{
                                                width: 16, height: 16, borderRadius: 4, border: '1px solid',
                                                borderColor: form.team_ids.includes(t.id) ? 'var(--neon-purple)' : 'var(--border-primary)',
                                                background: form.team_ids.includes(t.id) ? 'var(--neon-purple)' : 'transparent',
                                                flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center'
                                            }}>
                                                {form.team_ids.includes(t.id) && <CheckCircle size={10} color="#fff" />}
                                            </div>
                                            <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontWeight: form.team_ids.includes(t.id) ? 600 : 400 }}>
                                                {t.team_name}
                                            </span>
                                        </label>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                )}
            </Modal>

            {/* Results Entry Modal */}
            <Modal
                isOpen={resultModalOpen}
                onClose={() => setResultModalOpen(false)}
                title={`Results — ${selectedMatch?.round} #${selectedMatch?.match_number}`}
                size="lg"
                footer={
                    <>
                        <button className="btn btn-secondary" onClick={() => setResultModalOpen(false)}>Cancel</button>
                        <button className="btn btn-primary" onClick={saveResults} disabled={selectedMatch?.locked}>
                            {selectedMatch?.locked ? 'Locked' : 'Save Results'}
                        </button>
                    </>
                }
            >
                {results.length === 0 ? (
                    <p style={{ color: 'var(--text-muted)' }}>No teams assigned to this match</p>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table" style={{ fontSize: '0.8rem' }}>
                            <thead>
                                <tr>
                                    <th>Team</th>
                                    <th>Score</th>
                                    <th>Placement</th>
                                    <th>Kills</th>
                                    <th>Deaths</th>
                                    <th>Time (ms)</th>
                                </tr>
                            </thead>
                            <tbody>
                                {results.map((r, idx) => (
                                    <tr key={r.team_id}>
                                        <td style={{ fontWeight: 600 }}>{r.team_name}</td>
                                        <td><input className="form-input" type="number" value={r.score} onChange={e => updateResult(idx, 'score', e.target.value)} style={{ width: 70 }} /></td>
                                        <td><input className="form-input" type="number" min="1" value={r.placement || ''} onChange={e => updateResult(idx, 'placement', e.target.value)} style={{ width: 60 }} placeholder="—" /></td>
                                        <td><input className="form-input" type="number" min="0" value={r.kills} onChange={e => updateResult(idx, 'kills', e.target.value)} style={{ width: 60 }} /></td>
                                        <td><input className="form-input" type="number" min="0" value={r.deaths} onChange={e => updateResult(idx, 'deaths', e.target.value)} style={{ width: 60 }} /></td>
                                        <td><input className="form-input" type="number" min="0" value={r.time_ms || ''} onChange={e => updateResult(idx, 'time_ms', e.target.value)} style={{ width: 90 }} placeholder="ms" /></td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </Modal>
        </div>
    );
}
