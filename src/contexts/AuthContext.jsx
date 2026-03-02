import { createContext, useContext, useState, useEffect, useRef } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);

    // Track whether initAuth is still running so onAuthStateChange doesn't duplicate work
    const initRunning = useRef(true);

    // Global safety net: never stuck loading > 8s
    useEffect(() => {
        let timer;
        if (loading) {
            timer = setTimeout(() => {
                console.warn('[Auth] Global loading timeout reached (8s). Forcing loading to false.');
                setLoading(false);
            }, 8000);
        }
        return () => clearTimeout(timer);
    }, [loading]);

    const fetchProfile = async (userId) => {
        try {
            const fetchPromise = supabase
                .from('profiles')
                .select('*')
                .eq('id', userId)
                .single();

            const timeoutPromise = new Promise((_, reject) =>
                setTimeout(() => reject(new Error('Profile fetch timeout')), 5000)
            );

            const { data } = await Promise.race([fetchPromise, timeoutPromise]);
            if (data) return data;
        } catch (err) {
            console.error('[Auth] Fetch profile error:', err);
        }
        return null;
    };

    useEffect(() => {
        let mounted = true;

        async function initAuth() {
            if (mounted) setLoading(true);
            try {
                const sessionPromise = supabase.auth.getSession();
                const timeoutPromise = new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Session fetch timeout')), 5000)
                );

                const result = await Promise.race([sessionPromise, timeoutPromise]);
                const session = result?.data?.session;

                if (session?.user) {
                    if (mounted) setUser(session.user);
                    const p = await fetchProfile(session.user.id);
                    if (mounted) setProfile(p);
                }
            } catch (err) {
                console.error('[Auth] Init error/timeout:', err);
            } finally {
                // Mark init as done BEFORE setting loading false
                initRunning.current = false;
                if (mounted) setLoading(false);
            }
        }

        initAuth();

        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            async (event, session) => {
                if (event === 'SIGNED_OUT') {
                    if (mounted) {
                        setUser(null);
                        setProfile(null);
                        setLoading(false);
                    }
                    return;
                }

                // CRITICAL FIX: If initAuth is still running, it will handle the profile fetch.
                // The SIGNED_IN event fires during init and would cause a duplicate fetch.
                if (initRunning.current && event === 'SIGNED_IN') {
                    return;
                }

                if ((event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') && session?.user) {
                    if (mounted) setUser(session.user);

                    try {
                        const p = await fetchProfile(session.user.id);
                        if (mounted && p) {
                            setProfile(p);
                        }
                        if (mounted) setLoading(false);
                    } catch (err) {
                        console.error('[Auth] Background profile refresh failed', err);
                        if (mounted) setLoading(false);
                    }
                }
            }
        );

        return () => {
            mounted = false;
            subscription.unsubscribe();
        };
    }, []);

    const login = async (email, password) => {
        setLoading(true);
        try {
            const loginPromise = supabase.auth.signInWithPassword({ email, password });
            const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error('Login request timed out')), 10000));

            const { data, error } = await Promise.race([loginPromise, timeoutPromise]);
            if (error) throw error;

            setUser(data.user);
            const p = await fetchProfile(data.user.id);
            setProfile(p);

            return { user: data.user, profile: p };
        } finally {
            setLoading(false);
        }
    };

    const refreshProfile = async () => {
        if (!user) return;
        try {
            const p = await fetchProfile(user.id);
            if (p) setProfile(p);
        } catch (err) {
            console.error('Failed to refresh profile:', err);
        }
    };

    const signup = async (email, password, displayName, role) => {
        setLoading(true);
        try {
            const { supabaseAdmin } = await import('../lib/supabase');
            if (!supabaseAdmin) throw new Error("Service role key missing. Cannot use admin signup.");

            const { data, error } = await supabaseAdmin.auth.admin.createUser({
                email,
                password,
                email_confirm: true,
                user_metadata: {
                    display_name: displayName,
                    role: role || 'game_leader'
                }
            });

            if (error) throw error;
            if (!data.user) throw new Error("Supabase returned no user object upon signup.");

            // Wait briefly for Postgres Trigger to insert profile row
            await new Promise(r => setTimeout(r, 1000));

            return await login(email, password);
        } finally {
            setLoading(false);
        }
    };

    const logout = async () => {
        setLoading(true);
        try {
            await Promise.race([
                supabase.auth.signOut(),
                new Promise(r => setTimeout(r, 2000))
            ]);
        } catch (e) {
            console.error('Logout error:', e);
        } finally {
            setUser(null);
            setProfile(null);
            setLoading(false);
        }
    };

    const isAdmin = profile?.role === 'admin';
    const isGameLeader = profile?.role === 'game_leader';
    const isViewer = profile?.role === 'viewer';
    const isPlayer = profile?.role === 'player';

    return (
        <AuthContext.Provider value={{
            user,
            profile,
            loading,
            login,
            signup,
            logout,
            setProfile,
            refreshProfile,
            isAdmin,
            isGameLeader,
            isViewer,
            isPlayer,
        }}>
            {children}
        </AuthContext.Provider>
    );
}

export const useAuth = () => {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error('useAuth must be used within AuthProvider');
    return ctx;
};
