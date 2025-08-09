// Agent status and performance metrics display
import React, { useMemo } from 'react';
import type { AgentConnection, AgentActivity } from '../types';

interface AgentStatusProps {
  agents: Map<string, AgentConnection>;
  activities: AgentActivity[];
  totalEvents: number;
  lastEventTime: Date | null;
  connected: boolean;
}

interface AgentMetrics {
  totalRequests: number;
  successRate: number;
  avgResponseTime: number;
  lastActivity: Date | null;
}

export const AgentStatus: React.FC<AgentStatusProps> = ({
  agents,
  activities,
  totalEvents,
  lastEventTime,
  connected
}) => {
  
  const agentMetrics = useMemo(() => {
    const metrics = new Map<string, AgentMetrics>();
    
    agents.forEach((_, agentId) => {
      const agentActivities = activities.filter(activity => activity.agentId === agentId);
      
      const totalRequests = agentActivities.length;
      const successfulRequests = agentActivities.filter(a => a.status === 'success').length;
      const successRate = totalRequests > 0 ? (successfulRequests / totalRequests) * 100 : 0;
      
      const completedActivities = agentActivities.filter(a => a.duration !== undefined);
      const avgResponseTime = completedActivities.length > 0
        ? completedActivities.reduce((sum, a) => sum + (a.duration || 0), 0) / completedActivities.length
        : 0;
      
      const lastActivity = agentActivities.length > 0 
        ? agentActivities[0].timestamp 
        : null;
      
      metrics.set(agentId, {
        totalRequests,
        successRate,
        avgResponseTime,
        lastActivity
      });
    });
    
    return metrics;
  }, [agents, activities]);
  
  const overallMetrics = useMemo(() => {
    const allMetrics = Array.from(agentMetrics.values());
    const totalRequests = allMetrics.reduce((sum, m) => sum + m.totalRequests, 0);
    const avgSuccessRate = allMetrics.length > 0 
      ? allMetrics.reduce((sum, m) => sum + m.successRate, 0) / allMetrics.length 
      : 0;
    const avgResponseTime = allMetrics.length > 0
      ? allMetrics.reduce((sum, m) => sum + m.avgResponseTime, 0) / allMetrics.length
      : 0;
    
    return { totalRequests, avgSuccessRate, avgResponseTime };
  }, [agentMetrics]);
  
  const getStatusIcon = (status: AgentConnection['status']) => {
    switch (status) {
      case 'connected': return '🟢';
      case 'active': return '🔄';
      case 'disconnected': return '🔴';
      default: return '⚪';
    }
  };
  
  const formatTime = (date: Date | null) => {
    if (!date) return 'Never';
    const now = Date.now();
    const diff = now - date.getTime();
    
    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    return date.toLocaleDateString();
  };
  
  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${Math.round(ms)}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };
  
  const activeAgents = Array.from(agents.values()).filter(agent => 
    agent.status === 'connected' || agent.status === 'active'
  );
  
  return (
    <div className="agent-status">
      <div className="status-header">
        <h3>Agent Status</h3>
        <div className="connection-indicator">
          {connected ? (
            <span className="connected">🟢 Observatory Online</span>
          ) : (
            <span className="disconnected">🔴 Observatory Offline</span>
          )}
        </div>
      </div>
      
      {/* Overall Metrics */}
      <div className="overall-metrics">
        <div className="metric-item">
          <div className="metric-value">{agents.size}</div>
          <div className="metric-label">Total Agents</div>
        </div>
        <div className="metric-item">
          <div className="metric-value">{activeAgents.length}</div>
          <div className="metric-label">Active</div>
        </div>
        <div className="metric-item">
          <div className="metric-value">{totalEvents}</div>
          <div className="metric-label">Total Events</div>
        </div>
        <div className="metric-item">
          <div className="metric-value">{Math.round(overallMetrics.avgSuccessRate)}%</div>
          <div className="metric-label">Success Rate</div>
        </div>
        <div className="metric-item">
          <div className="metric-value">{formatDuration(overallMetrics.avgResponseTime)}</div>
          <div className="metric-label">Avg Response</div>
        </div>
        <div className="metric-item">
          <div className="metric-value">{formatTime(lastEventTime)}</div>
          <div className="metric-label">Last Event</div>
        </div>
      </div>
      
      {/* Agent List */}
      <div className="agent-list">
        {agents.size === 0 ? (
          <div className="no-agents">
            No agents connected. Start an MCP client to see agents here.
          </div>
        ) : (
          Array.from(agents.values()).map(agent => {
            const metrics = agentMetrics.get(agent.id);
            return (
              <div key={agent.id} className={`agent-item ${agent.status}`}>
                <div className="agent-header">
                  <span className="agent-icon">{getStatusIcon(agent.status)}</span>
                  <span className="agent-name">{agent.name}</span>
                  <span className="agent-id">{agent.id}</span>
                </div>
                
                {metrics && (
                  <div className="agent-metrics">
                    <div className="agent-metric">
                      <span className="metric-label">Requests:</span>
                      <span className="metric-value">{metrics.totalRequests}</span>
                    </div>
                    <div className="agent-metric">
                      <span className="metric-label">Success:</span>
                      <span className="metric-value">{Math.round(metrics.successRate)}%</span>
                    </div>
                    <div className="agent-metric">
                      <span className="metric-label">Avg Time:</span>
                      <span className="metric-value">{formatDuration(metrics.avgResponseTime)}</span>
                    </div>
                    <div className="agent-metric">
                      <span className="metric-label">Last:</span>
                      <span className="metric-value">{formatTime(metrics.lastActivity)}</span>
                    </div>
                  </div>
                )}
                
                <div className="agent-footer">
                  <span className="agent-last-seen">
                    Last seen: {formatTime(agent.lastActivity)}
                  </span>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};