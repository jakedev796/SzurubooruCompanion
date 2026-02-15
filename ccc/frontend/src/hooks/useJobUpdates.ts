import { useEffect, useRef, useCallback } from "react";
import { getSSEUrl } from "../api";

let activeConnectionCount = 0;
const MAX_CONNECTIONS = 3;

export function useJobUpdates(
  onJobUpdate: (payload: Record<string, unknown>) => void,
  jobId: string | null = null
): void {
  const eventSourceRef = useRef<EventSource | null>(null);
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const onJobUpdateRef = useRef(onJobUpdate);
  const isConnectingRef = useRef(false);

  useEffect(() => {
    onJobUpdateRef.current = onJobUpdate;
  }, [onJobUpdate]);

  const connect = useCallback(() => {
    if (isConnectingRef.current) return;
    if (activeConnectionCount >= MAX_CONNECTIONS) {
      console.warn("Too many SSE connections, skipping connection attempt");
      return;
    }

    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      activeConnectionCount = Math.max(0, activeConnectionCount - 1);
    }

    isConnectingRef.current = true;
    const url = getSSEUrl(jobId);
    const eventSource = new EventSource(url);
    eventSourceRef.current = eventSource;
    activeConnectionCount++;

    eventSource.addEventListener("connected", () => {
      isConnectingRef.current = false;
    });

    eventSource.addEventListener("job_update", (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data) as Record<string, unknown>;
        onJobUpdateRef.current(data);
      } catch (e) {
        console.error("Failed to parse SSE job_update message:", e);
      }
    });

    eventSource.onmessage = (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data) as Record<string, unknown>;
        if (data.job_id !== undefined) {
          onJobUpdateRef.current(data);
        }
      } catch {
        // ignore
      }
    };

    eventSource.onerror = () => {
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
