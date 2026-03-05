import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { Gamepad2, Loader, UserPlus, Tv } from 'lucide-react';

export default function LoginPage() {
    const [mode, setMode] = useState('login'); // 'login' or 'signup'
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [displayName, setDisplayName] = useState('');
    const [error, setError] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);

    // Safety timeout for loading
    const [mountTime] = useState(Date.now());
    const [forceShow, setForceShow] = useState(false);

    const { login, signup, profile, user, loading: authLoading } = useAuth();
    const navigate = useNavigate();

    useEffect(() => {
        // If authLoading gets stuck over 5 seconds (Supabase outage or disconnected), force UI to render
        const check = setInterval(() => {
            if (Date.now() - mountTime > 3000) {
                setForceShow(true);
            }
        }, 1000);
        return () => clearInterval(check);
    }, [mountTime]);

    // If already logged in AND we have their profile, auto-redirect
    useEffect(() => {
        if (!authLoading && user) {
            if (profile) {
                redirectByRole(profile.role);
            } else if (!isSubmitting) {
                setError('Account missing profile data in Supabase. Try signing up as a new user with a different email, or check the profiles table.');
            }
        }
    }, [user, profile, authLoading, navigate, isSubmitting]);

    const redirectByRole = (role) => {
        switch (role) {
            case 'admin':
                navigate('/admin', { replace: true });
                break;
            case 'game_leader':
                navigate('/leader', { replace: true });
                break;
            case 'player':
                navigate('/player', { replace: true });
                break;
            default:
                navigate('/live', { replace: true });
        }
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        setIsSubmitting(true);

        try {
            let result;
            if (mode === 'signup') {
                if (password.length < 6) {
                    setError('Password must be at least 6 characters');
                    setIsSubmitting(false);
                    return;
                }
                result = await signup(email, password, displayName, 'game_leader');
            } else {
                result = await login(email, password);
            }

            if (!result.profile) {
                // Logged in/signed up via Supabase auth, but profile row missing
                setError('Authentication succeeded but the database profile trigger failed. Please check the `profiles` table in Supabase.');
                setIsSubmitting(false);
            }
            // If profile exists, useEffect handles redirect
        } catch (err) {
            console.error('Auth error:', err);
            // Translate common Supabase messages
            if (err.message.includes('Invalid login credentials')) {
                setError('Invalid email or password');
            } else if (err.message.includes('User already registered')) {
                setError('This email is already taken. Try logging in.');
            } else {
                setError(err.message || 'Authentication failed');
            }
            setIsSubmitting(false);
        }
    };

    // If AuthContext is still initializing the initial session, show loader
    // But if it takes longer than 3 seconds (forceShow), break the loop and show the form anyway
    if (authLoading && !isSubmitting && !forceShow) {
        return (
            <div className="login-page">
                <div className="login-card" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '48px' }}>
                    <Loader size={32} className="spin" style={{ color: 'var(--neon-purple)', marginBottom: '16px' }} />
                    <p style={{ color: 'var(--text-muted)' }}>Connecting to Supabase...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="login-page">
            <div className="login-card">
                <div className="login-header">
                    <Gamepad2 size={36} style={{ color: 'var(--neon-purple)', margin: '0 auto 12px' }} />
                    <h1 className="text-gradient">AMBIORA ESPORTS</h1>
                    <p style={{ fontWeight: 'bold', letterSpacing: '1px' }}>PARTICIPANTS LOGIN/SIGNUP</p>
                </div>

                {error && <div className="login-error">{error}</div>}

                <div style={{ display: 'flex', gap: '8px', marginBottom: '16px', borderBottom: '1px solid var(--border)', paddingBottom: '16px' }}>
                    <button
                        type="button"
                        className={`btn ${mode === 'login' ? 'btn-primary' : 'btn-secondary'}`}
                        style={{ flex: 1 }}
                        onClick={() => { setMode('login'); setError(''); }}
                        disabled={isSubmitting || authLoading}
                    >
                        Login
                    </button>
                    <button
                        type="button"
                        className={`btn ${mode === 'signup' ? 'btn-primary' : 'btn-secondary'}`}
                        style={{ flex: 1 }}
                        onClick={() => { setMode('signup'); setError(''); }}
                        disabled={isSubmitting || authLoading}
                    >
                        Sign Up
                    </button>
                </div>

                <form className="login-form" onSubmit={handleSubmit}>
                    {mode === 'signup' && (
                        <div className="form-group">
                            <label className="form-label">Display Name</label>
                            <input
                                type="text"
                                className="form-input"
                                value={displayName}
                                onChange={(e) => setDisplayName(e.target.value)}
                                placeholder="Display name"
                                required
                            />
                        </div>
                    )}
                    <div className="form-group">
                        <label className="form-label">Email</label>
                        <input
                            type="email"
                            className="form-input"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            placeholder="abc@gmail.com"
                            required
                        />
                    </div>
                    <div className="form-group">
                        <label className="form-label">Password</label>
                        <input
                            type="password"
                            className="form-input"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            placeholder="••••••••"
                            required
                        />
                    </div>
                    <button
                        type="submit"
                        className="btn btn-primary"
                        disabled={isSubmitting || (authLoading && !forceShow)}
                        style={{ width: '100%', justifyContent: 'center', padding: '12px' }}
                    >
                        {isSubmitting ? (
                            <Loader size={16} className="spin" />
                        ) : mode === 'login' ? (
                            'AUTHENTICATE'
                        ) : (
                            <><UserPlus size={16} style={{ marginRight: '8px' }} /> CREATE LEADER ACCOUNT</>
                        )}
                    </button>
                </form>

                <p style={{ textAlign: 'center', marginTop: '16px', fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                    {mode === 'signup' ? 'New accounts act as Game Leaders. Admins must assign your specific game later.' : 'Access restricted. Default role requires manual assignment.'}
                </p>

                <div style={{ borderTop: '1px solid var(--border)', marginTop: '16px', paddingTop: '16px', textAlign: 'center' }}>
                    <Link
                        to="/live"
                        className="btn btn-secondary"
                        style={{ width: '100%', justifyContent: 'center', padding: '10px', fontSize: '0.85rem', gap: '8px', textDecoration: 'none' }}
                    >
                        <Tv size={16} /> WATCH LIVE
                    </Link>
                </div>
            </div>
        </div>
    );
}
