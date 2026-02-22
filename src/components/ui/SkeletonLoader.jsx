import React from 'react';

export default function SkeletonLoader({ type = 'row', count = 1, className = '', style = {} }) {
    const renderSkeleton = () => {
        if (type === 'card') {
            return (
                <div className={`scanner-loader ${className}`} style={{ padding: 'var(--space-md)', ...style }}>
                    <div className="skeleton-pulse" style={{ height: '40px', borderRadius: '8px', marginBottom: '16px' }} />
                    <div className="skeleton-pulse" style={{ height: '20px', borderRadius: '4px', marginBottom: '8px', width: '80%' }} />
                    <div className="skeleton-pulse" style={{ height: '20px', borderRadius: '4px', width: '60%' }} />
                    <div className="scanner-text">&gt; INITIALIZING TOURNAMENT SYSTEMS...</div>
                </div>
            );
        }

        if (type === 'table') {
            return (
                <div className={`scanner-loader ${className}`} style={{ padding: 'var(--space-md)', ...style }}>
                    <div className="skeleton-pulse" style={{ height: '40px', borderRadius: '4px', marginBottom: '16px' }} />
                    {Array.from({ length: Math.max(1, count) }).map((_, i) => (
                        <div key={i} className="skeleton-pulse" style={{ height: '50px', borderRadius: '4px', marginBottom: '8px' }} />
                    ))}
                    <div className="scanner-text">&gt; INITIALIZING TOURNAMENT DATA...</div>
                </div>
            );
        }

        if (type === 'dashboard-stats') {
            return (
                <div className="stats-grid" style={style}>
                    {Array.from({ length: Math.max(1, count) }).map((_, i) => (
                        <div key={i} className="scanner-loader" style={{ padding: 'var(--space-md)' }}>
                            <div className="skeleton-pulse" style={{ height: '24px', width: '40px', borderRadius: '4px', marginBottom: '12px' }} />
                            <div className="skeleton-pulse" style={{ height: '36px', width: '80px', borderRadius: '4px', marginBottom: '8px' }} />
                            <div className="skeleton-pulse" style={{ height: '16px', width: '120px', borderRadius: '4px' }} />
                        </div>
                    ))}
                </div>
            );
        }

        // Default 'row' or 'box'
        return Array.from({ length: Math.max(1, count) }).map((_, i) => (
            <div key={i} className={`skeleton-pulse ${className}`} style={{ height: '20px', borderRadius: '4px', marginBottom: '8px', ...style }} />
        ));
    };

    return <>{renderSkeleton()}</>;
}
