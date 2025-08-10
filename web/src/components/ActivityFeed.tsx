// Real-time agent activity feed component
import React, { useMemo } from 'react';
import type { AgentActivity, AgentConnection } from '../types';

interface ActivityFeedProps {
  activities: AgentActivity[];
  agents: Map<string, AgentConnection>;
  maxItems?: number;
}

interface ActivityItemProps {
  activity: AgentActivity;
  agentName: string;
}

const ActivityItem: React.FC<ActivityItemProps> = ({ activity, agentName }) => {
  const getStatusIcon = () => {
    switch (activity.status) {
      case 'success': return '✅';
      case 'error': return '❌';
      case 'pending': return '⏳';
      default: return '⚪';
    }
  };
  
  const getToolIcon = () => {
    switch (activity.tool) {
      case 'read_code': return '📖';
      case 'write_code': return '✏️';
      case 'get_context': return '🔍';
      case 'analyze_dependencies': return '📊';
      case 'record_decision': return '📝';
      default: return '🔧';
    }
  };
  
  const formatDuration = (ms: number | undefined) => {
    if (!ms) return '';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };
  
  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', { 
      hour12: false, 
      hour: '2-digit', 
      minute: '2-digit', 
      second: '2-digit' 
    });
  };
  
  const getActivityDescription = () => {
    const { tool, action, params } = activity;
    
    switch (tool) {
      case 'read_code':
        return `read ${params?.file_path || 'file'}`;
      case 'write_code':
        return `wrote to ${params?.file_path || 'file'}`;
      case 'get_context':
        return `analyzed context for ${params?.query || 'query'}`;
      case 'analyze_dependencies':
        return `analyzed dependencies of ${params?.target || 'target'}`;
      case 'record_decision':
        return `recorded decision: ${params?.decision || 'decision'}`;
      default:
        return action || 'performed action';
    }
  };
  
  return (
    <div className="activity-item">
      <div className="activity-header">
        <span className="activity-status">{getStatusIcon()}</span>
        <span className="activity-tool">{getToolIcon()}</span>
        <span className="activity-agent">{agentName}</span>
        <span className="activity-time">{formatTime(activity.timestamp)}</span>
        {activity.duration && (
          <span className="activity-duration">{formatDuration(activity.duration)}</span>
        )}
      </div>
      <div className="activity-description">
        {getActivityDescription()}
      </div>
      {activity.status === 'error' && activity.result && (
        <div className="activity-error">
          Error: {activity.result.error || 'Unknown error'}
        </div>
      )}
    </div>
  );
};

export const ActivityFeed: React.FC<ActivityFeedProps> = ({ 
  activities, 
  agents, 
  maxItems = 50 
}) => {
  const displayActivities = useMemo(() => {
    return activities.slice(0, maxItems);
  }, [activities, maxItems]);
  
  const getAgentName = (agentId: string) => {
    return agents.get(agentId)?.name || agentId;
  };
  
  if (displayActivities.length === 0) {
    return (
      <div className="activity-feed">
        <div className="activity-header">
          <h3>Agent Activity</h3>
        </div>
        <div className="activity-empty">
          No agent activity yet. Waiting for agents to connect...
        </div>
      </div>
    );
  }
  
  const recentActivity = useMemo(() => {
    const now = new Date().getTime();
    const recent = activities.filter(activity => 
      (now - activity.timestamp.getTime()) < 30000 // Last 30 seconds
    );
    return recent.length;
  }, [activities]);

  const collaborativeActions = useMemo(() => {
    // Identify potential collaborative actions
    const timeWindow = 10000; // 10 seconds
    const collaborations = [];
    
    for (let i = 0; i < activities.length - 1; i++) {
      const current = activities[i];
      const next = activities[i + 1];
      
      if (current.agentId !== next.agentId && 
          Math.abs(current.timestamp.getTime() - next.timestamp.getTime()) < timeWindow) {
        collaborations.push({ current, next, timeDiff: Math.abs(current.timestamp.getTime() - next.timestamp.getTime()) });
      }
    }
    
    return collaborations.slice(0, 5); // Show recent collaborations
  }, [activities]);

  return (
    <div className="activity-feed">
      <div className="activity-header">
        <h3>🤖 Multi-Agent Activity</h3>
        <div className="activity-stats">
          <span className="activity-count">{activities.length} total</span>
          <span className="recent-activity">{recentActivity} recent</span>
          {collaborativeActions.length > 0 && (
            <span className="collaboration-indicator">⚡ {collaborativeActions.length} collaborations</span>
          )}
        </div>
      </div>

      {/* Collaborative Actions Highlight */}
      {collaborativeActions.length > 0 && (
        <div className="collaboration-highlight">
          <h4>🔥 Active Collaboration Detected</h4>
          <div className="collaboration-examples">
            {collaborativeActions.slice(0, 2).map((collab, index) => (
              <div key={index} className="collaboration-pair">
                <div className="agent-pair">
                  <span className="agent-1">{getAgentName(collab.current.agentId)}</span>
                  <span className="collaboration-arrow">↔️</span>
                  <span className="agent-2">{getAgentName(collab.next.agentId)}</span>
                </div>
                <div className="collaboration-timing">
                  <span className="time-gap">{collab.timeDiff}ms apart</span>
                  <span className="collaboration-type">Real-time coordination</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      <div className="activity-list">
        {displayActivities.map((activity) => (
          <ActivityItem 
            key={activity.id} 
            activity={activity} 
            agentName={getAgentName(activity.agentId)}
          />
        ))}
      </div>
    </div>
  );
};