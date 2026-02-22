import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { useToast } from '../../components/Toast';
import { FileDown, FileSpreadsheet, Table } from 'lucide-react';
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

    const fetchExportData = async (table) => {
        let query = supabase.from(table).select('*');
        if (selectedGame && ['teams', 'matches', 'leaderboards'].includes(table)) {
            query = query.eq('game_id', selectedGame);
        }
        const { data, error } = await query;
        if (error) throw error;
        return data || [];
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
            const tables = ['teams', 'players', 'matches', 'match_results', 'leaderboards'];
            if (format === 'excel') {
                const wb = XLSX.utils.book_new();
                for (const table of tables) {
                    const data = await fetchExportData(table);
                    const ws = XLSX.utils.json_to_sheet(data.length > 0 ? data : [{ 'No Data': '' }]);
                    XLSX.utils.book_append_sheet(wb, ws, table);
                }
                XLSX.writeFile(wb, 'esports_full_export.xlsx');
            } else {
                for (const table of tables) {
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
        { name: 'teams', label: 'Teams', icon: Table },
        { name: 'players', label: 'Players', icon: Table },
        { name: 'matches', label: 'Matches', icon: Table },
        { name: 'match_results', label: 'Match Results', icon: Table },
        { name: 'leaderboards', label: 'Leaderboards', icon: Table },
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
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 'var(--space-md)' }}>
                {tables.map(t => (
                    <div key={t.name} className="card" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-md)' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)' }}>
                            <t.icon size={16} style={{ color: 'var(--neon-cyan)' }} />
                            <span style={{ fontFamily: 'var(--font-display)', fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px' }}>
                                {t.label}
                            </span>
                        </div>
                        <div style={{ display: 'flex', gap: 'var(--space-sm)' }}>
                            <button className="btn btn-sm btn-secondary" onClick={() => exportCSV(t.name)} disabled={exporting}>
                                <FileDown size={12} /> CSV
                            </button>
                            <button className="btn btn-sm btn-secondary" onClick={() => exportExcel(t.name)} disabled={exporting}>
                                <FileSpreadsheet size={12} /> Excel
                            </button>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
}
