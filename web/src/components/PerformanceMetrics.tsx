// Real-time Algorithm Performance Monitoring Dashboard
import React, { useMemo } from 'react';
import type { PerformanceUpdate } from '../types';

interface PerformanceMetricsProps {
  performanceUpdates: PerformanceUpdate[];
}

interface MetricCardProps {
  title: string;
  value: string;
  subtitle?: string;
  trend?: 'up' | 'down' | 'stable';
  color?: string;
  efficiency?: number;
}

interface AlgorithmSectionProps {
  title: string;
  icon: string;
  metrics: Array<{ label: string; value: string; subtitle?: string; color?: string; efficiency?: number }>;
  complexityInfo: string;
  efficiencyMultiplier?: number;
}

const MetricCard: React.FC<MetricCardProps> = ({ 
  title, 
  value, 
  subtitle, 
  trend = 'stable', 
  color = '#333',
  efficiency 
}) => {
  const getTrendIcon = () => {
    switch (trend) {
      case 'up': return '📈';
      case 'down': return '📉';
      default: return '➡️';
    }
  };

  const getTrendColor = () => {
    switch (trend) {
      case 'up': return '#4CAF50';
      case 'down': return '#F44336';
      default: return '#9E9E9E';
    }
  };

  return (
    <div className="metric-card">
      <div className="metric-header">
        <span className="metric-title">{title}</span>
        {trend !== 'stable' && (
          <span className="metric-trend" style={{ color: getTrendColor() }}>
            {getTrendIcon()}
          </span>
        )}
      </div>
      
      <div className="metric-value" style={{ color }}>
        {value}
      </div>
      
      {subtitle && (
        <div className="metric-subtitle">
          {subtitle}
        </div>
      )}

      {efficiency !== undefined && (
        <div className="metric-efficiency">
          <div 
            className="efficiency-bar"
            style={{ 
              width: `${Math.min(100, (efficiency / 100) * 100)}%`,
              backgroundColor: efficiency > 50 ? '#4CAF50' : efficiency > 20 ? '#FF9800' : '#F44336'
            }}
          />
          <span className="efficiency-text">{efficiency.toFixed(1)}x faster</span>
        </div>
      )}
    </div>
  );
};

const AlgorithmSection: React.FC<AlgorithmSectionProps> = ({ 
  title, 
  icon, 
  metrics, 
  complexityInfo,
  efficiencyMultiplier 
}) => {
  const getEfficiencyColor = (multiplier?: number) => {
    if (!multiplier) return '#9E9E9E';
    if (multiplier > 100) return '#00ff00';
    if (multiplier > 50) return '#80ff00';
    if (multiplier > 10) return '#ffff00';
    if (multiplier > 5) return '#ff8000';
    return '#ff4000';
  };

  return (
    <div className="algorithm-section">
      <div className="algorithm-header">
        <span className="algorithm-icon">{icon}</span>
        <h4 className="algorithm-title">{title}</h4>
        {efficiencyMultiplier && (
          <span 
            className="efficiency-multiplier"
            style={{ color: getEfficiencyColor(efficiencyMultiplier) }}
          >
            {efficiencyMultiplier.toFixed(0)}x faster than naive
          </span>
        )}
      </div>

      <div className="algorithm-complexity">
        <span className="complexity-label">Complexity:</span>
        <code className="complexity-value">{complexityInfo}</code>
      </div>

      <div className="metrics-grid">
        {metrics.map((metric, index) => (
          <MetricCard
            key={index}
            title={metric.label}
            value={metric.value}
            subtitle={metric.subtitle}
            color={metric.color}
            efficiency={metric.efficiency}
          />
        ))}
      </div>
    </div>
  );
};

export const PerformanceMetrics: React.FC<PerformanceMetricsProps> = ({
  performanceUpdates
}) => {
  const latestUpdate = performanceUpdates[0];

  const averageMetrics = useMemo(() => {
    if (performanceUpdates.length === 0) return null;

    const avgHnswSearchTime = performanceUpdates.reduce((sum, update) => 
      sum + update.hnswPerformance.avgSearchTime, 0) / performanceUpdates.length;
    
    const avgHnswThroughput = performanceUpdates.reduce((sum, update) => 
      sum + update.hnswPerformance.throughput, 0) / performanceUpdates.length;

    const avgFreTraversalTime = performanceUpdates.reduce((sum, update) => 
      sum + update.frePerformance.avgTraversalTime, 0) / performanceUpdates.length;

    const avgFreThroughput = performanceUpdates.reduce((sum, update) => 
      sum + update.frePerformance.throughput, 0) / performanceUpdates.length;

    const avgCrdtOperationTime = performanceUpdates.reduce((sum, update) => 
      sum + update.crdtPerformance.avgOperationTime, 0) / performanceUpdates.length;

    const avgCrdtMergeTime = performanceUpdates.reduce((sum, update) => 
      sum + update.crdtPerformance.avgMergeTime, 0) / performanceUpdates.length;

    const avgMemoryUsage = performanceUpdates.reduce((sum, update) => 
      sum + update.systemMetrics.memoryUsage, 0) / performanceUpdates.length;

    const avgCpuUsage = performanceUpdates.reduce((sum, update) => 
      sum + update.systemMetrics.cpuUsage, 0) / performanceUpdates.length;

    return {
      avgHnswSearchTime,
      avgHnswThroughput,
      avgFreTraversalTime,
      avgFreThroughput,
      avgCrdtOperationTime,
      avgCrdtMergeTime,
      avgMemoryUsage,
      avgCpuUsage
    };
  }, [performanceUpdates]);

  const formatTime = (ms: number) => {
    if (ms < 1) return `${(ms * 1000).toFixed(0)}μs`;
    if (ms < 1000) return `${ms.toFixed(1)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatThroughput = (ops: number) => {
    if (ops > 1000000) return `${(ops / 1000000).toFixed(1)}M ops/s`;
    if (ops > 1000) return `${(ops / 1000).toFixed(1)}K ops/s`;
    return `${ops.toFixed(0)} ops/s`;
  };

  const formatBytes = (bytes: number) => {
    if (bytes > 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)}GB`;
    if (bytes > 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
    if (bytes > 1024) return `${(bytes / 1024).toFixed(1)}KB`;
    return `${bytes}B`;
  };

  const formatPercentage = (value: number) => {
    return `${value.toFixed(1)}%`;
  };

  if (!latestUpdate) {
    return (
      <div className="performance-metrics">
        <div className="metrics-header">
          <h3>⚡ Algorithm Performance</h3>
        </div>
        <div className="no-metrics">
          <p>No performance data available.</p>
          <p>Metrics will appear when algorithms are actively processing data.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="performance-metrics">
      <div className="metrics-header">
        <h3>⚡ Algorithm Performance Dashboard</h3>
        <div className="update-info">
          <span>Last updated: {new Date(latestUpdate.timestamp).toLocaleTimeString()}</span>
          <span>•</span>
          <span>{performanceUpdates.length} data points</span>
        </div>
      </div>

      {/* System Overview */}
      <div className="system-overview">
        <h4>🖥️ System Overview</h4>
        <div className="overview-grid">
          <MetricCard
            title="Memory Usage"
            value={formatBytes(latestUpdate.systemMetrics.memoryUsage)}
            subtitle={averageMetrics ? `Avg: ${formatBytes(averageMetrics.avgMemoryUsage)}` : undefined}
            color="#2196F3"
          />
          <MetricCard
            title="CPU Usage"
            value={formatPercentage(latestUpdate.systemMetrics.cpuUsage)}
            subtitle={averageMetrics ? `Avg: ${formatPercentage(averageMetrics.avgCpuUsage)}` : undefined}
            color="#FF9800"
          />
          <MetricCard
            title="Active Connections"
            value={latestUpdate.systemMetrics.activeConnections.toString()}
            subtitle="WebSocket + MCP"
            color="#4CAF50"
          />
          <MetricCard
            title="Data Points"
            value={performanceUpdates.length.toString()}
            subtitle="Performance samples"
            color="#9C27B0"
          />
        </div>
      </div>

      {/* HNSW Performance */}
      <AlgorithmSection
        title="HNSW Semantic Search"
        icon="🔍"
        complexityInfo="O(log n) vs O(n) linear scan"
        efficiencyMultiplier={latestUpdate.hnswPerformance.speedupVsLinear}
        metrics={[
          {
            label: "Avg Search Time",
            value: formatTime(latestUpdate.hnswPerformance.avgSearchTime),
            subtitle: averageMetrics ? `Overall: ${formatTime(averageMetrics.avgHnswSearchTime)}` : undefined,
            color: "#4CAF50",
            efficiency: latestUpdate.hnswPerformance.speedupVsLinear
          },
          {
            label: "Throughput",
            value: formatThroughput(latestUpdate.hnswPerformance.throughput),
            subtitle: averageMetrics ? `Avg: ${formatThroughput(averageMetrics.avgHnswThroughput)}` : undefined,
            color: "#2196F3"
          },
          {
            label: "Index Size",
            value: formatBytes(latestUpdate.hnswPerformance.indexSize),
            subtitle: "In-memory vectors",
            color: "#FF9800"
          },
          {
            label: "Speedup Factor",
            value: `${latestUpdate.hnswPerformance.speedupVsLinear.toFixed(0)}x`,
            subtitle: "vs Linear Search",
            color: "#9C27B0"
          }
        ]}
      />

      {/* FRE Performance */}
      <AlgorithmSection
        title="FRE Graph Traversal"
        icon="🕸️"
        complexityInfo="O(m log^(2/3) n) vs O(m + n log n) Dijkstra"
        efficiencyMultiplier={latestUpdate.frePerformance.speedupVsDijkstra}
        metrics={[
          {
            label: "Avg Traversal Time",
            value: formatTime(latestUpdate.frePerformance.avgTraversalTime),
            subtitle: averageMetrics ? `Overall: ${formatTime(averageMetrics.avgFreTraversalTime)}` : undefined,
            color: "#4CAF50",
            efficiency: latestUpdate.frePerformance.speedupVsDijkstra
          },
          {
            label: "Throughput",
            value: formatThroughput(latestUpdate.frePerformance.throughput),
            subtitle: averageMetrics ? `Avg: ${formatThroughput(averageMetrics.avgFreThroughput)}` : undefined,
            color: "#2196F3"
          },
          {
            label: "Graph Size",
            value: `${latestUpdate.frePerformance.graphSize.toLocaleString()} nodes`,
            subtitle: "Dependency graph",
            color: "#FF9800"
          },
          {
            label: "Speedup Factor", 
            value: `${latestUpdate.frePerformance.speedupVsDijkstra.toFixed(0)}x`,
            subtitle: "vs Dijkstra",
            color: "#9C27B0"
          }
        ]}
      />

      {/* CRDT Performance */}
      <AlgorithmSection
        title="CRDT Collaboration"
        icon="👥"
        complexityInfo="O(1) operation application with conflict-free merging"
        metrics={[
          {
            label: "Avg Operation Time",
            value: formatTime(latestUpdate.crdtPerformance.avgOperationTime),
            subtitle: averageMetrics ? `Overall: ${formatTime(averageMetrics.avgCrdtOperationTime)}` : undefined,
            color: "#4CAF50"
          },
          {
            label: "Avg Merge Time",
            value: formatTime(latestUpdate.crdtPerformance.avgMergeTime),
            subtitle: averageMetrics ? `Overall: ${formatTime(averageMetrics.avgCrdtMergeTime)}` : undefined,
            color: "#2196F3"
          },
          {
            label: "Operation Throughput",
            value: formatThroughput(latestUpdate.crdtPerformance.operationThroughput),
            subtitle: "Concurrent operations",
            color: "#FF9800"
          },
          {
            label: "Conflict Rate",
            value: formatPercentage(latestUpdate.crdtPerformance.conflictRate),
            subtitle: "Auto-resolved",
            color: latestUpdate.crdtPerformance.conflictRate > 10 ? "#F44336" : "#4CAF50"
          }
        ]}
      />

      {/* Performance Trends */}
      {performanceUpdates.length > 1 && (
        <div className="performance-trends">
          <h4>📈 Performance Trends</h4>
          <div className="trends-summary">
            <div className="trend-item">
              <span className="trend-label">HNSW Search:</span>
              <span className="trend-value">
                {latestUpdate.hnswPerformance.avgSearchTime < averageMetrics!.avgHnswSearchTime ? '📈 Improving' : '📉 Degrading'}
              </span>
            </div>
            <div className="trend-item">
              <span className="trend-label">FRE Traversal:</span>
              <span className="trend-value">
                {latestUpdate.frePerformance.avgTraversalTime < averageMetrics!.avgFreTraversalTime ? '📈 Improving' : '📉 Degrading'}
              </span>
            </div>
            <div className="trend-item">
              <span className="trend-label">CRDT Operations:</span>
              <span className="trend-value">
                {latestUpdate.crdtPerformance.avgOperationTime < averageMetrics!.avgCrdtOperationTime ? '📈 Improving' : '📉 Degrading'}
              </span>
            </div>
            <div className="trend-item">
              <span className="trend-label">Memory Usage:</span>
              <span className="trend-value">
                {latestUpdate.systemMetrics.memoryUsage < averageMetrics!.avgMemoryUsage ? '📈 Optimized' : '📉 Increasing'}
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};