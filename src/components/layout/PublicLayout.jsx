import { Outlet, NavLink } from 'react-router-dom';
import { Gamepad2, Calendar, ClipboardList, Trophy, LogIn, Users } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';

export default function PublicLayout() {
    const { user } = useAuth();
    return (
        <div style={{ minHeight: '100vh', background: 'var(--bg-primary)' }}>
            {/* Public top navigation bar */}
            <header className="public-header">
                <div className="public-header-left">
                    <div className="public-logo">
                        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)' }}>
                            <Gamepad2 size={20} style={{ color: 'var(--neon-purple)' }} />
                            <span className="public-brand">
                                Ambiora Esports
                            </span>
                        </div>
                        {user ? (
                            <NavLink to="/" className="btn btn-sm btn-primary public-login-mobile" style={{ textDecoration: 'none' }}>
                                <Gamepad2 size={14} /> My Dashboard
                            </NavLink>
                        ) : (
                            <NavLink to="/login" className="btn btn-sm btn-secondary public-login-mobile" style={{ textDecoration: 'none' }}>
                                <LogIn size={14} /> Login/Signup
                            </NavLink>
                        )}
                    </div>

                    <nav className="public-nav">
                        <NavLink
                            to="/live"
                            end
                            className={({ isActive }) => `tab ${isActive ? 'active' : ''}`}
                            style={{ borderBottom: 'none', height: 'var(--topbar-height)', display: 'flex', alignItems: 'center' }}
                        >
                            <Users size={14} style={{ marginRight: 4 }} /> Teams
                        </NavLink>
                        <NavLink
                            to="/live/fixtures"
                            className={({ isActive }) => `tab ${isActive ? 'active' : ''}`}
                            style={{ borderBottom: 'none', height: 'var(--topbar-height)', display: 'flex', alignItems: 'center' }}
                        >
                            <Calendar size={14} style={{ marginRight: 4 }} /> Fixtures
                        </NavLink>
                        <NavLink
                            to="/live/results"
                            className={({ isActive }) => `tab ${isActive ? 'active' : ''}`}
                            style={{ borderBottom: 'none', height: 'var(--topbar-height)', display: 'flex', alignItems: 'center' }}
                        >
                            <ClipboardList size={14} style={{ marginRight: 4 }} /> Results
                        </NavLink>
                        <NavLink
                            to="/live/leaderboards"
                            className={({ isActive }) => `tab ${isActive ? 'active' : ''}`}
                            style={{ borderBottom: 'none', height: 'var(--topbar-height)', display: 'flex', alignItems: 'center' }}
                        >
                            <Trophy size={14} style={{ marginRight: 4 }} /> Leaderboards
                        </NavLink>
                    </nav>
                </div>

                {user ? (
                    <NavLink to="/" className="btn btn-sm btn-primary public-login-desktop" style={{ textDecoration: 'none' }}>
                        <Gamepad2 size={14} /> My Dashboard
                    </NavLink>
                ) : (
                    <NavLink to="/login" className="btn btn-sm btn-secondary public-login-desktop" style={{ textDecoration: 'none' }}>
                        <LogIn size={14} /> Login/Signup
                    </NavLink>
                )}
            </header>

            {/* Page content */}
            <div style={{ padding: 'var(--space-xl)', maxWidth: 1200, margin: '0 auto' }}>
                <Outlet />
            </div>
        </div>
    );
}
