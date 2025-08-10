// Demo Data Provider - Showcases revolutionary technology capabilities
import React, { useEffect, useMemo, useState } from 'react';
import type { 
  AgentConnection, 
  AgentActivity, 
  CollaborationUpdate, 
  PerformanceUpdate,
  SemanticSearchResult,
  DependencyAnalysis 
} from '../types';

interface DemoDataProviderProps {
  children: React.ReactNode;
  connected: boolean;
  agents: Map<string, AgentConnection>;
  activities: AgentActivity[];
  collaborationUpdates: CollaborationUpdate[];
  performanceUpdates: PerformanceUpdate[];
  onSampleData?: (data: {
    sampleAgents: Map<string, AgentConnection>;
    sampleActivities: AgentActivity[];
    sampleCollaborations: CollaborationUpdate[];
    samplePerformance: PerformanceUpdate[];
    sampleSearchResults: SemanticSearchResult[];
    sampleDependencies: DependencyAnalysis[];
  }) => void;
}

export const DemoDataProvider: React.FC<DemoDataProviderProps> = ({ 
  children, 
  connected,
  agents,
  activities,
  collaborationUpdates,
  performanceUpdates,
  onSampleData 
}) => {
  const [showDemo, setShowDemo] = useState(false);

  // Generate sample data for demonstration
  const sampleData = useMemo(() => {
    if (!showDemo) return null;

    const now = new Date();
    const sampleAgents = new Map<string, AgentConnection>();
    
    // Sample AI agents
    const agentConfigs = [
      { id: 'claude-code-1', name: 'Claude Code Primary', status: 'active' as const },
      { id: 'cursor-ai-2', name: 'Cursor AI Assistant', status: 'connected' as const },
      { id: 'claude-architect', name: 'Claude Architect', status: 'active' as const },
      { id: 'ai-reviewer', name: 'AI Code Reviewer', status: 'connected' as const },
    ];

    agentConfigs.forEach(config => {
      sampleAgents.set(config.id, {
        ...config,
        lastActivity: new Date(now.getTime() - Math.random() * 60000)
      });
    });

    // Sample collaborative activities
    const sampleActivities: AgentActivity[] = [];
    const files = ['src/db/core.zig', 'src/mcp/server.ts', 'web/src/App.tsx', 'src/algorithms/hnsw.zig'];
    
    for (let i = 0; i < 25; i++) {
      const agentId = Array.from(sampleAgents.keys())[Math.floor(Math.random() * sampleAgents.size)];
      const file = files[Math.floor(Math.random() * files.length)];
      const tools = ['read_code', 'write_code', 'analyze_dependencies', 'get_context', 'record_decision'];
      const tool = tools[Math.floor(Math.random() * tools.length)];
      
      sampleActivities.push({
        id: `activity-${i}`,
        agentId,
        agentName: sampleAgents.get(agentId)?.name || agentId,
        tool,
        action: `Processing ${file}`,
        timestamp: new Date(now.getTime() - i * 5000 - Math.random() * 10000),
        params: { file_path: file },
        duration: 50 + Math.random() * 200,
        status: Math.random() > 0.1 ? 'success' : 'error'
      });
    }

    // Sample collaboration updates (CRDT)
    const sampleCollaborations: CollaborationUpdate[] = files.map((file, index) => ({
      id: new Date(now.getTime() - index * 30000).toISOString(),
      filePath: file,
      operations: Array.from({ length: 3 + Math.floor(Math.random() * 8) }, (_, i) => ({
        id: `op-${index}-${i}`,
        agentId: Array.from(sampleAgents.keys())[Math.floor(Math.random() * sampleAgents.size)],
        type: ['insert', 'delete', 'replace'][Math.floor(Math.random() * 3)] as any,
        position: Math.floor(Math.random() * 1000),
        content: Math.random() > 0.5 ? `code_${i}` : undefined,
        timestamp: new Date(now.getTime() - i * 1000),
        vectorClock: Object.fromEntries(
          Array.from(sampleAgents.keys()).map(id => [id, Math.floor(Math.random() * 10)])
        )
      })),
      conflicts: Math.random() > 0.7 ? [{
        operationIds: [`op-${index}-0`, `op-${index}-1`],
        resolution: Math.random() > 0.8 ? 'manual' : 'automatic' as any,
        resolutionStrategy: 'last-writer-wins'
      }] : [],
      crdtStats: {
        operationTime: 0.5 + Math.random() * 2,
        mergeTime: 0.2 + Math.random() * 1,
        stateSize: 1024 + Math.floor(Math.random() * 4096)
      },
      activeAgents: Array.from(sampleAgents.keys()).slice(0, 2 + Math.floor(Math.random() * 2))
    }));

    // Sample performance metrics
    const samplePerformance: PerformanceUpdate[] = [{
      id: now.toISOString(),
      timestamp: now,
      hnswPerformance: {
        avgSearchTime: 0.3 + Math.random() * 0.5,
        throughput: 50000 + Math.random() * 20000,
        indexSize: 1024 * 1024 * (10 + Math.random() * 50),
        speedupVsLinear: 100 + Math.random() * 900
      },
      frePerformance: {
        avgTraversalTime: 0.8 + Math.random() * 1.2,
        throughput: 25000 + Math.random() * 15000,
        graphSize: 10000 + Math.floor(Math.random() * 90000),
        speedupVsDijkstra: 20 + Math.random() * 30
      },
      crdtPerformance: {
        avgOperationTime: 0.1 + Math.random() * 0.3,
        avgMergeTime: 0.05 + Math.random() * 0.15,
        operationThroughput: 10000 + Math.random() * 5000,
        conflictRate: Math.random() * 5
      },
      systemMetrics: {
        memoryUsage: 1024 * 1024 * (500 + Math.random() * 1000),
        cpuUsage: 20 + Math.random() * 40,
        activeConnections: sampleAgents.size
      }
    }];

    // Sample semantic search results
    const sampleSearchResults: SemanticSearchResult[] = [{
      id: 'search-1',
      query: 'CRDT conflict resolution algorithm',
      results: Array.from({ length: 5 }, (_, i) => ({
        nodeId: `node-${i}`,
        content: `Code snippet ${i} related to CRDT operations`,
        similarity: 0.95 - i * 0.1,
        distance: i * 0.1 + 0.05,
        embedding: Array.from({ length: 64 }, () => Math.random())
      })),
      hnswStats: {
        searchTime: 0.2 + Math.random() * 0.3,
        hopsCount: 5 + Math.floor(Math.random() * 10),
        candidatesEvaluated: 100 + Math.floor(Math.random() * 200)
      },
      agentId: Array.from(sampleAgents.keys())[0]
    }];

    // Sample dependency analysis
    const sampleDependencies: DependencyAnalysis[] = [{
      id: 'dep-1',
      targetNode: 'src/db/core.zig',
      nodes: files.map((file, i) => ({
        id: file,
        name: file,
        type: 'file',
        filePath: file,
        complexity: Math.floor(Math.random() * 100)
      })),
      edges: files.slice(1).map(file => ({
        source: 'src/db/core.zig',
        target: file,
        type: 'imports',
        weight: Math.random()
      })),
      freStats: {
        traversalTime: 1.2 + Math.random() * 0.8,
        nodesVisited: files.length,
        pathsFound: files.length - 1,
        complexity: 'O(m log^(2/3) n)'
      },
      impactPaths: files.slice(1).map(file => ({
        path: ['src/db/core.zig', file],
        weight: Math.random(),
        impactScore: Math.random() * 100
      })),
      agentId: Array.from(sampleAgents.keys())[0]
    }];

    return {
      sampleAgents,
      sampleActivities,
      sampleCollaborations,
      samplePerformance,
      sampleSearchResults,
      sampleDependencies
    };
  }, [showDemo]);

  // Auto-enable demo if no real data is present
  useEffect(() => {
    const hasRealData = agents.size > 0 || activities.length > 0 || 
                        collaborationUpdates.length > 0 || performanceUpdates.length > 0;
    
    if (!hasRealData && !connected) {
      setShowDemo(true);
    } else if (hasRealData) {
      setShowDemo(false);
    }
  }, [connected, agents.size, activities.length, collaborationUpdates.length, performanceUpdates.length]);

  // Provide sample data to parent
  useEffect(() => {
    if (sampleData && onSampleData) {
      onSampleData(sampleData);
    }
  }, [sampleData, onSampleData]);

  return (
    <>
      {children}
      {showDemo && (
        <div className="demo-banner">
          <div className="demo-content">
            <h4>🚀 DEMO MODE: Revolutionary Technology Showcase</h4>
            <p>Displaying simulated multi-agent AI collaboration to demonstrate breakthrough capabilities</p>
            <div className="demo-features">
              <span>✅ Multi-Agent Coordination</span>
              <span>✅ Real-time CRDT Sync</span>
              <span>✅ HNSW Semantic Search</span>
              <span>✅ FRE Graph Traversal</span>
            </div>
          </div>
        </div>
      )}
    </>
  );
};