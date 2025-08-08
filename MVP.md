# MVP Specification: Agrama CodeGraph MCP Server and Observatory

## Executive Summary

Agrama CodeGraph is a Model Context Protocol (MCP) server that demonstrates the Agrama temporal knowledge graph database in a real-world collaborative AI coding scenario. The system enables multiple AI agents (Claude Code, Cursor, etc.) to work on code projects while humans observe and guide the process through a web-based observatory interface. All interactions, code changes, and decisions are captured in our temporal knowledge graph, creating an unprecedented view into AI-human collaborative software development.

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Agrama CodeGraph MVP                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────┐  │
│  │   AI Agents     │    │  MCP Server     │    │ Web Client  │  │
│  │                 │    │                 │    │             │  │
│  │ • Claude Code   │◄──►│ • Tool Registry │◄──►│ • Observatory│  │
│  │ • Cursor        │    │ • Event Capture │    │ • Command   │  │
│  │ • Custom Agents │    │ • Query Engine  │    │   Center    │  │
│  └─────────────────┘    └─────────────────┘    └─────────────┘  │
│           │                        │                     │      │
│           └────────────────────────┼─────────────────────┘      │
│                                    │                            │
│  ┌─────────────────────────────────┼─────────────────────────┐  │
│  │        Temporal Knowledge Graph Database                 │  │
│  │                                 │                       │  │
│  │ • Code Entities & Relations     │                       │  │
│  │ • Agent Actions & Decisions     │                       │  │
│  │ • Human Commands & Feedback     │                       │  │
│  │ • Temporal Evolution Tracking   │                       │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. MCP Server Implementation

**Purpose**: Bridge between AI agents and our temporal knowledge graph database

```zig
const AgramaCodeGraphServer = struct {
    database: *TemporalGraphDB,
    tool_registry: ToolRegistry,
    event_processor: EventProcessor,
    websocket_server: WebSocketServer,
    
    pub fn init(config: MCPConfig) !AgramaCodeGraphServer {
        const database = try TemporalGraphDB.init(config.db_config);
        const tool_registry = try ToolRegistry.init();
        const event_processor = try EventProcessor.init(database);
        const websocket_server = try WebSocketServer.init(config.ws_port);
        
        // Register core tools
        try tool_registry.register("read_code", readCodeTool);
        try tool_registry.register("write_code", writeCodeTool);
        try tool_registry.register("analyze_dependencies", analyzeDependenciesTool);
        try tool_registry.register("get_context", getContextTool);
        try tool_registry.register("record_decision", recordDecisionTool);
        try tool_registry.register("query_history", queryHistoryTool);
        
        return AgramaCodeGraphServer{
            .database = database,
            .tool_registry = tool_registry,
            .event_processor = event_processor,
            .websocket_server = websocket_server,
        };
    }
    
    pub fn handleMCPRequest(self: *AgramaCodeGraphServer, request: MCPRequest) !MCPResponse {
        // Log all agent interactions
        try self.event_processor.recordEvent(.{
            .timestamp = std.time.timestamp(),
            .agent_id = request.agent_id,
            .tool = request.tool,
            .parameters = request.parameters,
        });
        
        // Process the tool call
        const result = try self.tool_registry.execute(request.tool, request.parameters);
        
        // Update knowledge graph
        try self.updateKnowledgeGraph(request, result);
        
        // Broadcast to web clients
        try self.websocket_server.broadcast(.{
            .type = "agent_action",
            .agent_id = request.agent_id,
            .action = request.tool,
            .result = result,
            .timestamp = std.time.timestamp(),
        });
        
        return MCPResponse{
            .result = result,
            .context = try self.generateContextualInfo(request),
        };
    }
};
```

### 2. Core MCP Tools

**2.1 Code Reading and Analysis**

```zig
const readCodeTool = MCPTool{
    .name = "read_code",
    .description = "Read and analyze code files with full context",
    .parameters = &[_]MCPParameter{
        .{ .name = "file_path", .type = "string", .required = true },
        .{ .name = "include_history", .type = "boolean", .default = "false" },
        .{ .name = "include_dependencies", .type = "boolean", .default = "true" },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const file_path = params.getString("file_path");
            const include_history = params.getBool("include_history");
            const include_deps = params.getBool("include_dependencies");
            
            // Read current file content
            const content = try context.database.getFileContent(file_path, null);
            
            var result = MCPResult.init();
            result.content = content;
            
            // Add historical context if requested
            if (include_history) {
                const history = try context.database.getFileHistory(file_path, .{
                    .limit = 10,
                    .include_changes = true,
                });
                result.history = history;
            }
            
            // Add dependency context
            if (include_deps) {
                const deps = try context.database.analyzeDependencies(file_path, .{
                    .direction = .both,
                    .max_depth = 2,
                });
                result.dependencies = deps;
            }
            
            // Add semantic context - similar code
            const file_embedding = try context.database.getFileEmbedding(file_path);
            const similar = try context.database.semanticSearch(file_embedding, .{
                .k = 5,
                .exclude_self = true,
            });
            result.similar_code = similar;
            
            return result;
        }
    },
};

const writeCodeTool = MCPTool{
    .name = "write_code",
    .description = "Write or modify code with full provenance tracking",
    .parameters = &[_]MCPParameter{
        .{ .name = "file_path", .type = "string", .required = true },
        .{ .name = "content", .type = "string", .required = true },
        .{ .name = "reasoning", .type = "string", .required = true },
        .{ .name = "change_type", .type = "string", .enum = &[_][]const u8{"create", "modify", "delete"} },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const file_path = params.getString("file_path");
            const content = params.getString("content");
            const reasoning = params.getString("reasoning");
            const change_type = params.getString("change_type");
            
            // Create change record
            const change = CodeChange{
                .file_path = file_path,
                .content = content,
                .reasoning = reasoning,
                .change_type = std.meta.stringToEnum(ChangeType, change_type).?,
                .agent_id = context.agent_id,
                .timestamp = std.time.timestamp(),
            };
            
            // Apply change and update knowledge graph
            const change_id = try context.database.applyCodeChange(change);
            
            // Analyze impact
            const impact = try context.database.analyzeChangeImpact(change_id, .{
                .max_depth = 3,
                .include_tests = true,
            });
            
            // Generate embedding for new/modified content
            if (change_type != "delete") {
                const embedding = try context.embedding_service.generateEmbedding(content);
                try context.database.updateFileEmbedding(file_path, embedding);
            }
            
            return MCPResult{
                .change_id = change_id,
                .impact_analysis = impact,
                .success = true,
            };
        }
    },
};
```

**2.2 Context and Decision Tools**

```zig
const getContextTool = MCPTool{
    .name = "get_context",
    .description = "Get comprehensive context for current development task",
    .parameters = &[_]MCPParameter{
        .{ .name = "focus_area", .type = "string", .required = true },
        .{ .name = "time_window", .type = "string", .default = "1h" },
        .{ .name = "include_human_feedback", .type = "boolean", .default = "true" },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const focus_area = params.getString("focus_area");
            const time_window = parseTimeWindow(params.getString("time_window"));
            const include_feedback = params.getBool("include_human_feedback");
            
            // Get relevant code entities
            const entities = try context.database.findRelevantEntities(focus_area, .{
                .max_results = 20,
                .time_range = time_window,
            });
            
            // Get recent agent activities
            const activities = try context.database.getRecentActivities(.{
                .time_range = time_window,
                .related_to = entities,
            });
            
            // Get human feedback if requested
            var feedback: ?[]HumanFeedback = null;
            if (include_feedback) {
                feedback = try context.database.getHumanFeedback(.{
                    .time_range = time_window,
                    .related_to = entities,
                });
            }
            
            // Generate contextual summary
            const summary = try context.llm_service.generateContextSummary(.{
                .entities = entities,
                .activities = activities,
                .feedback = feedback,
                .focus = focus_area,
            });
            
            return MCPResult{
                .entities = entities,
                .recent_activities = activities,
                .human_feedback = feedback,
                .summary = summary,
            };
        }
    },
};

const recordDecisionTool = MCPTool{
    .name = "record_decision",
    .description = "Record an important development decision with reasoning",
    .parameters = &[_]MCPParameter{
        .{ .name = "decision", .type = "string", .required = true },
        .{ .name = "reasoning", .type = "string", .required = true },
        .{ .name = "alternatives_considered", .type = "array", .items = "string" },
        .{ .name = "confidence", .type = "number", .minimum = 0, .maximum = 1 },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const decision_record = DecisionRecord{
                .decision = params.getString("decision"),
                .reasoning = params.getString("reasoning"),
                .alternatives = params.getStringArray("alternatives_considered"),
                .confidence = params.getFloat("confidence"),
                .agent_id = context.agent_id,
                .timestamp = std.time.timestamp(),
                .context_snapshot = try context.database.captureCurrentContext(),
            };
            
            const decision_id = try context.database.recordDecision(decision_record);
            
            return MCPResult{
                .decision_id = decision_id,
                .success = true,
            };
        }
    },
};
```

### 3. Web Observatory Interface

**3.1 Real-time Dashboard**

```typescript
// Frontend React component for the Observatory
const AgramaCodeGraphObservatory: React.FC = () => {
    const [agentActivities, setAgentActivities] = useState<AgentActivity[]>([]);
    const [knowledgeGraph, setKnowledgeGraph] = useState<GraphData>({});
    const [userCommands, setUserCommands] = useState<string>('');
    const [selectedTimeRange, setSelectedTimeRange] = useState('1h');
    
    // WebSocket connection to MCP server
    useEffect(() => {
        const ws = new WebSocket('ws://localhost:8080/observatory');
        
        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            
            switch (data.type) {
                case 'agent_action':
                    setAgentActivities(prev => [data, ...prev.slice(0, 99)]);
                    updateKnowledgeGraph(data);
                    break;
                case 'graph_update':
                    setKnowledgeGraph(data.graph);
                    break;
                case 'human_command_result':
                    showNotification(data.result);
                    break;
            }
        };
        
        return () => ws.close();
    }, []);
    
    const sendCommand = async (command: string) => {
        const response = await fetch('/api/human-command', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
                command, 
                timestamp: Date.now(),
                session_id: sessionId 
            })
        });
        
        const result = await response.json();
        setUserCommands('');
    };
    
    return (
        <div className="observatory-container">
            <Header>
                <h1>Agrama CodeGraph Observatory</h1>
                <TimeRangeSelector 
                    value={selectedTimeRange} 
                    onChange={setSelectedTimeRange} 
                />
            </Header>
            
            <div className="main-layout">
                <div className="left-panel">
                    <AgentActivityFeed activities={agentActivities} />
                    <HumanCommandInterface 
                        value={userCommands}
                        onChange={setUserCommands}
                        onSubmit={sendCommand}
                    />
                </div>
                
                <div className="center-panel">
                    <KnowledgeGraphVisualization 
                        data={knowledgeGraph}
                        timeRange={selectedTimeRange}
                    />
                </div>
                
                <div className="right-panel">
                    <CodeContextViewer />
                    <DecisionTimeline />
                    <PerformanceMetrics />
                </div>
            </div>
        </div>
    );
};

// Knowledge Graph Visualization Component
const KnowledgeGraphVisualization: React.FC<{
    data: GraphData;
    timeRange: string;
}> = ({ data, timeRange }) => {
    const svgRef = useRef<SVGSVGElement>(null);
    
    useEffect(() => {
        if (!svgRef.current || !data.nodes) return;
        
        const svg = d3.select(svgRef.current);
        svg.selectAll("*").remove();
        
        const simulation = d3.forceSimulation(data.nodes)
            .force("link", d3.forceLink(data.edges).id(d => d.id))
            .force("charge", d3.forceManyBody().strength(-300))
            .force("center", d3.forceCenter(400, 300));
        
        // Render nodes with different colors for different entity types
        const nodes = svg.selectAll(".node")
            .data(data.nodes)
            .enter().append("circle")
            .attr("class", "node")
            .attr("r", d => Math.sqrt(d.importance) * 10)
            .attr("fill", d => getNodeColor(d.type))
            .call(d3.drag()
                .on("start", dragstarted)
                .on("drag", dragged)
                .on("end", dragended));
        
        // Render edges with temporal weight visualization
        const links = svg.selectAll(".link")
            .data(data.edges)
            .enter().append("line")
            .attr("class", "link")
            .attr("stroke-width", d => Math.sqrt(d.weight) * 2)
            .attr("stroke", d => getEdgeColor(d.age))
            .attr("opacity", d => Math.max(0.3, 1 - d.age / 86400)); // Fade with age
        
        simulation.on("tick", () => {
            links
                .attr("x1", d => d.source.x)
                .attr("y1", d => d.source.y)
                .attr("x2", d => d.target.x)
                .attr("y2", d => d.target.y);
            
            nodes
                .attr("cx", d => d.x)
                .attr("cy", d => d.y);
        });
        
    }, [data, timeRange]);
    
    return (
        <div className="graph-container">
            <svg ref={svgRef} width="800" height="600" />
            <GraphControls />
        </div>
    );
};
```

**3.2 Human Command Interface**

```typescript
const HumanCommandInterface: React.FC<{
    value: string;
    onChange: (value: string) => void;
    onSubmit: (command: string) => void;
}> = ({ value, onChange, onSubmit }) => {
    const [suggestions, setSuggestions] = useState<CommandSuggestion[]>([]);
    
    const commandTemplates = [
        {
            pattern: "focus on {area}",
            description: "Direct agents to focus on specific code area",
            example: "focus on authentication module"
        },
        {
            pattern: "analyze impact of {change}",
            description: "Request impact analysis of recent changes",
            example: "analyze impact of database schema changes"
        },
        {
            pattern: "explain decision {decision_id}",
            description: "Request explanation of agent decision",
            example: "explain decision dec_12345"
        },
        {
            pattern: "review code in {file_path}",
            description: "Request human review of specific code",
            example: "review code in src/auth/login.ts"
        },
        {
            pattern: "pause work on {task}",
            description: "Pause agent work on specific task",
            example: "pause work on user registration"
        }
    ];
    
    const handleInputChange = (newValue: string) => {
        onChange(newValue);
        
        // Generate command suggestions
        const matches = commandTemplates.filter(template =>
            template.pattern.toLowerCase().includes(newValue.toLowerCase()) ||
            newValue.toLowerCase().includes(template.pattern.split(' ')[0])
        );
        setSuggestions(matches);
    };
    
    return (
        <div className="command-interface">
            <div className="command-input-container">
                <textarea
                    value={value}
                    onChange={(e) => handleInputChange(e.target.value)}
                    placeholder="Enter command for AI agents..."
                    className="command-input"
                    rows={3}
                />
                <button 
                    onClick={() => onSubmit(value)}
                    disabled={!value.trim()}
                    className="send-command-btn"
                >
                    Send Command
                </button>
            </div>
            
            {suggestions.length > 0 && (
                <div className="command-suggestions">
                    <h4>Suggested Commands:</h4>
                    {suggestions.map((suggestion, index) => (
                        <div key={index} className="suggestion-item">
                            <div className="suggestion-pattern">{suggestion.pattern}</div>
                            <div className="suggestion-description">{suggestion.description}</div>
                            <div className="suggestion-example">e.g., {suggestion.example}</div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
};
```

### 4. Database Schema for MVP

```zig
// Core entities for the MVP use case
const MVPSchema = struct {
    // Code entities
    files: TemporalTable(FileEntity),
    functions: TemporalTable(FunctionEntity),
    classes: TemporalTable(ClassEntity),
    modules: TemporalTable(ModuleEntity),
    
    // Agent entities
    agents: TemporalTable(AgentEntity),
    agent_actions: TemporalTable(AgentAction),
    decisions: TemporalTable(DecisionRecord),
    
    // Human interaction
    human_commands: TemporalTable(HumanCommand),
    human_feedback: TemporalTable(HumanFeedback),
    
    // Relationships
    dependencies: TemporalEdgeTable(DependencyRelation),
    similarities: TemporalEdgeTable(SimilarityRelation),
    agent_interactions: TemporalEdgeTable(AgentInteraction),
    
    // Embeddings and indices
    code_embeddings: HNSWIndex(f32, 768),
    agent_behavior_embeddings: HNSWIndex(f32, 256),
};

const FileEntity = struct {
    id: u128,
    path: []const u8,
    content: []const u8,
    language: ProgrammingLanguage,
    size_bytes: u64,
    line_count: u32,
    last_modified_by: AgentID,
    embedding: MatryoshkaEmbedding,
    
    // Temporal metadata
    created_at: i64,
    modified_at: i64,
    valid_from: i64,
    valid_to: ?i64,
};

const AgentAction = struct {
    id: u128,
    agent_id: AgentID,
    action_type: ActionType,
    target_entity: EntityID,
    parameters: HashMap([]const u8, Value),
    result: ActionResult,
    reasoning: ?[]const u8,
    confidence: f32,
    execution_time_ms: u32,
    
    // Context
    context_entities: []EntityID,
    predecessor_actions: []ActionID,
    
    // Temporal
    started_at: i64,
    completed_at: i64,
};

const HumanCommand = struct {
    id: u128,
    command_text: []const u8,
    command_type: CommandType,
    target_agents: ?[]AgentID,
    priority: Priority,
    status: CommandStatus,
    
    // Processing
    parsed_intent: ?Intent,
    assigned_agents: []AgentID,
    completion_criteria: ?[]const u8,
    
    // Results
    execution_results: []ActionResult,
    human_satisfaction: ?f32,
    
    // Temporal
    issued_at: i64,
    acknowledged_at: ?i64,
    completed_at: ?i64,
};
```

### 5. Installation and Setup

**5.1 Database Installation**

```bash
# Install Agrama database
curl -sSL https://install.agrama.dev | bash

# Initialize database for project
agrama init ./my-project
# Creates .agrama/ directory with:
# - config.toml
# - database files
# - embeddings cache

# Configure database
cat > .agrama/config.toml << EOF
[database]
storage_path = ".agrama/db"
max_memory_mb = 2048
enable_embeddings = true

[mcp_server]
port = 3001
host = "localhost"
enable_web_ui = true
web_ui_port = 3000

[agents]
max_concurrent = 5
default_timeout_ms = 30000

[embeddings]
model = "text-embedding-3-small"
dimensions = [64, 256, 768]
cache_size_mb = 512
EOF
```

**5.2 MCP Server Setup**

```bash
# Start MCP server
agrama codegraph serve

# Output:
# ✅ Agrama database initialized
# ✅ Agrama CodeGraph MCP server listening on port 3001
# ✅ Web Observatory available at http://localhost:3000
# ✅ Ready for agent connections
```

**5.3 Agent Configuration**

**Claude Code Integration**:

```json
// Claude Desktop config.json
{
  "mcpServers": {
    "agrama-codegraph": {
      "command": "npx",
      "args": ["@agrama/codegraph-mcp-client"],
      "env": {
        "AGRAMA_SERVER": "http://localhost:3001",
        "AGRAMA_PROJECT": "./my-project"
      }
    }
  }
}
```

**Cursor Integration**:

```json
// Cursor settings.json
{
  "cursor.mcp.servers": [
    {
      "name": "agrama-codegraph",
      "url": "http://localhost:3001",
      "tools": [
        "read_code",
        "write_code", 
        "analyze_dependencies",
        "get_context",
        "record_decision"
      ]
    }
  ]
}
```

### 6. User Workflows

**6.1 Initial Setup Flow**

1. Developer installs Agrama database
1. Configures project with `agrama init`
1. Starts Agrama CodeGraph MCP server with `agrama codegraph serve`
1. Connects AI agents (Claude, Cursor) via MCP configuration
1. Opens Observatory web interface at `localhost:3000`

**6.2 Active Development Flow**

1. **AI Agent Works**: Claude analyzes codebase using MCP tools
1. **Observatory Shows**: Real-time visualization of agent actions
1. **Human Observes**: Developer sees knowledge graph evolving
1. **Human Guides**: Issues commands like "focus on authentication"
1. **Agents Respond**: Adjust behavior based on human input
1. **Knowledge Accumulates**: All interactions stored in temporal graph

**6.3 Review and Analysis Flow**

1. **Developer Reviews**: Uses Observatory to see what agents accomplished
1. **Analyzes Decisions**: Clicks on agent decisions to see reasoning
1. **Provides Feedback**: Comments on agent actions through web interface
1. **Queries History**: Uses temporal queries to understand evolution
1. **Optimizes Process**: Adjusts agent behavior based on observations

### 7. MVP Success Metrics

**Technical Metrics**:

- **Response Time**: <100ms for MCP tool calls
- **Throughput**: 50+ agent actions per minute
- **Storage Efficiency**: <100MB for 10K code entities
- **Web UI Latency**: <500ms for graph updates

**User Experience Metrics**:

- **Agent Onboarding**: <5 minutes to connect first agent
- **Command Response**: Agents acknowledge human commands within 10 seconds
- **Context Accuracy**: 90%+ relevant context in agent responses
- **Observable Insights**: Users report new insights within first hour

**Collaboration Metrics**:

- **Multi-Agent Coordination**: 3+ agents working simultaneously
- **Human-AI Interaction**: 10+ meaningful command exchanges per session
- **Knowledge Evolution**: Observable graph growth and pattern emergence
- **Decision Traceability**: 100% of agent decisions recorded and explainable

### 8. Technical Implementation Plan

**Week 1-2: Core MCP Server**

- Implement basic MCP server with tool registry
- Core tools: read_code, write_code, get_context
- Basic database integration
- WebSocket server for real-time updates

**Week 3-4: Web Observatory**

- React-based web interface
- Real-time knowledge graph visualization
- Agent activity feed
- Basic human command interface

**Week 5-6: Agent Integration**

- Claude Code MCP client
- Cursor integration
- Testing with multiple concurrent agents
- Performance optimization

**Week 7-8: Advanced Features**

- Decision recording and analysis
- Temporal query interface
- Human feedback integration
- Polish and deployment scripts

### 9. Risk Mitigation

**Technical Risks**:

- **MCP Compatibility**: Test with multiple agent versions
- **Performance**: Load testing with realistic agent workloads
- **Data Consistency**: CRDT validation with concurrent agents

**User Experience Risks**:

- **Complexity**: Simple initial UI, advanced features optional
- **Reliability**: Graceful degradation when agents disconnect
- **Learning Curve**: Comprehensive tutorials and examples

**Deployment Risks**:

- **Portability**: Docker containers for consistent deployment
- **Security**: Local-only by default, HTTPS for remote access
- **Backup**: Automated database backup and recovery

### 10. Future Expansion

**Phase 2 Additions**:

- Integration with more AI coding tools
- Advanced temporal analytics
- Team collaboration features
- Custom agent development SDK

**Phase 3 Vision**:

- Multi-project knowledge graphs
- AI agent marketplace
- Enterprise deployment options
- Research collaboration platform

## Conclusion

The Agrama CodeGraph MVP demonstrates the Agrama temporal knowledge graph database in a compelling real-world scenario. By enabling seamless collaboration between AI agents and humans through MCP, we create an unprecedented observatory into AI-assisted software development. The system captures not just code changes but the entire decision-making process, creating a living knowledge base that evolves with each interaction.

This MVP positions Agrama as the foundation for the future of AI-assisted software development, with CodeGraph serving as the primary demonstration of multi-agent collaboration capabilities, where human insight guides AI capability in an observable, traceable, and continuously improving collaboration.