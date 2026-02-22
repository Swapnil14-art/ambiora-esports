// Simple in-memory cache for API responses
const cache = new Map();

// Default TTL is 5 minutes
const DEFAULT_TTL = 5 * 60 * 1000;

/**
 * Fetches data or retrieves it from cache.
 * @param {string} key - Unique cache key
 * @param {Function} fetcher - Async function that returns the data
 * @param {number} ttl - Time to live in milliseconds
 * @returns {Promise<any>}
 */
export const fetchWithCache = async (key, fetcher, ttl = DEFAULT_TTL) => {
    const cached = cache.get(key);
    const now = Date.now();

    if (cached && now - cached.timestamp < ttl) {
        return cached.data;
    }

    try {
        const data = await fetcher();
        cache.set(key, { data, timestamp: now });
        return data;
    } catch (error) {
        console.error(`Error fetching data for cache key ${key}:`, error);
        throw error;
    }
};

/**
 * Invalidates specific cache keys or starts with a prefix.
 * @param {string|Function} predicate - Key to remove or function that tests keys
 */
export const invalidateCache = (predicate) => {
    if (typeof predicate === 'string') {
        cache.delete(predicate);
        // Also try deleting anything that starts with this string if it looks like a prefix pattern
        for (const key of cache.keys()) {
            if (key.startsWith(predicate + ':')) {
                cache.delete(key);
            }
        }
    } else if (typeof predicate === 'function') {
        for (const key of cache.keys()) {
            if (predicate(key)) {
                cache.delete(key);
            }
        }
    } else {
        // Clear all if no predicate
        cache.clear();
    }
};

/**
 * Clears the entire cache.
 */
export const clearCache = () => {
    cache.clear();
};
