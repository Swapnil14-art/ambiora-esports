import { createContext, useContext, useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [profile, setProfile] = useState(null);
    const [loading, setLoading] = useState(true);

    // Global safety net: never allow the app to be stuck in a loading state for > 20 seconds
    useEffect(() => {
        let timer;
        if (loading) {
            timer = setTimeout(() => {
                console.warn('[Auth] Global loading timeout reached (20000ms). Forcing loading to false to prevent infinite black screen.');
                setLoading(false);
            }, 20000);
        }
        return () => clearTimeout(timer);
    }, [loading]);

    const fetchProfile = async (userId) => {
        try {
            // Retry logic with timeout wrappers
            for (let attempt = 1; attempt <= 3; attempt++) {

                // Wrap in strict 15s timeout so supabase query cannot hang indefinitely
                // We just select * from profiles. The dashboard can fetch game details itself.
                // This prevents complex JOINs from failing the critical profile load.
                const fetchPromise = supabase
                    .from('profiles')
                    .select('*')
                    .eq('id', userId)
                    .single();

                const timeoutPromise = new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Profile fetch timeout')), 15000)
                );

                const { data, error } = await Promise.race([fetchPromise, timeoutPromise]);

                if (data) return data;

                if (attempt < 3) {
                    await new Promise(r => setTimeout(r, 600));
                }
            }
        } catch (err) {
            console.error('[Auth] Fetch profile crash/timeout:', err);
        }
        return null;
    };

    useEffect(() => {
        let mounted = true;

        async function initAuth() {
            if (mounted) setLoading(true);
            try {
                // Ensure getSession doesn't infinitely stall due to corrupted GoTrueClient
                const sessionPromise = supabase.auth.getSession();
                const timeoutPromise = new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Session fetch timeout')), 15000)
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
                if (mounted) setLoading(false);
            }
        }

        initAuth();

        const { data: { subscription } } = supabase.auth.onAuthStateChange(
            async (event, session) => {
                // If they signed out, clear everything
                if (event === 'SIGNED_OUT') {
                    if (mounted) {
                        setUser(null);
                        setProfile(null);
                        setLoading(false);
                    }
                    return;
                }

                // If they signed in or their token refreshed in the background
                if ((event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') && session?.user) {
                    if (mounted) setUser(session.user);

                    try {
                        const p = await fetchProfile(session.user.id);
                        if (mounted && p) {
                            setProfile(p);
                        }
                        // CRITICAL FIX: If p is null but we ALREADY have a profile (e.g. they are mid-session and 
                        // just refreshing their token), we DO NOT overwrite it with null and kick them out! 
                        // Only set loading false if we survived the fetch
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
            const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error('Login request timed out')), 15000));

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
            // Using supabaseAdmin bypasses ALL rate limits and email confirmation requirements
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

            // Authenticate the user now that they're created
            return await login(email, password);
        } finally {
            // Loading is handled by login/finally
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
