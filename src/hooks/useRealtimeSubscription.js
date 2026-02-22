import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '../lib/supabase';

export function useRealtimeSubscription(table, filter = null) {
    const [data, setData] = useState([]);
    const [loading, setLoading] = useState(true);
    const channelRef = useRef(null);

    const fetchData = useCallback(async () => {
        let query = supabase.from(table).select('*');
        if (filter) {
            Object.entries(filter).forEach(([key, value]) => {
                query = query.eq(key, value);
            });
        }
        const { data: result, error } = await query.order('created_at', { ascending: false });
        if (error) {
            console.error(`Error fetching ${table}:`, error);
        } else {
            setData(result || []);
        }
        setLoading(false);
    }, [table, JSON.stringify(filter)]);

    useEffect(() => {
        fetchData();

        const channelName = `realtime-${table}-${JSON.stringify(filter || {})}`;
        const channel = supabase
            .channel(channelName)
            .on(
                'postgres_changes',
                {
                    event: '*',
                    schema: 'public',
                    table: table,
                },
                () => {
                    fetchData();
                }
            )
            .subscribe();

        channelRef.current = channel;

        return () => {
            if (channelRef.current) {
                supabase.removeChannel(channelRef.current);
            }
        };
    }, [fetchData]);

    return { data, loading, refetch: fetchData };
}

export function useRealtimeQuery(queryFn, deps = []) {
    const [data, setData] = useState([]);
    const [loading, setLoading] = useState(true);

    const fetchData = useCallback(async () => {
        setLoading(true);
        try {
            const result = await queryFn();
            setData(result || []);
        } catch (err) {
            console.error('Query error:', err);
        }
        setLoading(false);
    }, deps);

    useEffect(() => {
        fetchData();
    }, [fetchData]);

    return { data, loading, refetch: fetchData };
}
