// Observatory type definitions for MCP server integration

export interface AgentConnection {
  id: string;
  name: string;
  status: 'connected' | 'disconnected' | 'active';
  lastActivity: Date;
}

export interface AgentActivity {
  id: string;
  agentId: string;
  agentName: string;
  tool: string;
  action: string;
  timestamp: Date;
  params?: Record<string, unknown>;
  result?: unknown;
  duration?: number;
  status: 'pending' | 'success' | 'error';
}

export interface FileChange {
  path: string;
  action: 'read' | 'write' | 'analyze';
  timestamp: Date;
  agentId: string;
  content?: string;
}

export interface HumanCommand {
  id: string;
  command: string;
  timestamp: Date;
  targetAgents?: string[];
  status: 'sent' | 'acknowledged' | 'completed' | 'error';
  response?: string;
}

export interface WebSocketEvent {
  type: 'agent_connected' | 'agent_disconnected' | 'agent_activity' | 'file_changed' | 'human_command_response' | 
        'semantic_search_result' | 'dependency_analysis' | 'collaboration_update' | 'performance_metrics';
  data: AgentConnection | AgentActivity | FileChange | HumanCommand | SemanticSearchResult | 
        DependencyAnalysis | CollaborationUpdate | PerformanceUpdate;
  timestamp: Date;
}

export interface ProjectFile {
  path: string;
  type: 'file' | 'directory';
  size?: number;
  modified?: Date;
  children?: ProjectFile[];
  lastAgent?: string;
  changeCount: number;
}

export interface PerformanceMetrics {
  agentCount: number;
  totalRequests: number;
  avgResponseTime: number;
  errorRate: number;
  throughput: number;
}

// Advanced Algorithm Types

export interface SemanticSearchResult {
  id: string;
  query: string;
  results: Array<{
    nodeId: string;
    content: string;
    similarity: number;
    distance: number;
    embedding: number[];
  }>;
  hnswStats: {
    searchTime: number;
    hopsCount: number;
    candidatesEvaluated: number;
  };
  agentId: string;
}

export interface DependencyNode {
  id: string;
  name: string;
  type: 'file' | 'function' | 'class' | 'module';
  filePath?: string;
  complexity: number;
  x?: number;
  y?: number;
  fx?: number | null;
  fy?: number | null;
}

export interface DependencyEdge {
  source: string | DependencyNode;
  target: string | DependencyNode;
  type: 'imports' | 'calls' | 'extends' | 'implements';
  weight: number;
}

export interface DependencyAnalysis {
  id: string;
  targetNode: string;
  nodes: DependencyNode[];
  edges: DependencyEdge[];
  freStats: {
    traversalTime: number;
    nodesVisited: number;
    pathsFound: number;
    complexity: string; // O(m log^(2/3) n)
  };
  impactPaths: Array<{
    path: string[];
    weight: number;
    impactScore: number;
  }>;
  agentId: string;
}

export interface CollaborationOperation {
  id: string;
  agentId: string;
  type: 'insert' | 'delete' | 'replace';
  position: number;
  content?: string;
  timestamp: Date;
  vectorClock: Record<string, number>;
}

export interface CollaborationUpdate {
  id: string;
  filePath: string;
  operations: CollaborationOperation[];
  conflicts: Array<{
    operationIds: string[];
    resolution: 'automatic' | 'manual';
    resolutionStrategy: string;
  }>;
  crdtStats: {
    operationTime: number;
    mergeTime: number;
    stateSize: number;
  };
  activeAgents: string[];
}

export interface AlgorithmPerformance {
  algorithm: 'hnsw' | 'fre' | 'crdt';
  operation: string;
  responseTime: number;
  complexity: string;
  dataSize: number;
  efficiency: number; // speedup multiplier vs naive approach
}

export interface PerformanceUpdate {
  id: string;
  timestamp: Date;
  hnswPerformance: {
    avgSearchTime: number;
    throughput: number;
    indexSize: number;
    speedupVsLinear: number;
  };
  frePerformance: {
    avgTraversalTime: number;
    throughput: number;
    graphSize: number;
    speedupVsDijkstra: number;
  };
  crdtPerformance: {
    avgOperationTime: number;
    avgMergeTime: number;
    operationThroughput: number;
    conflictRate: number;
  };
  systemMetrics: {
    memoryUsage: number;
    cpuUsage: number;
    activeConnections: number;
  };
}