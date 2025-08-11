---
title: Frontend Architecture
description: Technical architecture and design patterns for the Observatory interface
---

# Frontend Architecture

## Overview

The Agrama Observatory frontend architecture is designed for high-performance real-time visualization of multi-agent AI collaboration. Built with modern React patterns, TypeScript type safety, and D3.js visualization capabilities, it provides a scalable foundation for complex interactive dashboards.

## Architectural Principles

### Real-time First
Every component is designed to handle continuous data streams with minimal latency:
- **Event-driven updates** trigger immediate UI changes
- **Optimistic UI patterns** provide instant feedback
- **Efficient reconciliation** minimizes unnecessary re-renders
- **Memory-bounded buffers** prevent performance degradation

### Type Safety Throughout
Comprehensive TypeScript coverage ensures reliability:
- **Strict type checking** for all MCP server communication
- **Interface definitions** for every data structure
- **Generic components** with proper constraint enforcement
- **Runtime type validation** for WebSocket events

### Performance-Optimized
Architecture designed for sub-100ms update latencies:
- **Memoized computations** prevent expensive recalculations
- **Virtual rendering** for large datasets
- **Debounced interactions** smooth user experience
- **WebGL acceleration** for complex visualizations

## Technology Stack

### Core Framework
```json
{
  "react": "^18.2.0",
  "typescript": "^5.1.0",
  "vite": "^4.4.0"
}
```

### Visualization Libraries
```json
{
  "d3": "^7.8.0",
  "d3-force": "^3.0.0",
  "d3-selection": "^3.0.0",
  "d3-scale": "^4.0.0"
}
```

### Development Tools
```json
{
  "@types/d3": "^7.4.0",
  "eslint": "^8.45.0",
  "@typescript-eslint/parser": "^5.62.0"
}
```

## Directory Structure

```
web/
├── src/
│   ├── components/           # React components
│   │   ├── ActivityFeed.tsx         # Agent activity monitoring
│   │   ├── AgentStatus.tsx          # Agent connection status
│   │   ├── CollaborationDashboard.tsx # CRDT visualization
│   │   ├── CommandInput.tsx         # Human command interface
│   │   ├── DependencyGraphViz.tsx   # FRE graph visualization
│   │   ├── FileExplorer.tsx         # File change monitoring
│   │   ├── PerformanceMetrics.tsx   # Algorithm performance
│   │   └── SemanticSearchPanel.tsx  # HNSW search interface
│   ├── hooks/               # Custom React hooks
│   │   └── useWebSocket.ts          # Real-time communication
│   ├── types/               # TypeScript definitions
│   │   └── index.ts                 # Core type definitions
│   ├── utils/               # Utility functions
│   ├── App.tsx              # Main application component
│   ├── main.tsx            # Application entry point
│   └── App.css             # Global styles
├── public/                  # Static assets
├── dist/                   # Build output
├── package.json            # Dependencies and scripts
├── tsconfig.json           # TypeScript configuration
├── vite.config.ts          # Vite build configuration
└── README.md               # Development instructions
```

## Component Architecture

### Hierarchical Structure

```
App.tsx (Root)
├── Header
│   ├── SystemStatus
│   └── AgentOverview
├── Main Content
│   ├── Left Panel
│   │   ├── AgentStatus
│   │   └── FileExplorer
│   ├── Center Panel (Tabbed)
│   │   ├── ActivityFeed
│   │   ├── SemanticSearchPanel
│   │   ├── DependencyGraphViz
│   │   ├── CollaborationDashboard
│   │   └── PerformanceMetrics
│   └── Right Panel
│       └── CommandInput
└── Footer
    └── SystemMetrics
```

### Component Design Patterns

#### Functional Components with Hooks
All components use modern React patterns:
```typescript
const AgentStatus: React.FC<AgentStatusProps> = ({
  agents,
  activities,
  totalEvents,
  lastEventTime,
  connected
}) => {
  // Hook-based state management
  const [expandedAgent, setExpandedAgent] = useState<string | null>(null);
  
  // Memoized calculations
  const agentStats = useMemo(() => 
    calculateAgentStatistics(agents, activities), 
    [agents, activities]
  );
  
  // Optimized rendering
  return <div className="agent-status">...</div>;
};
```

#### Custom Hooks for Complex Logic
Reusable logic extracted into custom hooks:
```typescript
const useWebSocket = (): UseWebSocketReturn => {
  const [connected, setConnected] = useState(false);
  const [agents, setAgents] = useState<Map<string, AgentConnection>>(new Map());
  
  const handleWebSocketEvent = useCallback((event: WebSocketEvent) => {
    // Event processing logic
  }, []);
  
  return {
    connected,
    agents,
    sendCommand,
    reconnect
  };
};
```

#### Memoization for Performance
Expensive calculations are memoized:
```typescript
const collaborativeActions = useMemo(() => {
  const timeWindow = 10000;
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
```

## State Management Architecture

### Centralized State with useWebSocket
The `useWebSocket` hook serves as the primary state manager:

```typescript
interface UseWebSocketReturn {
  // Connection state
  connected: boolean;
  connecting: boolean;
  error: string | null;
  
  // Core data streams
  agents: Map<string, AgentConnection>;
  activities: AgentActivity[];
  fileChanges: FileChange[];
  commands: HumanCommand[];
  
  // Algorithm-specific streams
  semanticSearchResults: SemanticSearchResult[];
  dependencyAnalyses: DependencyAnalysis[];
  collaborationUpdates: CollaborationUpdate[];
  performanceUpdates: PerformanceUpdate[];
  
  // Actions
  sendCommand: (command: string, targetAgents?: string[]) => void;
  sendSemanticSearch: (query: string) => void;
  reconnect: () => void;
}
```

### Data Flow Architecture

```
MCP Server (WebSocket) 
    ↓
useWebSocket Hook (State Management)
    ↓
App Component (State Distribution)
    ↓
Child Components (Local State + Props)
    ↓
D3.js Visualizations (DOM Manipulation)
```

### Event Processing Pipeline

1. **WebSocket Event Reception**
   ```typescript
   ws.current.onmessage = (event) => {
     const wsEvent: WebSocketEvent = JSON.parse(event.data);
     wsEvent.timestamp = new Date(wsEvent.timestamp);
     handleWebSocketEvent(wsEvent);
   };
   ```

2. **Event Type Routing**
   ```typescript
   const handleWebSocketEvent = useCallback((event: WebSocketEvent) => {
     switch (event.type) {
       case 'agent_activity':
         setActivities(prev => [event.data as AgentActivity, ...prev]);
         break;
       case 'semantic_search_result':
         setSemanticSearchResults(prev => [event.data as SemanticSearchResult, ...prev]);
         break;
       // ... other event types
     }
   }, []);
   ```

3. **State Updates with Memory Bounds**
   ```typescript
   setActivities(prev => {
     const updated = [activity, ...prev];
     return updated.slice(0, MAX_ACTIVITIES); // Memory-bounded
   });
   ```

## Visualization Architecture

### D3.js Integration Patterns

#### Component-D3.js Hybrid Approach
React manages component lifecycle, D3.js manages DOM manipulation:

```typescript
export const DependencyGraphViz: React.FC<DependencyGraphVizProps> = ({
  dependencyAnalyses,
  width = 800,
  height = 600
}) => {
  const svgRef = useRef<SVGSVGElement>(null);
  
  useEffect(() => {
    if (!graphData || !svgRef.current) return;
    
    const svg = d3.select(svgRef.current);
    svg.selectAll("*").remove();
    
    // D3.js visualization logic
    const simulation = d3.forceSimulation(graphData.nodes)
      .force("link", d3.forceLink(graphData.edges))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(width / 2, height / 2));
    
    // React manages component, D3.js manages visualization
    return () => simulation.stop();
  }, [graphData, width, height]);
  
  return <svg ref={svgRef} width={width} height={height} />;
};
```

#### Interactive Visualization Patterns

```typescript
// Mouse interactions with React state updates
nodes
  .on("mouseenter", (_, d) => {
    setHoveredNode(d.id); // Update React state
    
    // D3.js visual updates
    edges.style("opacity", edge => 
      isConnectedToNode(edge, d.id) ? 0.9 : 0.2
    );
  })
  .on("mouseleave", () => {
    setHoveredNode(null);
    edges.style("opacity", 0.6);
  });
```

#### Force Simulation Configuration

```typescript
const simulation = d3.forceSimulation(graphData.nodes)
  .force("link", d3.forceLink<DependencyNode, DependencyEdge>(graphData.edges)
    .id(d => d.id)
    .distance(80)
    .strength(0.3))
  .force("charge", d3.forceManyBody().strength(-300))
  .force("center", d3.forceCenter(width / 2, height / 2))
  .force("collision", d3.forceCollide().radius(d => nodeSize(d.complexity) + 5));
```

### Real-time Animation Strategy

#### Smooth Transitions
```typescript
// Smooth data updates without jarring changes
simulation.on("tick", () => {
  edges
    .attr("x1", d => (d.source as DependencyNode).x!)
    .attr("y1", d => (d.source as DependencyNode).y!)
    .attr("x2", d => (d.target as DependencyNode).x!)
    .attr("y2", d => (d.target as DependencyNode).y!);
  
  nodes.attr("transform", d => `translate(${d.x!},${d.y!})`);
});
```

#### Performance Optimization
```typescript
// Debounced updates for high-frequency events
const debouncedUpdate = useCallback(
  debounce((newData) => {
    updateVisualization(newData);
  }, 100),
  []
);
```

## Performance Optimization

### Memory Management

#### Buffer Limits
```typescript
const MAX_ACTIVITIES = 1000;
const MAX_FILE_CHANGES = 500;
const MAX_SEARCH_RESULTS = 100;

// Automatic cleanup
setActivities(prev => {
  const updated = [activity, ...prev];
  return updated.slice(0, MAX_ACTIVITIES);
});
```

#### Cleanup Patterns
```typescript
useEffect(() => {
  // Setup resources
  const simulation = d3.forceSimulation(nodes);
  
  // Cleanup function
  return () => {
    simulation.stop();
    // Clean up any other resources
  };
}, [dependencies]);
```

### Rendering Performance

#### Memoization Strategies
```typescript
// Expensive calculations cached
const processedData = useMemo(() => {
  return expensiveDataProcessing(rawData);
}, [rawData]);

// Component memoization
const ExpensiveComponent = React.memo(({ data }) => {
  return <ComplexVisualization data={data} />;
}, (prevProps, nextProps) => {
  return prevProps.data.id === nextProps.data.id;
});
```

#### Virtualization for Large Lists
```typescript
// Virtual scrolling for activity feeds
const visibleItems = useMemo(() => {
  const startIndex = Math.floor(scrollTop / itemHeight);
  const endIndex = Math.min(startIndex + visibleCount, activities.length);
  return activities.slice(startIndex, endIndex);
}, [activities, scrollTop, itemHeight, visibleCount]);
```

## WebSocket Architecture

### Connection Management

#### Resilient Connection Handling
```typescript
const connect = useCallback(() => {
  try {
    ws.current = new WebSocket(WS_URL);
    
    ws.current.onopen = () => {
      setConnected(true);
      setError(null);
    };
    
    ws.current.onclose = (event) => {
      setConnected(false);
      // Auto-reconnect unless explicitly closed
      if (event.code !== 1000) {
        scheduleReconnect();
      }
    };
    
    ws.current.onerror = (error) => {
      setError('Connection error');
      scheduleReconnect();
    };
  } catch (error) {
    setError('Failed to connect');
    scheduleReconnect();
  }
}, []);
```

#### Automatic Reconnection
```typescript
const scheduleReconnect = useCallback(() => {
  if (reconnectTimeoutRef.current) return;
  
  reconnectTimeoutRef.current = window.setTimeout(() => {
    reconnectTimeoutRef.current = null;
    connect();
  }, RECONNECT_INTERVAL);
}, [connect]);
```

### Message Processing

#### Type-Safe Event Handling
```typescript
const handleWebSocketEvent = useCallback((event: WebSocketEvent) => {
  // Type-safe event processing
  switch (event.type) {
    case 'agent_connected': {
      const agent = event.data as AgentConnection;
      setAgents(prev => {
        const updated = new Map(prev);
        updated.set(agent.id, agent);
        return updated;
      });
      break;
    }
    
    case 'semantic_search_result': {
      const searchResult = event.data as SemanticSearchResult;
      setSemanticSearchResults(prev => [searchResult, ...prev]);
      break;
    }
  }
}, []);
```

#### Command Broadcasting
```typescript
const sendCommand = useCallback((command: string, targetAgents?: string[]) => {
  if (!connected || !ws.current) return;
  
  const humanCommand: HumanCommand = {
    id: `cmd_${++commandIdCounter.current}`,
    command,
    timestamp: new Date(),
    targetAgents,
    status: 'sent'
  };
  
  ws.current.send(JSON.stringify({
    type: 'human_command',
    data: humanCommand
  }));
}, [connected]);
```

## Error Handling

### Connection Resilience
- **Automatic reconnection** with exponential backoff
- **Connection state indicators** for user awareness
- **Graceful degradation** when disconnected
- **Error message display** with recovery options

### Data Validation
- **Runtime type checking** for WebSocket events
- **Schema validation** for complex data structures
- **Fallback values** for missing or invalid data
- **Error boundaries** to contain component failures

### User Experience
- **Loading states** during connection establishment
- **Empty states** when no data is available
- **Error states** with clear recovery paths
- **Progress indicators** for long-running operations

## Development Workflow

### Hot Reloading Setup
```typescript
// vite.config.ts
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    hot: true,
    proxy: {
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true,
        changeOrigin: true
      }
    }
  }
});
```

### TypeScript Configuration
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "moduleResolution": "node",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

### Testing Strategy
- **Unit tests** for complex data processing logic
- **Component tests** for React component behavior
- **Integration tests** for WebSocket communication
- **Visual regression tests** for D3.js visualizations

## Future Architecture Enhancements

### Planned Improvements
- **Web Workers** for heavy data processing
- **Service Workers** for offline capabilities
- **IndexedDB** for local data persistence
- **WebGL** for 3D visualizations

### Scalability Considerations
- **Code splitting** for large applications
- **Lazy loading** for non-critical components
- **CDN integration** for asset delivery
- **Progressive Web App** capabilities

This architecture provides a solid foundation for the Agrama Observatory while maintaining flexibility for future enhancements and scaling requirements.