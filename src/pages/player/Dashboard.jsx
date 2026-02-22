import { Trophy, Gamepad2 } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { Link } from 'react-router-dom';

export default function PlayerDashboard() {
    const { profile } = useAuth();

    return (
        <div className="app-layout">
            <main className="main-content" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '100vh', padding: '20px' }}>
                <div className="card" style={{ maxWidth: '600px', width: '100%', textAlign: 'center', padding: '40px' }}>
                    <div style={{ display: 'flex', justifyContent: 'center', gap: '20px', marginBottom: '20px' }}>
                        <Gamepad2 size={48} style={{ color: 'var(--neon-purple)' }} />
                        <Trophy size={48} style={{ color: 'var(--neon-cyan)' }} />
                    </div>

                    <h2 className="text-gradient" style={{ fontSize: '2.5rem', marginBottom: '10px' }}>
                        Welcome, Player!
                    </h2>

                    <div style={{ padding: '20px', background: 'rgba(255,255,255,0.02)', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.05)', marginBottom: '30px', marginTop: '30px' }}>
                        <p style={{ color: 'var(--text-secondary)', fontSize: '1.2rem', lineHeight: '1.6', margin: 0 }}>
                            You have successfully registered for the bracket.
                            <br /><br />
                            <strong style={{ color: 'var(--text-primary)' }}>What happens next?</strong>
                            <br />
                            Your Team Leader will need to add you to their official roster using your name/in-game ID. Once you are added, you will automatically be included in the match standings.
                        </p>
                    </div>

                    <Link to="/live" className="btn btn-primary" style={{ padding: '16px 32px', fontSize: '1.2rem', display: 'inline-flex' }}>
                        View Live Brackets & Standings
                    </Link>
                </div>
            </main>
        </div>
    );
}
