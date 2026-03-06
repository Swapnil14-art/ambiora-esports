import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useToast } from '../../components/Toast';
import { FileDown, FileSpreadsheet, Table, Users, Gamepad2, UserCog, Swords, Trophy, ClipboardList, Calendar } from 'lucide-react';
import Papa from 'papaparse';
import * as XLSX from 'xlsx';

export default function ExportData() {
    const toast = useToast();
    const [games, setGames] = useState([]);
    const [selectedGame, setSelectedGame] = useState('');
    const [exporting, setExporting] = useState(false);

    useEffect(() => {
        fetchGames();
    }, []);

    const fetchGames = async () => {
        const { data } = await supabase.from('games').select('*').order('name');
        setGames(data || []);
    };

    // Flatten nested objects for export (e.g. { teams: { team_name: 'X' } } → { team_name: 'X' })
    const flatten = (rows, mappings) => {
        return rows.map(row => {
            const flat = {};
            for (const [key, label] of Object.entries(mappings)) {
                const keys = key.split('.');
                let val = row;
                for (const k of keys) {
                    val = val?.[k];
                }
                flat[label] = val ?? '';
            }
            return flat;
        });
    };

    const fetchExportData = async (tableKey) => {
        switch (tableKey) {
            case 'games': {
                const { data, error } = await supabase.from('games').select('*').order('name');
                if (error) throw error;
                return flatten(data || [], {
                    'id': 'Game ID',
                    'name': 'Game Name',
                    'slug': 'Slug',
                    'max_teams': 'Max Teams',
                    'created_at': 'Created At',
                });
            }

            case 'profiles': {
                const { data, error } = await supabase.from('profiles').select('*, games:assigned_game_id(name)');
                if (error) throw error;
                return flatten(data || [], {
                    'id': 'User ID',
                    'email': 'Email',
                    'display_name': 'Display Name',
                    'role': 'Role',
                    'games.name': 'Assigned Game',
                    'created_at': 'Created At',
                    'updated_at': 'Updated At',
                });
            }

            case 'teams': {
                let query = supabase.from('teams').select('*, games(name), profiles:created_by(display_name, email)').order('created_at', { ascending: false });
                if (selectedGame) query = query.eq('game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                return flatten(data || [], {
                    'id': 'Team ID',
                    'team_name': 'Team Name',
                    'games.name': 'Game',
                    'status': 'Status',
                    'profiles.display_name': 'Created By (Name)',
                    'profiles.email': 'Created By (Email)',
                    'logo_url': 'Logo URL',
                    'created_at': 'Created At',
                    'updated_at': 'Updated At',
                });
            }

            case 'players': {
                let query = supabase.from('players').select('*, teams!inner(team_name, game_id, games(name))').order('created_at', { ascending: false });
                if (selectedGame) query = query.eq('teams.game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                return flatten(data || [], {
                    'id': 'Player ID',
                    'name': 'Name',
                    'in_game_name': 'In-Game Name',
                    'role': 'Role',
                    'phone': 'Phone',
                    'year_of_study': 'Year of Study',
                    'teams.team_name': 'Team',
                    'teams.games.name': 'Game',
                    'user_id': 'Linked User ID',
                    'created_at': 'Created At',
                    'updated_at': 'Updated At',
                });
            }

            case 'matches': {
                let query = supabase.from('matches').select('*, games(name, slug), match_teams(team_id, teams(team_name))').order('created_at', { ascending: false });
                if (selectedGame) query = query.eq('game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                return (data || []).map(m => ({
                    'Match ID': m.id,
                    'Game': m.games?.name || '',
                    'Round': m.round,
                    'Match #': m.match_number,
                    'Status': m.status,
                    'Match Type': m.match_type,
                    'Best Of': m.best_of,
                    'Locked': m.locked ? 'Yes' : 'No',
                    'Venue': m.venue || '',
                    'Teams': m.match_teams?.map(mt => mt.teams?.team_name).filter(Boolean).join(' vs ') || '',
                    'Scheduled At': m.scheduled_at || '',
                    'Created At': m.created_at,
                    'Updated At': m.updated_at,
                }));
            }

            case 'match_teams': {
                let query = supabase.from('match_teams').select('*, teams(team_name, game_id, games(name)), matches(round, match_number, status)');
                if (selectedGame) query = query.eq('teams.game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                const filtered = selectedGame ? (data || []).filter(mt => mt.teams?.game_id === selectedGame) : data || [];
                return flatten(filtered, {
                    'id': 'ID',
                    'match_id': 'Match ID',
                    'team_id': 'Team ID',
                    'teams.team_name': 'Team Name',
                    'teams.games.name': 'Game',
                    'matches.round': 'Round',
                    'matches.match_number': 'Match #',
                    'matches.status': 'Match Status',
                    'seed': 'Seed',
                });
            }

            case 'match_results': {
                let query = supabase.from('match_results').select('*, teams(team_name, game_id, games(name)), matches(round, match_number)');
                if (selectedGame) query = query.eq('teams.game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                const filtered = selectedGame ? (data || []).filter(mr => mr.teams?.game_id === selectedGame) : data || [];
                return flatten(filtered, {
                    'id': 'Result ID',
                    'matches.round': 'Round',
                    'matches.match_number': 'Match #',
                    'teams.team_name': 'Team',
                    'teams.games.name': 'Game',
                    'score': 'Score',
                    'placement': 'Placement',
                    'kills': 'Kills',
                    'deaths': 'Deaths',
                    'time_ms': 'Time (ms)',
                    'created_at': 'Created At',
                    'updated_at': 'Updated At',
                });
            }

            case 'leaderboards': {
                let query = supabase.from('leaderboards').select('*, teams(team_name), games:game_id(name)').order('rank');
                if (selectedGame) query = query.eq('game_id', selectedGame);
                const { data, error } = await query;
                if (error) throw error;
                return flatten(data || [], {
                    'id': 'ID',
                    'games.name': 'Game',
                    'teams.team_name': 'Team',
                    'rank': 'Rank',
                    'total_points': 'Total Points',
                    'total_kills': 'Total Kills',
                    'wins': 'Wins',
                    'matches_played': 'Matches Played',
                    'updated_at': 'Updated At',
                });
            }

            case 'audit_logs': {
                const { data, error } = await supabase.from('audit_logs').select('*, profiles:user_id(display_name, email)').order('created_at', { ascending: false }).limit(1000);
                if (error) throw error;
                return (data || []).map(l => ({
                    'Log ID': l.id,
                    'User': l.profiles?.display_name || l.profiles?.email || '',
                    'Action': l.action,
                    'Details': l.details ? JSON.stringify(l.details) : '',
                    'Created At': l.created_at,
                }));
            }

            default:
                return [];
        }
    };

    const exportCSV = async (table) => {
        setExporting(true);
        try {
            const data = await fetchExportData(table);
            if (data.length === 0) {
                toast.info('No data to export');
                setExporting(false);
                return;
            }
            const csv = Papa.unparse(data);
            downloadFile(csv, `${table}_export.csv`, 'text/csv');
            toast.success(`Exported ${data.length} ${table} records`);
        } catch (err) {
            toast.error(`Export failed: ${err.message}`);
        }
        setExporting(false);
    };

    const exportExcel = async (table) => {
        setExporting(true);
        try {
            const data = await fetchExportData(table);
            if (data.length === 0) {
                toast.info('No data to export');
                setExporting(false);
                return;
            }
            const ws = XLSX.utils.json_to_sheet(data);
            const wb = XLSX.utils.book_new();
            XLSX.utils.book_append_sheet(wb, ws, table);
            XLSX.writeFile(wb, `${table}_export.xlsx`);
            toast.success(`Exported ${data.length} ${table} records`);
        } catch (err) {
            toast.error(`Export failed: ${err.message}`);
        }
        setExporting(false);
    };

    const exportAll = async (format) => {
        setExporting(true);
        try {
            const allTables = tables.map(t => t.name);
            if (format === 'excel') {
                const wb = XLSX.utils.book_new();
                for (const table of allTables) {
                    const data = await fetchExportData(table);
                    const ws = XLSX.utils.json_to_sheet(data.length > 0 ? data : [{ 'No Data': '' }]);
                    XLSX.utils.book_append_sheet(wb, ws, table.replace('match_', 'm_'));
                }
                XLSX.writeFile(wb, 'esports_full_export.xlsx');
            } else {
                for (const table of allTables) {
                    const data = await fetchExportData(table);
                    if (data.length > 0) {
                        const csv = Papa.unparse(data);
                        downloadFile(csv, `${table}_export.csv`, 'text/csv');
                    }
                }
            }
            toast.success('Full export completed');
        } catch (err) {
            toast.error(`Export failed: ${err.message}`);
        }
        setExporting(false);
    };

    const downloadFile = (content, filename, type) => {
        const blob = new Blob([content], { type });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
    };

    const tables = [
        { name: 'games', label: 'Games', icon: Gamepad2, description: 'All game brackets' },
        { name: 'profiles', label: 'Users / Profiles', icon: UserCog, description: 'All user accounts & roles' },
        { name: 'teams', label: 'Teams', icon: Users, description: 'Teams with status & creator info' },
        { name: 'players', label: 'Players', icon: Users, description: 'All player rosters with team & game' },
        { name: 'matches', label: 'Matches', icon: Swords, description: 'All matches with teams & schedule' },
        { name: 'match_teams', label: 'Match Teams', icon: Calendar, description: 'Team-to-match assignments' },
        { name: 'match_results', label: 'Match Results', icon: ClipboardList, description: 'Scores, kills, placements' },
        { name: 'leaderboards', label: 'Leaderboards', icon: Trophy, description: 'Computed rankings per game' },
        { name: 'audit_logs', label: 'Audit Logs', icon: ClipboardList, description: 'Last 1000 admin actions' },
    ];

    return (
        <div>
            <div className="page-header">
                <h1>Export Data</h1>
                <div className="page-header-actions">
                    <button className="btn btn-secondary" onClick={() => exportAll('csv')} disabled={exporting}>
                        <FileDown size={14} /> Export All CSV
                    </button>
                    <button className="btn btn-primary" onClick={() => exportAll('excel')} disabled={exporting}>
                        <FileSpreadsheet size={14} /> Export All Excel
                    </button>
                </div>
            </div>

            <div className="filters-bar" style={{ marginBottom: 'var(--space-lg)' }}>
                <select className="form-select" value={selectedGame} onChange={e => setSelectedGame(e.target.value)}>
                    <option value="">All Games</option>
                    {games.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                </select>
                <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                    Game filter applies to: Teams, Players, Matches, Match Teams, Match Results, Leaderboards
                </span>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 280px), 1fr))', gap: 'var(--space-md)' }}>
                {tables.map(t => (
                    <div key={t.name} className="card" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-sm)' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)' }}>
                            <t.icon size={16} style={{ color: 'var(--neon-cyan)', flexShrink: 0 }} />
                            <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px' }}>
                                {t.label}
                            </span>
                        </div>
                        <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)', margin: 0, lineHeight: 1.4 }}>
                            {t.description}
                        </p>
                        <div style={{ display: 'flex', gap: 'var(--space-sm)', marginTop: 'auto' }}>
                            <button className="btn btn-sm btn-secondary" onClick={() => exportCSV(t.name)} disabled={exporting} style={{ flex: 1 }}>
                                <FileDown size={12} /> CSV
                            </button>
                            <button className="btn btn-sm btn-secondary" onClick={() => exportExcel(t.name)} disabled={exporting} style={{ flex: 1 }}>
                                <FileSpreadsheet size={12} /> Excel
                            </button>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
}
