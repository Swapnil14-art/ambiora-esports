import { useState, useEffect } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import {
    LayoutDashboard,
    Users,
    UserPlus,
    Gamepad2,
    Trophy,
    Calendar,
    ClipboardList,
    FileDown,
    Shield,
    Swords,
    Target,
    Car,
    LogOut,
    UserCog,
} from 'lucide-react';

const GAME_ICONS = {
    bgmi: Target,
    valorant: Swords,
    fifa25: Gamepad2,
    f1: Car,
};

export default function Sidebar({ isOpen }) {
    const { profile, logout, isAdmin, isGameLeader, isPlayer } = useAuth();
    const location = useLocation();
    const [hasTeam, setHasTeam] = useState(false);

    useEffect(() => {
        if (isGameLeader) {
            if (!profile?.assigned_game_id) {
                setHasTeam(false);
                return;
            }
            supabase
                .from('teams')
                .select('id', { count: 'exact', head: true })
                .eq('created_by', profile.id)
                .then(({ count }) => {
                    setHasTeam((count || 0) > 0);
                });
        }
    }, [isGameLeader, profile]);

    const adminNavItems = [
        { label: 'Overview', path: '/admin', icon: LayoutDashboard, end: true },
        { label: 'Users', path: '/admin/users', icon: UserCog },
        { label: 'Teams', path: '/admin/teams', icon: Users },
        { label: 'Fixtures', path: '/admin/fixtures', icon: Calendar },
        { label: 'Matches', path: '/admin/matches', icon: Swords },
        { label: 'Leaderboards', path: '/admin/leaderboards', icon: Trophy },
        { label: 'Audit Logs', path: '/admin/audit', icon: ClipboardList },
        { label: 'Export Data', path: '/admin/export', icon: FileDown },
    ];

    const leaderNavItems = [
        { label: 'Dashboard', path: '/leader', icon: LayoutDashboard, end: true },
        { label: 'Teams', path: '/leader/teams', icon: Users },
        { label: 'Players', path: '/leader/players', icon: UserPlus },
        { label: 'Fixtures', path: '/leader/fixtures', icon: Calendar },
        { label: 'Results', path: '/leader/results', icon: ClipboardList },
        { label: 'Leaderboard', path: '/leader/leaderboard', icon: Trophy },
    ];

    const playerNavItems = [
        { label: 'Dashboard', path: '/player', icon: LayoutDashboard, end: true },
        { label: 'Teams', path: '/player/teams', icon: Users },
        { label: 'Live Bracket', path: '/live', icon: Trophy, end: false },
    ];

    let navItems = isAdmin ? adminNavItems : (isGameLeader ? leaderNavItems : playerNavItems);

    // Hide extra options until they finish onboarding
    if (isGameLeader && !isAdmin && !hasTeam) {
        navItems = leaderNavItems.filter(item =>
            profile?.assigned_game_id
                ? ['Dashboard', 'Teams'].includes(item.label)
                : ['Dashboard'].includes(item.label)
        );
    }

    const RoleBadge = () => {
        if (isAdmin) return <span className="badge badge-admin">Admin</span>;
        if (isGameLeader) return <span className="badge badge-leader">Leader</span>;
        if (isPlayer) return <span className="badge badge-viewer" style={{ background: 'rgba(0, 255, 204, 0.1)', color: 'var(--neon-cyan)', border: '1px solid rgba(0, 255, 204, 0.2)' }}>Player</span>;
        return <span className="badge badge-viewer">Viewer</span>;
    };

    return (
        <aside className={`sidebar ${isOpen ? 'open' : ''}`}>
            <div className="sidebar-header">
                <Gamepad2 size={20} style={{ color: 'var(--neon-purple)' }} />
                <span className="sidebar-brand text-gradient">Ambiora</span>
            </div>

            <nav className="sidebar-nav">
                <div className="sidebar-section">
                    <div className="sidebar-section-title">Navigation</div>
                    {navItems.map(item => (
                        <NavLink
                            key={item.path}
                            to={item.path}
                            end={item.end}
                            className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
                        >
                            <item.icon size={16} />
                            {item.label}
                        </NavLink>
                    ))}
                </div>

                {isAdmin && (
                    <div className="sidebar-section">
                        <div className="sidebar-section-title">Games</div>
                        {Object.entries(GAME_ICONS).map(([slug, Icon]) => (
                            <NavLink
                                key={slug}
                                to={`/admin/matches?game=${slug}`}
                                className={`nav-item ${location.search.includes(slug) ? 'active' : ''}`}
                            >
                                <Icon size={16} />
                                {slug.toUpperCase()}
                            </NavLink>
                        ))}
                    </div>
                )}
            </nav>

            <div className="sidebar-footer">
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                    <Shield size={14} style={{ color: 'var(--text-muted)' }} />
                    <span style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                        {profile?.display_name || profile?.email}
                    </span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <RoleBadge />
                    <button className="btn-icon" onClick={logout} title="Logout">
                        <LogOut size={14} />
                    </button>
                </div>
            </div>
        </aside>
    );
}
