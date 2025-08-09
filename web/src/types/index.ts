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
  params?: Record<string, any>;
  result?: any;
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
  type: 'agent_connected' | 'agent_disconnected' | 'agent_activity' | 'file_changed' | 'human_command_response';
  data: AgentConnection | AgentActivity | FileChange | HumanCommand;
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