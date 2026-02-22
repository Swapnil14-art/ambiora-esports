import { Outlet } from 'react-router-dom';
import Sidebar from './Sidebar';
import { useState, useEffect } from 'react';
import { Menu, X } from 'lucide-react';
import { useLocation } from 'react-router-dom';
import Gatekeeper from './Gatekeeper';

export default function AppLayout() {
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);
    const location = useLocation();

    // Close sidebar on route change for mobile
    useEffect(() => {
        setIsSidebarOpen(false);
    }, [location.pathname]);

    return (
        <Gatekeeper>
            <div className="app-layout">
                {/* Mobile Header */}
                <div className="mobile-header">
                    <button className="btn-icon" onClick={() => setIsSidebarOpen(!isSidebarOpen)}>
                        {isSidebarOpen ? <X size={20} /> : <Menu size={20} />}
                    </button>
                    <span className="sidebar-brand text-gradient">Ambiora</span>
                </div>

                {/* Mobile Overlay */}
                <div
                    className={`sidebar-overlay ${isSidebarOpen ? 'active' : ''}`}
                    onClick={() => setIsSidebarOpen(false)}
                />

                <Sidebar isOpen={isSidebarOpen} />

                <main className="main-content">
                    <div className="page-content page-transition" key={location.pathname}>
                        <Outlet />
                    </div>
                </main>
            </div>
        </Gatekeeper>
    );
}
