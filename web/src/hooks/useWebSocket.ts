// WebSocket hook for real-time MCP server communication
import { useState, useEffect, useRef, useCallback } from 'react';
import type { WebSocketEvent, AgentConnection, AgentActivity, FileChange, HumanCommand } from '../types';

interface UseWebSocketReturn {
  // Connection state
  connected: boolean;
  connecting: boolean;
  error: string | null;
  
  // Data streams
  agents: Map<string, AgentConnection>;
  activities: AgentActivity[];
  fileChanges: FileChange[];
  commands: HumanCommand[];
  
  // Actions
  sendCommand: (command: string, targetAgents?: string[]) => void;
  reconnect: () => void;
  
  // Metrics
  totalEvents: number;
  lastEventTime: Date | null;
}

const WS_URL = 'ws://localhost:8080';
const RECONNECT_INTERVAL = 3000;
const MAX_ACTIVITIES = 1000;
const MAX_FILE_CHANGES = 500;
const MAX_COMMANDS = 100;

export const useWebSocket = (): UseWebSocketReturn => {
  // Connection state
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  // Data state
  const [agents, setAgents] = useState<Map<string, AgentConnection>>(new Map());
  const [activities, setActivities] = useState<AgentActivity[]>([]);
  const [fileChanges, setFileChanges] = useState<FileChange[]>([]);
  const [commands, setCommands] = useState<HumanCommand[]>([]);
  const [totalEvents, setTotalEvents] = useState(0);
  const [lastEventTime, setLastEventTime] = useState<Date | null>(null);
  
  // WebSocket reference
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<number | null>(null);
  const commandIdCounter = useRef(0);
  
  // Connect to WebSocket
  const connect = useCallback(() => {
    if (ws.current?.readyState === WebSocket.OPEN) return;
    
    setConnecting(true);
    setError(null);
    
    try {
      ws.current = new WebSocket(WS_URL);
      
      ws.current.onopen = () => {
        console.log('[Observatory] WebSocket connected');
        setConnected(true);
        setConnecting(false);
        setError(null);
        
        // Clear any pending reconnection
        if (reconnectTimeoutRef.current) {
          clearTimeout(reconnectTimeoutRef.current);
          reconnectTimeoutRef.current = null;
        }
      };
      
      ws.current.onmessage = (event) => {
        try {
          const wsEvent: WebSocketEvent = JSON.parse(event.data);
          wsEvent.timestamp = new Date(wsEvent.timestamp);
          
          setTotalEvents(prev => prev + 1);
          setLastEventTime(wsEvent.timestamp);
          
          handleWebSocketEvent(wsEvent);
        } catch (error) {
          console.error('[Observatory] Failed to parse WebSocket message:', error);
        }
      };
      
      ws.current.onclose = (event) => {
        console.log('[Observatory] WebSocket closed:', event.code, event.reason);
        setConnected(false);
        setConnecting(false);
        
        // Auto-reconnect unless explicitly closed
        if (event.code !== 1000) {
          setError('Connection lost');
          scheduleReconnect();
        }
      };
      
      ws.current.onerror = (error) => {
        console.error('[Observatory] WebSocket error:', error);
        setError('Connection error');
        setConnecting(false);
      };
      
    } catch (error) {
      console.error('[Observatory] Failed to create WebSocket:', error);
      setError('Failed to connect');
      setConnecting(false);
      scheduleReconnect();
    }
  }, []);
  
  // Schedule reconnection
  const scheduleReconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) return;
    
    reconnectTimeoutRef.current = window.setTimeout(() => {
      reconnectTimeoutRef.current = null;
      connect();
    }, RECONNECT_INTERVAL);
  }, [connect]);
  
  // Handle incoming WebSocket events
  const handleWebSocketEvent = useCallback((event: WebSocketEvent) => {
    switch (event.type) {
      case 'agent_connected':
        setAgents(prev => {
          const updated = new Map(prev);
          const agent = event.data as AgentConnection;
          agent.lastActivity = event.timestamp;
          updated.set(agent.id, agent);
          return updated;
        });
        break;
        
      case 'agent_disconnected':
        setAgents(prev => {
          const updated = new Map(prev);
          const agent = event.data as AgentConnection;
          if (updated.has(agent.id)) {
            updated.set(agent.id, { ...agent, status: 'disconnected', lastActivity: event.timestamp });
          }
          return updated;
        });
        break;
        
      case 'agent_activity':
        const activity = event.data as AgentActivity;
        activity.timestamp = event.timestamp;
        
        setActivities(prev => {
          const updated = [activity, ...prev];
          return updated.slice(0, MAX_ACTIVITIES);
        });
        
        // Update agent status
        setAgents(prev => {
          const updated = new Map(prev);
          if (updated.has(activity.agentId)) {
            const agent = updated.get(activity.agentId)!;
            updated.set(activity.agentId, { ...agent, status: 'active', lastActivity: event.timestamp });
          }
          return updated;
        });
        break;
        
      case 'file_changed':
        const fileChange = event.data as FileChange;
        fileChange.timestamp = event.timestamp;
        
        setFileChanges(prev => {
          const updated = [fileChange, ...prev];
          return updated.slice(0, MAX_FILE_CHANGES);
        });
        break;
        
      case 'human_command_response':
        const commandResponse = event.data as HumanCommand;
        commandResponse.timestamp = event.timestamp;
        
        setCommands(prev => prev.map(cmd => 
          cmd.id === commandResponse.id ? { ...cmd, ...commandResponse } : cmd
        ));
        break;
    }
  }, []);
  
  // Send human command to agents
  const sendCommand = useCallback((command: string, targetAgents?: string[]) => {
    if (!connected || !ws.current) {
      setError('Not connected to server');
      return;
    }
    
    const commandId = `cmd_${++commandIdCounter.current}`;
    const humanCommand: HumanCommand = {
      id: commandId,
      command,
      timestamp: new Date(),
      targetAgents,
      status: 'sent'
    };
    
    try {
      ws.current.send(JSON.stringify({
        type: 'human_command',
        data: humanCommand
      }));
      
      setCommands(prev => {
        const updated = [humanCommand, ...prev];
        return updated.slice(0, MAX_COMMANDS);
      });
      
    } catch (error) {
      console.error('[Observatory] Failed to send command:', error);
      setError('Failed to send command');
    }
  }, [connected]);
  
  // Manual reconnection
  const reconnect = useCallback(() => {
    if (ws.current) {
      ws.current.close(1000, 'Manual reconnect');
    }
    connect();
  }, [connect]);
  
  // Initialize connection on mount
  useEffect(() => {
    connect();
    
    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (ws.current) {
        ws.current.close(1000, 'Component unmount');
      }
    };
  }, [connect]);
  
  return {
    connected,
    connecting,
    error,
    agents,
    activities,
    fileChanges,
    commands,
    sendCommand,
    reconnect,
    totalEvents,
    lastEventTime
  };
};