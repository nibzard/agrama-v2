---
title: Component Architecture
description: Detailed React component specifications and implementation patterns
---

# Component Architecture

## Overview

The Agrama Observatory web interface is built using a modular React component architecture designed for real-time visualization of multi-agent AI collaboration. Each component is optimized for performance, type safety, and seamless integration with the Agrama CodeGraph backend.

## Component Hierarchy

### Application Structure
```
App.tsx (Root Container)
├── ObservatoryHeader
│   ├── SystemStatusIndicator
│   ├── AgentOverview
│   └── ConnectionStatus
├── MainLayout
│   ├── LeftPanel
│   │   ├── AgentStatus
│   │   └── FileExplorer
│   ├── CenterPanel (Tabbed Interface)
│   │   ├── ActivityFeed
│   │   ├── SemanticSearchPanel
│   │   ├── DependencyGraphViz
│   │   ├── CollaborationDashboard
│   │   └── PerformanceMetrics
│   └── RightPanel
│       ├── CommandInput
│       └── CommandHistory
└── ObservatoryFooter
    └── SystemMetrics
```

## Core Components

### 1. App Component
**File**: `src/App.tsx`

The root application component that manages global state and WebSocket connections.

```typescript
interface AppProps {}

export const App: React.FC<AppProps> = () => {
  const {
    connected,
    agents,
    activities,
    fileChanges,
    commands,
    semanticSearchResults,
    dependencyAnalyses,
    sendCommand,
    sendSemanticSearch
  } = useWebSocket();

  return (
    <div className="app">
      <ObservatoryHeader 
        connected={connected}
        agentCount={agents.size}
        totalEvents={activities.length}
      />
      <MainLayout>
        {/* Component composition */}
      </MainLayout>
      <ObservatoryFooter />
    </div>
  );
};
```

**Key Responsibilities**:
- WebSocket connection management
- Global state distribution
- Layout coordination
- Error boundary handling

**Performance Optimizations**:
- Memoized prop calculations
- Conditional rendering based on connection state
- Optimized re-render cycles

### 2. AgentStatus Component
**File**: `src/components/AgentStatus.tsx`

Real-time monitoring of AI agent connections and activity states.

```typescript
interface AgentStatusProps {
  agents: Map<string, AgentConnection>;
  activities: AgentActivity[];
  totalEvents: number;
  lastEventTime: Date | null;
  connected: boolean;
}

export const AgentStatus: React.FC<AgentStatusProps> = ({
  agents,
  activities,
  totalEvents,
  lastEventTime,
  connected
}) => {
  const [expandedAgent, setExpandedAgent] = useState<string | null>(null);
  
  // Memoized agent statistics
  const agentStats = useMemo(() => {
    const stats = new Map<string, AgentStats>();
    
    agents.forEach((agent, id) => {
      const agentActivities = activities.filter(a => a.agentId === id);
      stats.set(id, {
        totalActions: agentActivities.length,
        lastActivity: agentActivities[0]?.timestamp || null,
        averageResponseTime: calculateAverageResponseTime(agentActivities),
        successRate: calculateSuccessRate(agentActivities)
      });
    });
    
    return stats;
  }, [agents, activities]);

  return (
    <div className="agent-status">
      <div className="agent-status-header">
        <h3>Active Agents ({agents.size})</h3>
        <div className="connection-indicator">
          <div className={`status-dot ${connected ? 'connected' : 'disconnected'}`} />
          {connected ? 'Connected' : 'Disconnected'}
        </div>
      </div>
      
      {Array.from(agents.entries()).map(([id, agent]) => (
        <AgentCard
          key={id}
          agent={agent}
          stats={agentStats.get(id)}
          expanded={expandedAgent === id}
          onToggleExpanded={() => setExpandedAgent(
            expandedAgent === id ? null : id
          )}
        />
      ))}
    </div>
  );
};
```

**Features**:
- Real-time agent connection monitoring
- Individual agent performance metrics
- Expandable agent details
- Visual connection status indicators
- Activity statistics and trends

### 3. ActivityFeed Component
**File**: `src/components/ActivityFeed.tsx`

Chronological display of all multi-agent activities with real-time updates.

```typescript
interface ActivityFeedProps {
  activities: AgentActivity[];
  agents: Map<string, AgentConnection>;
  onActivityFilter?: (filter: ActivityFilter) => void;
}

export const ActivityFeed: React.FC<ActivityFeedProps> = ({
  activities,
  agents,
  onActivityFilter
}) => {
  const [filter, setFilter] = useState<ActivityFilter>('all');
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);
  const feedRef = useRef<HTMLDivElement>(null);
  
  // Auto-scroll to latest activity
  useEffect(() => {
    if (feedRef.current) {
      feedRef.current.scrollTop = 0;
    }
  }, [activities.length]);

  // Filtered and memoized activity list
  const filteredActivities = useMemo(() => {
    let filtered = activities;
    
    if (selectedAgent) {
      filtered = filtered.filter(a => a.agentId === selectedAgent);
    }
    
    if (filter !== 'all') {
      filtered = filtered.filter(a => a.status === filter);
    }
    
    return filtered;
  }, [activities, selectedAgent, filter]);

  // Detect collaborative actions
  const collaborativeActions = useMemo(() => {
    const timeWindow = 10000; // 10 seconds
    const collaborations = [];
    
    for (let i = 0; i < activities.length - 1; i++) {
      const current = activities[i];
      const next = activities[i + 1];
      
      if (current.agentId !== next.agentId && 
          Math.abs(current.timestamp.getTime() - next.timestamp.getTime()) < timeWindow) {
        collaborations.push({ current, next });
      }
    }
    
    return collaborations.slice(0, 5);
  }, [activities]);

  return (
    <div className="activity-feed">
      <ActivityFeedHeader 
        filter={filter}
        onFilterChange={setFilter}
        selectedAgent={selectedAgent}
        onAgentChange={setSelectedAgent}
        agents={agents}
      />
      
      <div className="collaboration-highlights">
        <h4>Recent Collaborations</h4>
        {collaborativeActions.map((collab, idx) => (
          <CollaborationIndicator key={idx} collaboration={collab} />
        ))}
      </div>
      
      <div ref={feedRef} className="activity-list">
        {filteredActivities.map(activity => (
          <ActivityItem
            key={activity.id}
            activity={activity}
            agent={agents.get(activity.agentId)}
          />
        ))}
      </div>
    </div>
  );
};
```

**Key Features**:
- Real-time activity streaming
- Agent-specific filtering
- Collaboration detection
- Auto-scrolling to latest
- Performance status indicators

### 4. DependencyGraphViz Component
**File**: `src/components/DependencyGraphViz.tsx`

Interactive D3.js visualization of code dependencies using Frontier Reduction Engine.

```typescript
interface DependencyGraphVizProps {
  dependencyAnalyses: DependencyAnalysis[];
  width?: number;
  height?: number;
  onNodeSelect?: (nodeId: string) => void;
}

export const DependencyGraphViz: React.FC<DependencyGraphVizProps> = ({
  dependencyAnalyses,
  width = 800,
  height = 600,
  onNodeSelect
}) => {
  const svgRef = useRef<SVGSVGElement>(null);
  const [hoveredNode, setHoveredNode] = useState<string | null>(null);
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  
  // Get latest dependency analysis
  const latestAnalysis = dependencyAnalyses[0];
  const graphData = latestAnalysis ? {
    nodes: latestAnalysis.nodes,
    edges: latestAnalysis.edges
  } : null;

  useEffect(() => {
    if (!graphData || !svgRef.current) return;
    
    const svg = d3.select(svgRef.current);
    svg.selectAll("*").remove();
    
    // Create force simulation
    const simulation = d3.forceSimulation(graphData.nodes)
      .force("link", d3.forceLink<DependencyNode, DependencyEdge>(graphData.edges)
        .id(d => d.id)
        .distance(d => {
          // Dynamic edge length based on relationship strength
          return 50 + (1 - d.weight) * 100;
        })
        .strength(0.3))
      .force("charge", d3.forceManyBody()
        .strength(d => {
          // Node charge based on complexity
          const baseStrength = -300;
          return baseStrength * (1 + d.complexity * 0.5);
        }))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide()
        .radius(d => nodeSize(d.complexity) + 5));

    // Add zoom behavior
    const zoom = d3.zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.1, 4])
      .on("zoom", (event) => {
        g.attr("transform", event.transform);
      });

    svg.call(zoom);
    
    const g = svg.append("g");
    
    // Add edges
    const edges = g.selectAll<SVGLineElement, DependencyEdge>(".edge")
      .data(graphData.edges)
      .enter()
      .append("line")
      .classed("edge", true)
      .style("stroke", d => edgeColor(d.type))
      .style("stroke-width", d => Math.sqrt(d.weight) * 2)
      .style("opacity", 0.6);
    
    // Add nodes
    const nodes = g.selectAll<SVGGElement, DependencyNode>(".node")
      .data(graphData.nodes)
      .enter()
      .append("g")
      .classed("node", true)
      .call(d3.drag<SVGGElement, DependencyNode>()
        .on("start", dragStarted)
        .on("drag", dragged)
        .on("end", dragEnded));
    
    // Node circles
    nodes.append("circle")
      .attr("r", d => nodeSize(d.complexity))
      .style("fill", d => nodeColor(d.type))
      .style("stroke", "#fff")
      .style("stroke-width", 2);
    
    // Node labels
    nodes.append("text")
      .text(d => d.name)
      .attr("dx", d => nodeSize(d.complexity) + 5)
      .attr("dy", "0.35em")
      .style("font-size", "12px")
      .style("fill", "#333");
    
    // Mouse interactions
    nodes
      .on("mouseenter", (event, d) => {
        setHoveredNode(d.id);
        
        // Highlight connected edges
        edges.style("opacity", edge => 
          isConnectedToNode(edge, d.id) ? 0.9 : 0.2
        );
        
        // Show tooltip
        showTooltip(event, d);
      })
      .on("mouseleave", () => {
        setHoveredNode(null);
        edges.style("opacity", 0.6);
        hideTooltip();
      })
      .on("click", (event, d) => {
        setSelectedNode(d.id);
        onNodeSelect?.(d.id);
      });
    
    // Update positions on simulation tick
    simulation.on("tick", () => {
      edges
        .attr("x1", d => (d.source as DependencyNode).x!)
        .attr("y1", d => (d.source as DependencyNode).y!)
        .attr("x2", d => (d.target as DependencyNode).x!)
        .attr("y2", d => (d.target as DependencyNode).y!);
      
      nodes.attr("transform", d => `translate(${d.x!},${d.y!})`);
    });
    
    // Drag event handlers
    function dragStarted(event: d3.D3DragEvent<SVGGElement, DependencyNode, DependencyNode>, d: DependencyNode) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }
    
    function dragged(event: d3.D3DragEvent<SVGGElement, DependencyNode, DependencyNode>, d: DependencyNode) {
      d.fx = event.x;
      d.fy = event.y;
    }
    
    function dragEnded(event: d3.D3DragEvent<SVGGElement, DependencyNode, DependencyNode>, d: DependencyNode) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }
    
    // Cleanup
    return () => {
      simulation.stop();
    };
  }, [graphData, width, height, onNodeSelect]);

  return (
    <div className="dependency-graph-viz">
      <div className="graph-controls">
        <GraphControls
          hoveredNode={hoveredNode}
          selectedNode={selectedNode}
          onReset={() => {
            setSelectedNode(null);
            setHoveredNode(null);
          }}
        />
      </div>
      
      <svg
        ref={svgRef}
        width={width}
        height={height}
        className="dependency-graph"
      />
      
      {latestAnalysis && (
        <GraphMetrics
          freStats={latestAnalysis.freStats}
          nodeCount={graphData?.nodes.length || 0}
          edgeCount={graphData?.edges.length || 0}
        />
      )}
    </div>
  );
};
```

**Advanced Features**:
- Force-directed graph layout with D3.js
- Interactive zoom and pan capabilities
- Node dragging with physics simulation
- Edge highlighting on hover
- Performance metrics display
- Responsive scaling

### 5. SemanticSearchPanel Component
**File**: `src/components/SemanticSearchPanel.tsx`

HNSW-powered semantic code search with real-time performance metrics.

```typescript
interface SemanticSearchPanelProps {
  searchResults: SemanticSearchResult[];
  onSearch: (query: string) => void;
}

export const SemanticSearchPanel: React.FC<SemanticSearchPanelProps> = ({
  searchResults,
  onSearch
}) => {
  const [query, setQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const searchTimeoutRef = useRef<number>();
  
  // Debounced search function
  const debouncedSearch = useCallback(
    debounce((searchQuery: string) => {
      if (searchQuery.trim()) {
        setIsSearching(true);
        onSearch(searchQuery);
      }
    }, 300),
    [onSearch]
  );
  
  useEffect(() => {
    debouncedSearch(query);
  }, [query, debouncedSearch]);
  
  // Reset searching state when results arrive
  useEffect(() => {
    if (searchResults.length > 0) {
      setIsSearching(false);
    }
  }, [searchResults]);

  const latestResult = searchResults[0];

  return (
    <div className="semantic-search-panel">
      <div className="search-input-container">
        <input
          type="text"
          placeholder="Search codebase semantically..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="search-input"
        />
        {isSearching && (
          <div className="search-spinner">
            <LoadingSpinner size="small" />
          </div>
        )}
      </div>
      
      {latestResult && (
        <div className="search-metrics">
          <div className="metric">
            <span className="label">Search Time:</span>
            <span className="value">{latestResult.hnswStats.searchTime.toFixed(2)}ms</span>
          </div>
          <div className="metric">
            <span className="label">Hops:</span>
            <span className="value">{latestResult.hnswStats.hopsCount}</span>
          </div>
          <div className="metric">
            <span className="label">Candidates:</span>
            <span className="value">{latestResult.hnswStats.candidatesEvaluated}</span>
          </div>
        </div>
      )}
      
      <div className="search-results">
        {latestResult?.results.map((result, idx) => (
          <SearchResultItem
            key={`${result.nodeId}-${idx}`}
            result={result}
            query={latestResult.query}
          />
        ))}
      </div>
      
      <div className="search-history">
        <h4>Recent Searches</h4>
        {searchResults.slice(1, 6).map((result, idx) => (
          <SearchHistoryItem
            key={idx}
            result={result}
            onRerun={() => setQuery(result.query)}
          />
        ))}
      </div>
    </div>
  );
};
```

**Key Features**:
- Real-time semantic search with debouncing
- HNSW performance metrics display
- Search history and re-run capability
- Result similarity scoring
- Query suggestion system

### 6. CommandInput Component
**File**: `src/components/CommandInput.tsx`

Natural language interface for directing AI agents with intelligent suggestions.

```typescript
interface CommandInputProps {
  onCommand: (command: string, targetAgents?: string[]) => void;
  agents: Map<string, AgentConnection>;
  commands: HumanCommand[];
  connected: boolean;
}

export const CommandInput: React.FC<CommandInputProps> = ({
  onCommand,
  agents,
  commands,
  connected
}) => {
  const [command, setCommand] = useState('');
  const [targetAgents, setTargetAgents] = useState<string[]>([]);
  const [suggestions, setSuggestions] = useState<CommandSuggestion[]>([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  
  // Command templates
  const commandTemplates = [
    {
      template: "Analyze the dependencies of {file}",
      description: "Analyze file dependencies and impact"
    },
    {
      template: "Refactor {function} to improve performance",
      description: "Suggest performance optimizations"
    },
    {
      template: "Add unit tests for {module}",
      description: "Generate comprehensive test coverage"
    },
    {
      template: "Document the {api} interface",
      description: "Create API documentation"
    }
  ];
  
  // Generate suggestions based on current input
  const generateSuggestions = useCallback((input: string) => {
    const suggestions: CommandSuggestion[] = [];
    
    // Template-based suggestions
    commandTemplates.forEach(template => {
      if (template.template.toLowerCase().includes(input.toLowerCase()) ||
          template.description.toLowerCase().includes(input.toLowerCase())) {
        suggestions.push({
          text: template.template,
          description: template.description,
          type: 'template'
        });
      }
    });
    
    // Context-aware suggestions based on recent activities
    const recentFiles = new Set(
      commands
        .slice(0, 10)
        .map(cmd => extractFilenameFromCommand(cmd.command))
        .filter(Boolean)
    );
    
    recentFiles.forEach(filename => {
      suggestions.push({
        text: `Review changes in ${filename}`,
        description: `Analyze recent modifications`,
        type: 'context'
      });
    });
    
    return suggestions.slice(0, 5);
  }, [commands]);

  // Update suggestions when input changes
  useEffect(() => {
    if (command.length > 2) {
      const newSuggestions = generateSuggestions(command);
      setSuggestions(newSuggestions);
      setShowSuggestions(newSuggestions.length > 0);
    } else {
      setShowSuggestions(false);
    }
  }, [command, generateSuggestions]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!command.trim() || !connected) return;
    
    onCommand(command, targetAgents.length > 0 ? targetAgents : undefined);
    setCommand('');
    setShowSuggestions(false);
  };

  const handleSuggestionClick = (suggestion: CommandSuggestion) => {
    setCommand(suggestion.text);
    setShowSuggestions(false);
  };

  return (
    <div className="command-input">
      <div className="command-header">
        <h3>Human Command Interface</h3>
        <div className="agent-targeting">
          <label>Target Agents:</label>
          <AgentSelector
            agents={agents}
            selectedAgents={targetAgents}
            onAgentToggle={(agentId) => {
              setTargetAgents(prev => 
                prev.includes(agentId) 
                  ? prev.filter(id => id !== agentId)
                  : [...prev, agentId]
              );
            }}
          />
        </div>
      </div>
      
      <form onSubmit={handleSubmit} className="command-form">
        <div className="input-container">
          <textarea
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            placeholder="Type a natural language command for AI agents..."
            rows={3}
            disabled={!connected}
            className="command-textarea"
          />
          
          {showSuggestions && (
            <div className="suggestions-dropdown">
              {suggestions.map((suggestion, idx) => (
                <div
                  key={idx}
                  className="suggestion-item"
                  onClick={() => handleSuggestionClick(suggestion)}
                >
                  <div className="suggestion-text">{suggestion.text}</div>
                  <div className="suggestion-description">{suggestion.description}</div>
                </div>
              ))}
            </div>
          )}
        </div>
        
        <button
          type="submit"
          disabled={!command.trim() || !connected}
          className="send-command-btn"
        >
          Send Command
        </button>
      </form>
      
      <div className="recent-commands">
        <h4>Command History</h4>
        {commands.slice(0, 5).map(cmd => (
          <CommandHistoryItem
            key={cmd.id}
            command={cmd}
            onRerun={() => setCommand(cmd.command)}
          />
        ))}
      </div>
    </div>
  );
};
```

**Advanced Features**:
- Natural language command interface
- Intelligent command suggestions
- Context-aware recommendations
- Multi-agent targeting
- Command history and re-run

## Shared Components

### LoadingSpinner
Reusable loading indicator with size variants.

### ConnectionStatus
Real-time connection status indicator with retry functionality.

### MetricDisplay
Standardized component for displaying performance metrics.

### ErrorBoundary
React error boundary for graceful error handling.

## Design System

### Color Palette
```css
:root {
  /* Primary colors */
  --primary-blue: #007acc;
  --primary-green: #28a745;
  --primary-red: #dc3545;
  --primary-yellow: #ffc107;
  
  /* Semantic colors */
  --success: #28a745;
  --warning: #ffc107;
  --error: #dc3545;
  --info: #17a2b8;
  
  /* Background colors */
  --bg-primary: #ffffff;
  --bg-secondary: #f8f9fa;
  --bg-dark: #212529;
  
  /* Text colors */
  --text-primary: #212529;
  --text-secondary: #6c757d;
  --text-muted: #adb5bd;
}
```

### Typography
- **Headers**: Inter font family, semi-bold weights
- **Body**: Inter font family, regular weight
- **Monospace**: Source Code Pro for code displays

### Spacing System
- **Base unit**: 8px
- **Small**: 4px, 8px, 12px
- **Medium**: 16px, 24px, 32px
- **Large**: 48px, 64px, 96px

## Performance Optimizations

### React Optimizations
- `React.memo()` for expensive components
- `useMemo()` for complex calculations
- `useCallback()` for event handlers
- Lazy loading for non-critical components

### D3.js Optimizations
- Efficient enter/update/exit patterns
- Debounced updates for high-frequency events
- Canvas fallback for large datasets
- WebGL acceleration for complex visualizations

### Memory Management
- Bounded arrays for real-time data streams
- Automatic cleanup of unused resources
- Efficient WebSocket message handling
- Garbage collection optimization

This component architecture provides a solid foundation for the Observatory interface while maintaining flexibility for future enhancements and ensuring optimal performance for real-time AI collaboration monitoring.