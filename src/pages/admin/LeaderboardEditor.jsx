import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../components/Toast';
import { Save, Plus, Trash2, Trophy, Clock, RefreshCw } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

function formatTime(ms) {
    if (!ms) return '';
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    const millis = ms % 1000;
    return `${minutes}:${String(seconds).padStart(2, '0')}.${String(millis).padStart(3, '0')}`;
}

function parseTimeToMs(str) {
    if (!str) return null;
    // Accept formats: m:ss.mmm or ss.mmm or just ms number
    const parts = str.match(/^(\d+):(\d{1,2})\.(\d{1,3})$/);
    if (parts) {
        return parseInt(parts[1]) * 60000 + parseInt(parts[2]) * 1000 + parseInt(parts[3].padEnd(3, '0'));
    }
    const secParts = str.match(/^(\d+)\.(\d{1,3})$/);
    if (secParts) {
        return parseInt(secParts[1]) * 1000 + parseInt(secParts[2].padEnd(3, '0'));
    }
    const num = parseInt(str);
    return isNaN(num) ? null : num;
}

export default function LeaderboardEditor() {
    const { profile } = useAuth();
    const toast = useToast();
    const [games, setGames] = useState([]);
    const [activeGame, setActiveGame] = useState(null);
    const [allTeams, setAllTeams] = useState([]);
    const [entries, setEntries] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [deletedIds, setDeletedIds] = useState([]);

    useEffect(() => {
        fetchGames();
    }, []);

    useEffect(() => {
        if (activeGame) fetchData();
    }, [activeGame]);

    const fetchGames = async () => {
        const { data } = await supabase.from('games').select('*').order('name');
        setGames(data || []);
        if (data?.length > 0) setActiveGame(data[0]);
    };

    const fetchData = useCallback(async () => {
        setLoading(true);
        setDeletedIds([]);

        // Fetch teams for this game AND existing leaderboard entries in parallel
        const [teamsRes, lbRes] = await Promise.all([
            supabase.from('teams').select('id, team_name, status').eq('game_id', activeGame.id).neq('status', 'disqualified').order('team_name'),
            supabase.from('leaderboards').select('*,teams(team_name)').eq('game_id', activeGame.id).order('rank', { ascending: true, nullsFirst: false }),
        ]);

        setAllTeams(teamsRes.data || []);

        // Build entries from existing leaderboard data
        const existing = (lbRes.data || []).map(row => ({
            id: row.id,
            team_id: row.team_id,
            team_name: row.teams?.team_name || '—',
            rank: row.rank || '',
            total_points: row.total_points || 0,
            total_kills: row.total_kills || 0,
            wins: row.wins || 0,
            matches_played: row.matches_played || 0,
            best_time_ms: row.extra_data?.best_time_ms || null,
            _bestTimeStr: formatTime(row.extra_data?.best_time_ms),
            _isNew: false,
        }));

        setEntries(existing);
        setLoading(false);
    }, [activeGame]);

    const addEntry = (teamId) => {
        const team = allTeams.find(t => t.id === teamId);
        if (!team) return;
        if (entries.some(e => e.team_id === teamId)) {
            toast.error('Team already in leaderboard');
            return;
        }

        const nextRank = entries.length > 0 ? Math.max(...entries.map(e => parseInt(e.rank) || 0)) + 1 : 1;
        setEntries(prev => [...prev, {
            id: null,
            team_id: teamId,
            team_name: team.team_name,
            rank: nextRank,
            total_points: 0,
            total_kills: 0,
            wins: 0,
            matches_played: 0,
            best_time_ms: null,
            _bestTimeStr: '',
            _isNew: true,
        }]);
    };

    const removeEntry = (idx) => {
        const entry = entries[idx];
        if (entry.id) {
            setDeletedIds(prev => [...prev, entry.id]);
        }
        setEntries(prev => prev.filter((_, i) => i !== idx));
    };

    const updateEntry = (idx, field, value) => {
        setEntries(prev => prev.map((e, i) => {
            if (i !== idx) return e;
            if (field === '_bestTimeStr') {
                return { ...e, _bestTimeStr: value, best_time_ms: parseTimeToMs(value) };
            }
            return { ...e, [field]: value };
        }));
    };

    const addAllTeams = () => {
        const existingTeamIds = new Set(entries.map(e => e.team_id));
        const missingTeams = allTeams.filter(t => !existingTeamIds.has(t.id));
        if (missingTeams.length === 0) {
            toast.info('All teams are already in the leaderboard');
            return;
        }
        let nextRank = entries.length > 0 ? Math.max(...entries.map(e => parseInt(e.rank) || 0)) + 1 : 1;
        const newEntries = missingTeams.map(t => ({
            id: null,
            team_id: t.id,
            team_name: t.team_name,
            rank: nextRank++,
            total_points: 0,
            total_kills: 0,
            wins: 0,
            matches_played: 0,
            best_time_ms: null,
            _bestTimeStr: '',
            _isNew: true,
        }));
        setEntries(prev => [...prev, ...newEntries]);
        toast.success(`Added ${newEntries.length} team(s)`);
    };

    const handleSave = async () => {
        if (!activeGame) return;
        setSaving(true);

        try {
            // 1. Delete removed entries
            for (const id of deletedIds) {
                await supabase.from('leaderboards').delete().eq('id', id);
            }

            // 2. Upsert all current entries
            for (const entry of entries) {
                const payload = {
                    game_id: activeGame.id,
                    team_id: entry.team_id,
                    rank: parseInt(entry.rank) || null,
                    total_points: parseInt(entry.total_points) || 0,
                    total_kills: parseInt(entry.total_kills) || 0,
                    wins: parseInt(entry.wins) || 0,
                    matches_played: parseInt(entry.matches_played) || 0,
                    extra_data: entry.best_time_ms ? { best_time_ms: entry.best_time_ms } : {},
                };

                if (entry.id) {
                    const { error } = await supabase.from('leaderboards').update(payload).eq('id', entry.id);
                    if (error) throw error;
                } else {
                    const { error } = await supabase.from('leaderboards').insert(payload);
                    if (error) throw error;
                }
            }

            await supabase.from('audit_logs').insert({
                user_id: profile.id,
                action: `Manually edited leaderboard for ${activeGame.name}`,
                details: { game_id: activeGame.id, entries_count: entries.length },
            });

            toast.success('Leaderboard saved successfully');
            setDeletedIds([]);
            fetchData(); // Refresh to get updated IDs
        } catch (err) {
            toast.error(`Save failed: ${err.message}`);
        }

        setSaving(false);
    };

    const isF1 = activeGame?.slug === 'f1';
    const isBGMI = activeGame?.slug === 'bgmi';
    const availableTeams = allTeams.filter(t => !entries.some(e => e.team_id === t.id));

    return (
        <div>
            <div className="page-header">
                <h1>Leaderboard Editor</h1>
                <div className="page-header-actions" style={{ display: 'flex', gap: '8px' }}>
                    <button className="btn btn-secondary" onClick={addAllTeams} title="Add all missing teams">
                        <Plus size={14} /> Add All Teams
                    </button>
                    <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
                        <Save size={14} /> {saving ? 'Saving...' : 'Save All'}
                    </button>
                </div>
            </div>

            <div className="tabs">
                {games.map(g => (
                    <button
                        key={g.id}
                        className={`tab ${activeGame?.id === g.id ? 'active' : ''}`}
                        onClick={() => setActiveGame(g)}
                    >
                        {g.name}
                    </button>
                ))}
            </div>

            {/* Add team dropdown */}
            {availableTeams.length > 0 && (
                <div style={{ marginBottom: 'var(--space-md)', display: 'flex', gap: 'var(--space-sm)', alignItems: 'center' }}>
                    <select
                        id="add-team-select"
                        className="form-select"
                        defaultValue=""
                        style={{ maxWidth: 300 }}
                    >
                        <option value="" disabled>— Add team to leaderboard —</option>
                        {availableTeams.map(t => (
                            <option key={t.id} value={t.id}>{t.team_name}</option>
                        ))}
                    </select>
                    <button
                        className="btn btn-secondary"
                        onClick={() => {
                            const sel = document.getElementById('add-team-select');
                            if (sel.value) {
                                addEntry(sel.value);
                                sel.value = '';
                            }
                        }}
                    >
                        <Plus size={14} /> Add
                    </button>
                </div>
            )}

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={6} /></div>
                ) : entries.length === 0 ? (
                    <div className="empty-state">
                        <Trophy size={32} />
                        <p>No leaderboard entries yet. Add teams above or click "Add All Teams".</p>
                    </div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table" style={{ fontSize: '0.85rem' }}>
                            <thead>
                                <tr>
                                    <th style={{ width: 50 }}>#</th>
                                    <th style={{ width: 70 }}>Rank</th>
                                    <th>Team</th>
                                    {isF1 ? (
                                        <th>Best Lap (m:ss.mmm)</th>
                                    ) : (
                                        <>
                                            <th>Points</th>
                                            {isBGMI && <th>Kills</th>}
                                            <th>Wins</th>
                                        </>
                                    )}
                                    <th>Played</th>
                                    <th style={{ width: 60 }}>Delete</th>
                                </tr>
                            </thead>
                            <tbody>
                                {entries.map((entry, idx) => (
                                    <tr key={entry.team_id} style={{
                                        background: entry._isNew ? 'rgba(0, 255, 204, 0.03)' : 'transparent',
                                    }}>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem' }}>{idx + 1}</td>
                                        <td>
                                            <input
                                                className="form-input"
                                                type="number"
                                                min="1"
                                                value={entry.rank}
                                                onChange={e => updateEntry(idx, 'rank', e.target.value)}
                                                style={{ width: 55, textAlign: 'center' }}
                                            />
                                        </td>
                                        <td style={{ fontWeight: 600 }}>
                                            {entry.team_name}
                                            {entry._isNew && (
                                                <span style={{ marginLeft: 6, fontSize: '0.65rem', color: 'var(--neon-cyan)', textTransform: 'uppercase' }}>new</span>
                                            )}
                                        </td>
                                        {isF1 ? (
                                            <td>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                                                    <Clock size={12} style={{ color: 'var(--neon-cyan)', flexShrink: 0 }} />
                                                    <input
                                                        className="form-input"
                                                        placeholder="1:23.456"
                                                        value={entry._bestTimeStr}
                                                        onChange={e => updateEntry(idx, '_bestTimeStr', e.target.value)}
                                                        style={{ width: 110 }}
                                                    />
                                                </div>
                                            </td>
                                        ) : (
                                            <>
                                                <td>
                                                    <input
                                                        className="form-input"
                                                        type="number"
                                                        min="0"
                                                        value={entry.total_points}
                                                        onChange={e => updateEntry(idx, 'total_points', e.target.value)}
                                                        style={{ width: 70 }}
                                                    />
                                                </td>
                                                {isBGMI && (
                                                    <td>
                                                        <input
                                                            className="form-input"
                                                            type="number"
                                                            min="0"
                                                            value={entry.total_kills}
                                                            onChange={e => updateEntry(idx, 'total_kills', e.target.value)}
                                                            style={{ width: 65 }}
                                                        />
                                                    </td>
                                                )}
                                                <td>
                                                    <input
                                                        className="form-input"
                                                        type="number"
                                                        min="0"
                                                        value={entry.wins}
                                                        onChange={e => updateEntry(idx, 'wins', e.target.value)}
                                                        style={{ width: 60 }}
                                                    />
                                                </td>
                                            </>
                                        )}
                                        <td>
                                            <input
                                                className="form-input"
                                                type="number"
                                                min="0"
                                                value={entry.matches_played}
                                                onChange={e => updateEntry(idx, 'matches_played', e.target.value)}
                                                style={{ width: 60 }}
                                            />
                                        </td>
                                        <td>
                                            <button
                                                className="btn-icon"
                                                onClick={() => removeEntry(idx)}
                                                title="Remove from leaderboard"
                                                style={{ color: 'var(--neon-red)' }}
                                            >
                                                <Trash2 size={14} />
                                            </button>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            <div style={{ marginTop: 'var(--space-md)', display: 'flex', justifyContent: 'flex-end' }}>
                <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ minWidth: 140 }}>
                    <Save size={14} /> {saving ? 'Saving...' : 'Save Changes'}
                </button>
            </div>
        </div>
    );
}
