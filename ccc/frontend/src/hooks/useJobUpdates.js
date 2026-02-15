import { useEffect, useRef, useCallback } from 'react';
import { getSSEUrl } from '../api.js';

// Global connection tracker to prevent duplicate connections
let activeConnectionCount = 0;
const MAX_CONNECTIONS = 3;

/**
 * Custom hook for subscribing to job updates via SSE
 * @param {Function} onJobUpdate - Callback when a job is updated
 * @param {string|null} jobId - Optional specific job ID to filter for
 */
export function useJobUpdates(onJobUpdate, jobId = null) {
  const eventSourceRef = useRef(null);
  const reconnectTimeoutRef = useRef(null);
  const onJobUpdateRef = useRef(onJobUpdate);
  const isConnectingRef = useRef(false);

  // Keep callback ref updated
  useEffect(() => {
    onJobUpdateRef.current = onJobUpdate;
  }, [onJobUpdate]);

  const connect = useCallback(() => {
    // Prevent multiple simultaneous connection attempts
    if (isConnectingRef.current) {
      return;
    }

    // Check for too many active connections (prevents connection leak)
    if (activeConnectionCount >= MAX_CONNECTIONS) {
      console.warn('Too many SSE connections, skipping connection attempt');
      return;
    }

    // Close existing connection
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      activeConnectionCount = Math.max(0, activeConnectionCount - 1);
    }

    isConnectingRef.current = true;

    // Use the helper to get the full URL with API base
    const url = getSSEUrl(jobId);
    
    const eventSource = new EventSource(url);
    eventSourceRef.current = eventSource;
    activeConnectionCount++;

    // Handle the "connected" event
    eventSource.addEventListener('connected', (event) => {
      console.log('SSE connected');
      isConnectingRef.current = false;
    });

    // Handle the "job_update" event (named event from backend)
    eventSource.addEventListener('job_update', (event) => {
      try {
        const data = JSON.parse(event.data);
        onJobUpdateRef.current(data);
      } catch (e) {
        console.error('Failed to parse SSE job_update message:', e);
      }
    });

    // Handle generic messages (fallback for any onmessage events)
    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        // Only process if it looks like a job update
        if (data.job_id !== undefined) {
          onJobUpdateRef.current(data);
        }
      } catch (e) {
        // Ignore parse errors for non-JSON messages (e.g., heartbeats)
      }
    };

    eventSource.onerror = () => {
      console.log('SSE connection lost, reconnecting in 3s...');
      isConnectingRef.current = false;
      eventSource.close();
      activeConnectionCount = Math.max(0, activeConnectionCount - 1);
      reconnectTimeoutRef.current = setTimeout(connect, 3000);
    };
  }, [jobId]);

  useEffect(() => {
    connect();

    return () => {
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        activeConnectionCount = Math.max(0, activeConnectionCount - 1);
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
    };
  }, [connect]);
}
