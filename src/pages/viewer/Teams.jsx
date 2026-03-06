import { useState, useEffect } from 'react';
import { supabase } from '../../lib/supabase';
import { fetchWithCache, hasValidCache } from '../../lib/cache';
import { Users, Gamepad2, Shield, ShieldX } from 'lucide-react';
import SkeletonLoader from '../../components/ui/SkeletonLoader';

export default function ViewerTeams() {
    const [games, setGames] = useState([]);
    const [teamsByGame, setTeamsByGame] = useState({});
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        if (!hasValidCache('public_games') || !hasValidCache('public_teams')) {
            setLoading(true);
        }

        try {
            const [gamesRes, teamsRes] = await Promise.all([
                fetchWithCache('public_games', async () => await supabase.from('games').select('*').order('name')),
                fetchWithCache('public_teams', async () => await supabase.from('teams').select('*, game:games(name, slug)'))
            ]);

            const gamesData = gamesRes.data || [];
            const teamsData = teamsRes.data || [];

            const grouped = {};
            gamesData.forEach(g => {
                grouped[g.id] = teamsData.filter(t => t.game_id === g.id);
            });

            setGames(gamesData);
            setTeamsByGame(grouped);
        } catch (error) {
            console.error("Error fetching teams data:", error);
        }
        setLoading(false);
    };

    if (loading) {
        return <div style={{ padding: 'var(--space-xl)' }}><SkeletonLoader type="card" count={4} /></div>;
    }

    return (
        <div>
            <div style={{ position: 'relative', overflowX: 'hidden' }}>
                {/* HER0 SECTION */}
                <div style={{
                    position: 'relative',
                    padding: 'var(--space-2xl) var(--space-xl)',
                    marginBottom: 'var(--space-2xl)',
                    background: 'linear-gradient(180deg, rgba(181, 55, 242, 0.15) 0%, transparent 100%)',
                    borderBottom: '1px solid var(--border-primary)',
                    overflow: 'hidden',
                    marginTop: '-var(--topbar-height)', /* Pull up behind the translucent nav if it exists */
                    paddingTop: 'calc(var(--topbar-height) + var(--space-2xl))'
                }}>
                    {/* Animated grid overlay */}
                    <div style={{
                        position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                        backgroundImage: 'linear-gradient(var(--border-secondary) 1px, transparent 1px), linear-gradient(90deg, var(--border-secondary) 1px, transparent 1px)',
                        backgroundSize: '40px 40px',
                        opacity: 0.2,
                        transform: 'perspective(500px) rotateX(60deg) translateY(-100px) translateZ(-200px)',
                        transformOrigin: 'top center',
                        animation: 'scanningLine 10s infinite linear'
                    }}></div>

                    <div style={{ position: 'relative', zIndex: 2, display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)', marginBottom: 'var(--space-md)' }}>
                            <span style={{ display: 'inline-block', width: 10, height: 10, borderRadius: '50%', background: 'var(--neon-red)', animation: 'pulse-live 2s infinite' }}></span>
                            <span style={{ color: 'var(--neon-red)', fontFamily: 'var(--font-display)', fontWeight: 700, letterSpacing: '2px', fontSize: '0.8rem' }}>EVENT LIVE</span>
                        </div>
                        <h1 style={{ fontSize: '3.5rem', fontWeight: 900, letterSpacing: '2px', marginBottom: 'var(--space-sm)', textShadow: '0 0 20px rgba(181, 55, 242, 0.4)' }}>
                            AMBIORA ESPORTS
                        </h1>
                        <p style={{ color: 'var(--neon-cyan)', fontSize: '1.2rem', fontFamily: 'var(--font-display)', letterSpacing: '1px', textTransform: 'uppercase' }}>
                            Official Tournament Register
                        </p>
                    </div>
                </div>

                <div style={{ padding: '0 var(--space-xl)' }}>
                    {games.map((game, index) => {
                        // Determine accent color
                        let accentColor = 'var(--neon-purple)';
                        let gameStyle = {};
                        const slug = game.slug.toLowerCase();
                        if (slug === 'valorant') { accentColor = 'var(--game-valorant)'; gameStyle = { borderTop: `2px solid ${accentColor}` }; }
                        if (slug === 'bgmi') { accentColor = 'var(--game-bgmi)'; gameStyle = { borderTop: `2px solid ${accentColor}` }; }
                        if (slug === 'fifa-25') { accentColor = 'var(--game-fifa)'; gameStyle = { borderTop: `2px solid ${accentColor}` }; }
                        if (slug === 'f1') { accentColor = 'var(--game-f1)'; gameStyle = { borderTop: `2px solid ${accentColor}` }; }

                        const staggerClass = `stagger-${Math.min(index + 1, 5)}`;

                        return (
                            <section key={game.id} className={staggerClass} style={{ marginBottom: 'var(--space-2xl)', padding: 'var(--space-lg) 0', ...gameStyle }}>
                                <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-sm)', marginBottom: 'var(--space-lg)' }}>
                                    <Gamepad2 size={28} style={{ color: accentColor }} />
                                    <h2 style={{ fontFamily: 'var(--font-display)', fontSize: '2rem', m: 0, color: '#fff', textShadow: `0 0 10px ${accentColor}40` }}>
                                        {game.name}
                                    </h2>
                                    <span className="badge badge-admin" style={{ marginLeft: 'var(--space-md)', background: `${accentColor}20`, color: accentColor, borderColor: accentColor }}>
                                        {teamsByGame[game.id]?.length || 0} CONTENDERS
                                    </span>
                                </div>

                                {teamsByGame[game.id]?.length === 0 ? (
                                    <div className="card empty-state clip-angle" style={{ background: 'rgba(255,255,255,0.02)', borderLeft: `2px solid ${accentColor}` }}>
                                        <Users size={32} style={{ color: 'var(--text-muted)', marginBottom: 'var(--space-sm)' }} />
                                        <p style={{ fontFamily: 'var(--font-display)', textTransform: 'uppercase', letterSpacing: '1px' }}>Awaiting Registrations.</p>
                                    </div>
                                ) : (
                                    <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 300px), 1fr))' }}>
                                        {teamsByGame[game.id].map((team, tIndex) => {
                                            const isDQ = team.status === 'disqualified';
                                            return (
                                                <div key={team.id} className={`card hud-card clip-angle hover-parallax stagger-${Math.min(tIndex + 1, 5)}`} style={{ padding: 'var(--space-md)', borderLeft: `4px solid ${isDQ ? 'var(--neon-red)' : accentColor}`, opacity: isDQ ? 0.55 : 1 }}>
                                                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 'var(--space-sm)' }}>
                                                        <div style={{ fontWeight: 800, fontSize: '1.2rem', fontFamily: 'var(--font-display)', textTransform: 'uppercase', color: isDQ ? 'var(--text-muted)' : '#fff', textDecoration: isDQ ? 'line-through' : 'none' }}>
                                                            {team.team_name}
                                                        </div>
                                                        {isDQ ? (
                                                            <ShieldX size={16} style={{ color: 'var(--neon-red)' }} title="Disqualified" />
                                                        ) : (
                                                            <Shield size={16} style={{ color: accentColor }} title="Qualified" />
                                                        )}
                                                    </div>
                                                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '4px' }}>
                                                        <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '1px' }}>
                                                            Est. {new Date(team.created_at).getFullYear()}
                                                        </div>
                                                        <div style={{ fontSize: '0.7rem', color: isDQ ? 'var(--neon-red)' : accentColor, fontFamily: 'var(--font-display)', letterSpacing: '1px', textAlign: 'right', flex: '1 1 auto', paddingRight: '8px' }}>
                                                            {isDQ ? 'DISQUALIFIED' : 'QUALIFIED'}
                                                        </div>
                                                    </div>
                                                </div>
                                            );
                                        })}
                                    </div>
                                )}
                            </section>
                        );
                    })}
                </div>
            </div>
        </div>
    );
}
