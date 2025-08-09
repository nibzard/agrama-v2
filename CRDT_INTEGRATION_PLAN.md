# CRDT Integration Plan for Agrama CodeGraph

## Executive Summary

This document outlines the implementation plan for integrating Conflict-free Replicated Data Types (CRDTs) into Agrama CodeGraph to enable seamless multi-agent collaboration without conflicts. The integration will replace the current file locking mechanism with a more sophisticated real-time collaborative editing system.

## Background Research

### CRDT Technology Assessment

**Yjs CRDT Library Analysis:**
- **Core Feature**: Provides shared data types (Y.Text, Y.Map, Y.Array) that can be manipulated concurrently across multiple clients
- **Conflict Resolution**: Automatic merging without merge conflicts using CRDT algorithms
- **Network Agnostic**: Supports WebSocket, WebRTC, and custom providers
- **Performance**: Efficient data structures using linked lists with minimal overhead
- **Offline Support**: Enables offline editing with eventual consistency

**CRDT vs Operational Transformation:**
- **CRDT Advantages**: Simpler to implement correctly, predictable merge behavior, no complex transformation functions
- **OT Disadvantages**: "Implementing OT sucks" - highly complex, error-prone transformation algorithms
- **Decision**: Choose CRDT for simpler conflict resolution and better reliability

### Multi-Agent Collaboration Requirements

**Key Scenarios to Support:**
1. **Simultaneous File Editing**: Multiple AI agents editing the same code file
2. **Real-time Synchronization**: Instant propagation of changes across all agents
3. **Conflict-Free Merging**: Automatic resolution without blocking operations
4. **Complete Audit Trail**: Full provenance tracking of collaborative changes
5. **Observatory Visualization**: Real-time display of collaborative conflicts and resolutions

## Technical Architecture

### 1. CRDT Document Model

```zig
// New CRDT-aware document structure
pub const CRDTDocument = struct {
    id: []const u8,                    // Unique document identifier
    yjs_doc: YjsDocument,              // Yjs document instance
    local_state: DocumentState,        // Local CRDT state
    version_vector: VersionVector,     // Logical timestamp tracking
    agent_cursors: AgentCursorMap,     // Real-time cursor positions
    conflict_log: ArrayList(ConflictEvent), // Resolved conflicts history
    
    pub fn applyOperation(self: *CRDTDocument, op: CRDTOperation) !void;
    pub fn synchronizeWith(self: *CRDTDocument, remote_doc: *CRDTDocument) !void;
    pub fn getConflicts(self: *CRDTDocument) []ConflictEvent;
};

// CRDT operation for tracking changes
pub const CRDTOperation = struct {
    operation_id: u128,                // Global unique operation ID
    agent_id: []const u8,             // Agent performing operation
    operation_type: OperationType,     // Insert, delete, modify
    position: Position,                // Location in document
    content: []const u8,              // Operation payload
    timestamp: VectorClock,            // Logical timestamp
    dependencies: []u128,              // Causal dependencies
};
```

### 2. Enhanced MCP Tools with CRDT Support

```zig
// Updated read_code tool with collaborative awareness
const readCodeCRDTTool = MCPTool{
    .name = "read_code_collaborative",
    .description = "Read code file with real-time collaborative context",
    .parameters = &[_]MCPParameter{
        .{ .name = "path", .type = "string", .required = true },
        .{ .name = "include_agent_cursors", .type = "boolean", .default = "true" },
        .{ .name = "include_recent_changes", .type = "boolean", .default = "true" },
        .{ .name = "conflict_resolution", .type = "string", .enum = &[_][]const u8{"automatic", "manual", "preview"} },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const file_path = params.getString("path");
            
            // Get CRDT document for file
            const crdt_doc = try context.crdt_manager.getOrCreateDocument(file_path);
            
            // Get current merged content
            const content = try crdt_doc.getCurrentContent();
            
            var result = MCPResult.init();
            result.content = content;
            
            // Add collaborative context
            if (params.getBool("include_agent_cursors")) {
                result.agent_cursors = try crdt_doc.getAgentCursors();
            }
            
            if (params.getBool("include_recent_changes")) {
                result.recent_operations = try crdt_doc.getRecentOperations(10);
            }
            
            // Include any pending conflicts
            result.conflicts = try crdt_doc.getConflicts();
            
            return result;
        }
    },
};

// Updated write_code tool with CRDT operations
const writeCodeCRDTTool = MCPTool{
    .name = "write_code_collaborative", 
    .description = "Write code with CRDT conflict resolution",
    .parameters = &[_]MCPParameter{
        .{ .name = "path", .type = "string", .required = true },
        .{ .name = "content", .type = "string", .required = true },
        .{ .name = "operation_type", .type = "string", .enum = &[_][]const u8{"insert", "replace", "delete"} },
        .{ .name = "position", .type = "object" }, // {line, column, offset}
        .{ .name = "reasoning", .type = "string", .required = true },
    },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            const file_path = params.getString("path");
            const content = params.getString("content");
            const operation_type = params.getString("operation_type");
            const reasoning = params.getString("reasoning");
            
            // Create CRDT operation
            const operation = CRDTOperation{
                .operation_id = generateOperationId(),
                .agent_id = context.agent_id,
                .operation_type = std.meta.stringToEnum(OperationType, operation_type).?,
                .content = content,
                .timestamp = try context.vector_clock.tick(),
                .dependencies = try context.crdt_manager.getDependencies(file_path),
            };
            
            // Get or create CRDT document
            const crdt_doc = try context.crdt_manager.getOrCreateDocument(file_path);
            
            // Apply operation with conflict detection
            const result = try crdt_doc.applyOperation(operation);
            
            // Broadcast to other agents immediately
            try context.crdt_manager.broadcastOperation(operation);
            
            // Record in audit trail
            try context.database.recordCRDTOperation(operation, reasoning);
            
            return MCPResult{
                .success = true,
                .operation_id = operation.operation_id,
                .conflicts_resolved = result.conflicts_resolved,
                .merged_content = result.final_content,
                .affected_agents = result.affected_agents,
            };
        }
    },
};
```

### 3. CRDT Manager Implementation

```zig
// Core CRDT coordination system
pub const CRDTManager = struct {
    allocator: Allocator,
    documents: HashMap([]const u8, CRDTDocument, HashContext, std.hash_map.default_max_load_percentage),
    agent_sessions: HashMap([]const u8, AgentCRDTSession, HashContext, std.hash_map.default_max_load_percentage),
    vector_clock: VectorClock,
    websocket_server: *WebSocketServer,
    conflict_resolver: ConflictResolver,
    mutex: Mutex,
    
    pub fn init(allocator: Allocator, websocket_server: *WebSocketServer) CRDTManager;
    
    /// Get or create CRDT document for file
    pub fn getOrCreateDocument(self: *CRDTManager, path: []const u8) !*CRDTDocument {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const gop = try self.documents.getOrPut(path);
        if (!gop.found_existing) {
            gop.value_ptr.* = try CRDTDocument.init(self.allocator, path);
        }
        return gop.value_ptr;
    }
    
    /// Broadcast operation to all connected agents
    pub fn broadcastOperation(self: *CRDTManager, operation: CRDTOperation) !void {
        const event = try std.fmt.allocPrint(self.allocator, 
            "{{\"type\":\"crdt_operation\",\"operation_id\":\"{}\",\"agent_id\":\"{s}\",\"path\":\"{s}\",\"timestamp\":{d}}}",
            .{operation.operation_id, operation.agent_id, operation.path, std.time.timestamp()}
        );
        defer self.allocator.free(event);
        
        self.websocket_server.broadcast(event);
    }
    
    /// Handle incoming CRDT operations from remote agents
    pub fn handleRemoteOperation(self: *CRDTManager, operation: CRDTOperation) !void {
        const doc = try self.getOrCreateDocument(operation.path);
        
        // Check for conflicts and resolve
        const conflicts = try doc.detectConflicts(operation);
        if (conflicts.len > 0) {
            const resolution = try self.conflict_resolver.resolve(conflicts, operation);
            try doc.applyResolution(resolution);
            
            // Broadcast conflict resolution
            try self.broadcastConflictResolution(resolution);
        } else {
            // No conflicts, apply directly
            try doc.applyOperation(operation);
        }
    }
    
    /// Synchronize with another CRDT manager (for distributed setups)
    pub fn synchronizeWith(self: *CRDTManager, remote: *CRDTManager) !void {
        // Implementation for cross-instance synchronization
        var doc_iterator = self.documents.iterator();
        while (doc_iterator.next()) |entry| {
            const local_doc = entry.value_ptr;
            if (remote.documents.get(entry.key_ptr.*)) |*remote_doc| {
                try local_doc.synchronizeWith(remote_doc);
            }
        }
    }
};

// Agent session with CRDT-specific state
pub const AgentCRDTSession = struct {
    agent_id: []const u8,
    vector_clock: VectorClock,
    active_documents: ArrayList([]const u8),
    cursor_positions: HashMap([]const u8, CursorPosition, HashContext, std.hash_map.default_max_load_percentage),
    pending_operations: ArrayList(CRDTOperation),
    
    pub fn updateCursor(self: *AgentCRDTSession, document_path: []const u8, position: CursorPosition) !void;
    pub fn queueOperation(self: *AgentCRDTSession, operation: CRDTOperation) !void;
};
```

### 4. Conflict Resolution Strategies

```zig
// Conflict resolution for code editing scenarios  
pub const ConflictResolver = struct {
    allocator: Allocator,
    resolution_strategies: HashMap([]const u8, ResolutionStrategy, HashContext, std.hash_map.default_max_load_percentage),
    
    pub const ResolutionStrategy = enum {
        last_writer_wins,        // Simple timestamp-based resolution
        semantic_merge,          // Intelligent code-aware merging
        agent_priority,          // Prioritize specific agents
        human_intervention,      // Request human resolution
        syntax_preserving,       // Maintain syntactic correctness
    };
    
    pub fn resolve(self: *ConflictResolver, conflicts: []ConflictEvent, operation: CRDTOperation) !ConflictResolution {
        // Determine appropriate strategy based on conflict type
        const strategy = self.selectStrategy(conflicts, operation);
        
        return switch (strategy) {
            .semantic_merge => try self.semanticMerge(conflicts, operation),
            .syntax_preserving => try self.syntaxPreservingMerge(conflicts, operation),
            .last_writer_wins => try self.lastWriterWins(conflicts, operation),
            .agent_priority => try self.agentPriorityMerge(conflicts, operation),
            .human_intervention => try self.requestHumanIntervention(conflicts, operation),
        };
    }
    
    fn semanticMerge(self: *ConflictResolver, conflicts: []ConflictEvent, operation: CRDTOperation) !ConflictResolution {
        // Implement intelligent code-aware conflict resolution
        // - Preserve syntactic structure
        // - Merge compatible changes
        // - Flag semantically incompatible changes for review
        
        var resolution = ConflictResolution.init(self.allocator);
        
        for (conflicts) |conflict| {
            // Analyze AST changes
            const ast_analysis = try self.analyzeASTConflict(conflict, operation);
            
            if (ast_analysis.is_compatible) {
                // Auto-merge compatible changes
                try resolution.merged_operations.append(try self.mergeOperations(conflict.base_op, operation));
            } else {
                // Request human review for incompatible semantic changes
                try resolution.requires_human_review.append(conflict);
            }
        }
        
        return resolution;
    }
};
```

### 5. Observatory Integration

```typescript
// Enhanced Observatory components for CRDT visualization
const CRDTCollaborationView: React.FC = () => {
    const [crdtDocuments, setCRDTDocuments] = useState<Map<string, CRDTDocument>>(new Map());
    const [agentCursors, setAgentCursors] = useState<Map<string, AgentCursor[]>>(new Map());
    const [conflictEvents, setConflictEvents] = useState<ConflictEvent[]>([]);
    
    useEffect(() => {
        const ws = new WebSocket('ws://localhost:8080/observatory');
        
        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            
            switch (data.type) {
                case 'crdt_operation':
                    updateCRDTDocument(data.path, data.operation);
                    break;
                case 'agent_cursor_update':
                    updateAgentCursor(data.agent_id, data.path, data.position);
                    break;
                case 'conflict_detected':
                    addConflictEvent(data.conflict);
                    break;
                case 'conflict_resolved':
                    resolveConflictEvent(data.resolution);
                    break;
            }
        };
        
        return () => ws.close();
    }, []);
    
    return (
        <div className="crdt-collaboration-container">
            <div className="collaborative-editor-panel">
                <CollaborativeCodeEditor 
                    documents={crdtDocuments}
                    agentCursors={agentCursors}
                    onCursorUpdate={handleCursorUpdate}
                />
            </div>
            
            <div className="conflict-resolution-panel">
                <ConflictResolutionView 
                    conflicts={conflictEvents}
                    onResolveConflict={handleConflictResolution}
                />
            </div>
            
            <div className="agent-activity-panel">
                <RealTimeAgentActivity 
                    operations={crdtOperations}
                    showConflicts={true}
                />
            </div>
        </div>
    );
};

// Real-time collaborative code editor component
const CollaborativeCodeEditor: React.FC<{
    documents: Map<string, CRDTDocument>;
    agentCursors: Map<string, AgentCursor[]>;
    onCursorUpdate: (path: string, position: CursorPosition) => void;
}> = ({ documents, agentCursors, onCursorUpdate }) => {
    const [selectedDocument, setSelectedDocument] = useState<string>('');
    const editorRef = useRef<HTMLDivElement>(null);
    
    // Real-time cursor visualization
    const renderAgentCursors = (path: string) => {
        const cursors = agentCursors.get(path) || [];
        
        return cursors.map(cursor => (
            <div 
                key={cursor.agent_id}
                className="agent-cursor"
                style={{
                    position: 'absolute',
                    top: cursor.position.line * 20, // Approximate line height
                    left: cursor.position.column * 8, // Approximate char width
                    borderLeft: `2px solid ${getAgentColor(cursor.agent_id)}`,
                    height: '20px',
                }}
            >
                <div className="agent-cursor-label">
                    {cursor.agent_name}
                </div>
            </div>
        ));
    };
    
    return (
        <div className="collaborative-editor">
            <div className="document-tabs">
                {Array.from(documents.keys()).map(path => (
                    <button 
                        key={path}
                        onClick={() => setSelectedDocument(path)}
                        className={path === selectedDocument ? 'active' : ''}
                    >
                        {path}
                        {agentCursors.get(path)?.length > 0 && (
                            <span className="active-agents-indicator">
                                {agentCursors.get(path).length}
                            </span>
                        )}
                    </button>
                ))}
            </div>
            
            <div ref={editorRef} className="editor-content">
                {selectedDocument && (
                    <>
                        <CodeMirrorEditor 
                            value={documents.get(selectedDocument)?.content || ''}
                            onChange={(value, position) => onCursorUpdate(selectedDocument, position)}
                            readOnly={true} // Observatory is read-only
                        />
                        {renderAgentCursors(selectedDocument)}
                    </>
                )}
            </div>
        </div>
    );
};
```

## Implementation Roadmap

### Phase 1: CRDT Foundation (Week 1-2)
- [ ] **Research CRDT Integration Patterns**: Study WebAssembly integration for Yjs in Zig
- [ ] **Design CRDT Document Model**: Define data structures and interfaces
- [ ] **Implement Basic CRDT Operations**: Insert, delete, update operations
- [ ] **Create Vector Clock System**: Logical timestamp tracking for operations

### Phase 2: MCP Tool Enhancement (Week 2-3)  
- [ ] **Extend read_code Tool**: Add collaborative awareness and cursor tracking
- [ ] **Enhance write_code Tool**: Implement CRDT operation generation
- [ ] **Add Conflict Detection**: Real-time conflict identification
- [ ] **Implement Basic Resolution**: Last-writer-wins and simple merge strategies

### Phase 3: Real-time Synchronization (Week 3-4)
- [ ] **Enhance WebSocket Protocol**: Add CRDT operation broadcasting
- [ ] **Implement Agent Cursor Tracking**: Real-time position synchronization
- [ ] **Add Operation Ordering**: Ensure causal consistency across agents
- [ ] **Create Conflict Event System**: Real-time conflict notification

### Phase 4: Advanced Conflict Resolution (Week 4-5)
- [ ] **Semantic-Aware Merging**: AST-based conflict resolution for code
- [ ] **Syntax-Preserving Strategies**: Maintain code correctness during merges
- [ ] **Human Intervention Hooks**: Flag complex conflicts for manual resolution
- [ ] **Performance Optimization**: Efficient CRDT operations for large files

### Phase 5: Observatory Integration (Week 5-6)
- [ ] **Collaborative Editor View**: Real-time multi-agent editing visualization
- [ ] **Conflict Resolution Interface**: Interactive conflict management
- [ ] **Agent Cursor Visualization**: Show real-time agent positions
- [ ] **Performance Metrics**: CRDT operation latency and throughput monitoring

## Success Criteria

### Technical Targets
- **Sub-50ms CRDT Operation Latency**: Operations propagate in real-time
- **3+ Concurrent Agent Support**: Multiple agents edit simultaneously without conflicts
- **100% Conflict Resolution**: All conflicts automatically resolved or flagged
- **Zero Data Loss**: Complete audit trail of all collaborative operations
- **Syntactic Correctness**: Merged code maintains valid syntax

### User Experience Goals
- **Seamless Collaboration**: Agents work together without blocking
- **Observable Conflicts**: All conflicts visible in Observatory interface
- **Predictable Behavior**: Deterministic conflict resolution outcomes
- **Complete Traceability**: Full history of collaborative decision-making

## Risk Mitigation

### Technical Risks
- **CRDT Complexity**: Start with simple text operations, gradually add code-aware features
- **Performance Impact**: Profile CRDT operations, optimize hot paths
- **Memory Usage**: Implement garbage collection for old operations
- **Network Overhead**: Compress CRDT operations for efficient transmission

### Integration Risks  
- **Backward Compatibility**: Maintain existing MCP tool interfaces
- **WebSocket Reliability**: Implement reconnection and state recovery
- **Agent Synchronization**: Handle agent disconnection/reconnection gracefully

## Future Extensions

### Advanced Features
- **Distributed CRDT Sync**: Cross-instance collaboration
- **Offline Agent Support**: Local operation queuing with eventual sync
- **Branch-based Collaboration**: Git-like branching for experimental changes
- **AI-Assisted Conflict Resolution**: Machine learning for intelligent merging

This CRDT integration will transform Agrama from a sequential file-locking system into a true real-time collaborative AI development platform, enabling unprecedented multi-agent cooperation without conflicts.