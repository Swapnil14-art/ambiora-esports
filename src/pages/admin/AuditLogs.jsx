import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { ClipboardList, Search, Filter } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function AuditLogs() {
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(0);
    const PAGE_SIZE = 50;

    useEffect(() => {
        fetchLogs();
    }, [page]);

    const fetchLogs = async () => {
        setLoading(true);
        const { data, error } = await supabase
            .from('audit_logs')
            .select('*, profiles(display_name, email)')
            .order('created_at', { ascending: false })
            .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

        if (error) console.error(error);
        setLogs(data || []);
        setLoading(false);
    };

    const filtered = search
        ? logs.filter(l => l.action.toLowerCase().includes(search.toLowerCase()))
        : logs;

    return (
        <div>
            <div className="page-header">
                <h1>Audit Logs</h1>
            </div>

            <div className="filters-bar">
                <div style={{ position: 'relative' }}>
                    <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                    <input
                        className="form-input"
                        placeholder="Filter actions..."
                        value={search}
                        onChange={e => setSearch(e.target.value)}
                        style={{ paddingLeft: 30 }}
                    />
                </div>
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {loading ? (
                    <div style={{ padding: 'var(--space-md)' }}><SkeletonLoader type="table" count={8} /></div>
                ) : filtered.length === 0 ? (
                    <div className="empty-state">
                        <ClipboardList size={32} />
                        <p>No audit logs found</p>
                    </div>
                ) : (
                    <div className="table-responsive">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th style={{ width: 180 }}>Timestamp</th>
                                    <th>User</th>
                                    <th>Action</th>
                                    <th>Details</th>
                                </tr>
                            </thead>
                            <tbody>
                                {filtered.map(log => (
                                    <tr key={log.id}>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem', whiteSpace: 'nowrap' }}>
                                            {new Date(log.created_at).toLocaleString()}
                                        </td>
                                        <td style={{ color: 'var(--neon-cyan)', fontSize: '0.8rem' }}>
                                            {log.profiles?.display_name || log.profiles?.email || log.user_id?.slice(0, 8)}
                                        </td>
                                        <td style={{ fontWeight: 500 }}>{log.action}</td>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.75rem', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                            {log.details ? JSON.stringify(log.details) : '—'}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            <div style={{ display: 'flex', justifyContent: 'center', gap: 'var(--space-sm)', marginTop: 'var(--space-md)' }}>
                <button className="btn btn-sm btn-secondary" disabled={page === 0} onClick={() => setPage(p => p - 1)}>Previous</button>
                <span style={{ padding: '4px 12px', fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Page {page + 1}</span>
                <button className="btn btn-sm btn-secondary" disabled={logs.length < PAGE_SIZE} onClick={() => setPage(p => p + 1)}>Next</button>
            </div>
        </div>
    );
}
