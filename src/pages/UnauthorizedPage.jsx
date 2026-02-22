import { Link } from 'react-router-dom';
import { ShieldX } from 'lucide-react';

export default function UnauthorizedPage() {
    return (
        <div className="unauthorized-page">
            <ShieldX size={64} style={{ color: 'var(--neon-red)' }} />
            <h1>403</h1>
            <h3 style={{ color: 'var(--text-secondary)', fontFamily: 'var(--font-primary)' }}>
                ACCESS DENIED
            </h3>
            <p style={{ color: 'var(--text-muted)', maxWidth: '400px' }}>
                You don't have permission to access this area.
                Contact your admin if you believe this is an error.
            </p>
            <Link to="/" className="btn btn-secondary" style={{ marginTop: '16px' }}>
                Return to Base
            </Link>
        </div>
    );
}
