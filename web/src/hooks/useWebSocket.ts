// WebSocket hook for real-time MCP server communication
import { useState, useEffect, useRef, useCallback } from 'react';
import type { 
  WebSocketEvent, 
  AgentConnection, 
  AgentActivity, 
  FileChange, 
  HumanCommand,
  SemanticSearchResult,
  DependencyAnalysis,
  CollaborationUpdate,
  PerformanceUpdate
} from '../types';

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
  
  // Algorithm data streams
  semanticSearchResults: SemanticSearchResult[];
  dependencyAnalyses: DependencyAnalysis[];
  collaborationUpdates: CollaborationUpdate[];
  performanceUpdates: PerformanceUpdate[];
  
  // Actions
  sendCommand: (command: string, targetAgents?: string[]) => void;
  sendSemanticSearch: (query: string) => void;
  requestDependencyAnalysis: (targetNode: string) => void;
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
const MAX_SEARCH_RESULTS = 100;
const MAX_DEPENDENCY_ANALYSES = 50;
const MAX_COLLABORATION_UPDATES = 200;
const MAX_PERFORMANCE_UPDATES = 100;

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
  
  // Algorithm data state
  const [semanticSearchResults, setSemanticSearchResults] = useState<SemanticSearchResult[]>([]);
  const [dependencyAnalyses, setDependencyAnalyses] = useState<DependencyAnalysis[]>([]);
  const [collaborationUpdates, setCollaborationUpdates] = useState<CollaborationUpdate[]>([]);
  const [performanceUpdates, setPerformanceUpdates] = useState<PerformanceUpdate[]>([]);
  
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

      case 'semantic_search_result':
        const searchResult = event.data as SemanticSearchResult;
        setSemanticSearchResults(prev => {
          const updated = [searchResult, ...prev];
          return updated.slice(0, MAX_SEARCH_RESULTS);
        });
        break;

      case 'dependency_analysis':
        const dependencyAnalysis = event.data as DependencyAnalysis;
        setDependencyAnalyses(prev => {
          const updated = [dependencyAnalysis, ...prev];
          return updated.slice(0, MAX_DEPENDENCY_ANALYSES);
        });
        break;

      case 'collaboration_update':
        const collaborationUpdate = event.data as CollaborationUpdate;
        setCollaborationUpdates(prev => {
          const updated = [collaborationUpdate, ...prev];
          return updated.slice(0, MAX_COLLABORATION_UPDATES);
        });
        break;

      case 'performance_metrics':
        const performanceUpdate = event.data as PerformanceUpdate;
        performanceUpdate.timestamp = event.timestamp;
        setPerformanceUpdates(prev => {
          const updated = [performanceUpdate, ...prev];
          return updated.slice(0, MAX_PERFORMANCE_UPDATES);
        });
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

  // Send semantic search request
  const sendSemanticSearch = useCallback((query: string) => {
    if (!connected || !ws.current) {
      setError('Not connected to server');
      return;
    }

    try {
      ws.current.send(JSON.stringify({
        type: 'semantic_search_request',
        data: { query, timestamp: new Date() }
      }));
    } catch (error) {
      console.error('[Observatory] Failed to send semantic search:', error);
      setError('Failed to send semantic search');
    }
  }, [connected]);

  // Request dependency analysis
  const requestDependencyAnalysis = useCallback((targetNode: string) => {
    if (!connected || !ws.current) {
      setError('Not connected to server');
      return;
    }

    try {
      ws.current.send(JSON.stringify({
        type: 'dependency_analysis_request',
        data: { targetNode, timestamp: new Date() }
      }));
    } catch (error) {
      console.error('[Observatory] Failed to request dependency analysis:', error);
      setError('Failed to request dependency analysis');
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
    semanticSearchResults,
    dependencyAnalyses,
    collaborationUpdates,
    performanceUpdates,
    sendCommand,
    sendSemanticSearch,
    requestDependencyAnalysis,
    reconnect,
    totalEvents,
    lastEventTime
  };
};