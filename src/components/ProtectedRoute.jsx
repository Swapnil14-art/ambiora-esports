import { Navigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

export default function ProtectedRoute({ children, allowedRoles }) {
    const { user, profile, loading } = useAuth();

    if (loading) {
        return (
            <div className="loading-screen">
                <div className="loader"></div>
                <p>INITIALIZING SYSTEM...</p>
            </div>
        );
    }

    // Not logged in → go to login
    if (!user) {
        return <Navigate to="/login" replace />;
    }

    // User exists but profile is null → profile fetch failed
    // Redirect to login so they can try again instead of infinite loading
    if (!profile) {
        return <Navigate to="/login" replace />;
    }

    // Role check
    if (allowedRoles && !allowedRoles.includes(profile.role)) {
        // Rather than showing a harsh 403 page, gracefully bounce them to their 
        // respective dashboard. This also fixes React unmount race conditions when 
        // changing roles from within a route protected by a previous role!
        switch (profile.role) {
            case 'admin':
                return <Navigate to="/admin" replace />;
            case 'player':
                return <Navigate to="/player" replace />;
            case 'game_leader':
                return <Navigate to="/leader" replace />;
            default:
                return <Navigate to="/live" replace />;
        }
    }

    return children;
}
