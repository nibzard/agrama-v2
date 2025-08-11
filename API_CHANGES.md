# API Changes and Breaking Changes

This document outlines API changes and breaking changes introduced through the primitive-based architecture implementation and associated fixes.

## Overview

The transition to primitive-based architecture represents a significant API evolution from the previous MCP tool-based approach. While this provides much more power and flexibility, it introduces changes that developers need to understand.

## Major API Changes

### 1. Primitive-Based Interface

**Previous**: Complex MCP tools with many parameters
**New**: 5 core primitives with composable operations

#### New Core Primitives API:
```zig
// STORE primitive - Universal storage with metadata
store(key: string, content: string, metadata?: object) -> result

// RETRIEVE primitive - Data access with context
retrieve(key: string, include_history?: boolean) -> result

// SEARCH primitive - Unified search across indices
search(query: string, mode: "semantic"|"lexical"|"hybrid", options?: object) -> results

// LINK primitive - Knowledge graph relationships
link(source: string, target: string, relationship: string, metadata?: object) -> result

// TRANSFORM primitive - Data transformation operations
transform(operation: string, input: any, parameters?: object) -> result
```

### 2. Context Management Changes

**New**: Enhanced PrimitiveContext with arena allocators
```zig
pub const PrimitiveContext = struct {
    allocator: Allocator,
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,
    agent_id: []const u8,           // NEW: Agent identity tracking
    timestamp: i64,                 // NEW: Temporal tracking
    session_id: []const u8,         // NEW: Session management
    arena: ?*std.heap.ArenaAllocator = null, // NEW: Memory management
};
```

### 3. Memory Management API Changes

**New**: Arena allocator integration
```zig
// NEW: Arena allocator for temporary operations
pub fn getArenaAllocator(self: *PrimitiveContext) Allocator

// NEW: JSON optimization with pooling
pub const JSONOptimizer = struct {
    pub fn getObject(self: *JSONOptimizer, allocator: Allocator) !*std.json.ObjectMap
    pub fn returnObject(self: *JSONOptimizer, object: *std.json.ObjectMap) void
    pub fn resetArena(self: *JSONOptimizer) void
}
```

## Breaking Changes

### 1. MCP Server Interface Changes

**Breaking Change**: MCP server now exposes primitives instead of specific tools

**Previous MCP Tools**:
```json
{
  "tools": [
    "read_code", "write_code", "analyze_dependencies", 
    "get_context", "record_decision", "search_semantic", 
    // ... 50+ tools
  ]
}
```

**New Primitive Interface**:
```json
{
  "primitives": [
    "store", "retrieve", "search", "link", "transform"
  ]
}
```

**Migration Path**: 
- Replace specific tool calls with primitive compositions
- Use `transform` primitive for operations like code analysis
- Use `search` primitive for semantic queries
- Use `store`/`retrieve` for data operations

### 2. Validation Requirements

**Breaking Change**: All primitive operations now require validation

**New Requirement**:
```zig
// All primitives must implement validate function
validate: *const fn (params: std.json.Value) anyerror!void
```

**Impact**: Invalid inputs are rejected before execution
**Migration**: Ensure all client code provides valid JSON parameters

### 3. Agent Identity Requirement

**Breaking Change**: All operations now require agent identification

**New Requirement**: Every primitive operation must include agent_id
**Migration**: Client code must provide agent identity for all operations

### 4. Session Management

**New Requirement**: Operations are now scoped to sessions
**Impact**: Session management required for proper operation tracking
**Migration**: Implement session lifecycle management in client code

## Non-Breaking Enhancements

### 1. Performance Monitoring

**New Feature**: Built-in performance metrics
```zig
// Automatic performance tracking in all operations
total_executions: u64
total_execution_time_ns: u64
operation_counts: HashMap
```

### 2. Enhanced Error Handling

**New Feature**: Structured error responses with context
**Benefit**: Better error debugging and handling
**Backward Compatible**: Previous error patterns still work

### 3. Memory Safety Improvements

**New Feature**: Automatic memory leak prevention
**Benefit**: More reliable long-running operations
**Backward Compatible**: No changes required to existing code

## Migration Guide

### From MCP Tools to Primitives

#### 1. Code Reading Operations
```javascript
// Old MCP tool approach
await mcpClient.callTool("read_code", {
  path: "src/main.zig",
  include_history: true,
  include_dependencies: true
});

// New primitive approach
const content = await mcpClient.callPrimitive("retrieve", {
  key: "src/main.zig",
  include_history: true
});

const deps = await mcpClient.callPrimitive("transform", {
  operation: "extract_dependencies",
  input: content
});
```

#### 2. Semantic Search Operations
```javascript
// Old approach
await mcpClient.callTool("search_semantic", {
  query: "function definitions",
  threshold: 0.8
});

// New primitive approach  
await mcpClient.callPrimitive("search", {
  query: "function definitions",
  mode: "semantic",
  options: { threshold: 0.8 }
});
```

#### 3. Data Storage Operations
```javascript
// Old approach
await mcpClient.callTool("record_decision", {
  decision: "Use primitive architecture",
  context: "After evaluating options..."
});

// New primitive approach
await mcpClient.callPrimitive("store", {
  key: "decision_primitive_architecture",
  content: "Use primitive architecture",
  metadata: {
    type: "decision",
    context: "After evaluating options...",
    agent_id: "planning_agent"
  }
});
```

## Compatibility Considerations

### 1. Existing MCP Clients

**Impact**: Existing MCP clients using old tool names will break
**Solution**: Implement adapter layer or update client code
**Timeline**: Deprecated tools will be removed in next major version

### 2. Database Schema Changes

**Impact**: New metadata fields and agent tracking
**Backward Compatibility**: Existing data remains accessible
**New Features**: Enhanced querying and provenance tracking

### 3. Performance Characteristics

**Change**: Performance targets are now more ambitious (<1ms P50)
**Impact**: May require client-side timeouts adjustment
**Benefit**: Much faster operations for most use cases

## Development Impact

### 1. Build System Changes

**New Build Targets**:
```bash
zig build test-primitives      # Primitive-specific tests
zig build test-performance     # Performance validation
zig build test-memory          # Memory safety tests
```

### 2. Testing Requirements

**New Requirements**:
- Memory leak detection in all tests
- Performance validation for all primitives
- Security testing for input validation

### 3. Documentation Updates

**New Documentation**:
- `/home/niko/agrama-v2/MEMORY_MANAGEMENT.md` - Memory safety patterns
- `/home/niko/agrama-v2/TEST_INFRASTRUCTURE.md` - Testing framework
- `/home/niko/agrama-v2/SECURITY_IMPROVEMENTS.md` - Security enhancements
- `/home/niko/agrama-v2/API_CHANGES.md` - This document

## Future API Evolution

### Planned Changes (Phase 2)
- Enhanced transform operations (20+ operations planned)
- Advanced search modes (temporal, graph traversal)
- Multi-agent collaboration primitives

### Planned Changes (Phase 3)
- Real-time event streaming API
- Conflict resolution primitives
- Advanced agent coordination features

## Migration Support

### Migration Tools (Planned)
- MCP tool -> primitive mapper
- Client code migration assistant
- Performance benchmarking for migration validation

### Support Resources
- Migration documentation and examples
- Client library updates for major frameworks
- Community support for migration questions

## Deprecation Timeline

### Immediate (Current)
- ✅ New primitive API available
- ✅ Old MCP tools still functional (compatibility layer)

### Phase 2 (Next Release)
- ⚠️ Old MCP tools deprecated with warnings
- ✅ Full primitive functionality complete

### Phase 3 (Future Release)  
- ❌ Old MCP tools removed
- ✅ Primitive-only interface

This API evolution provides much more power and flexibility while maintaining reasonable migration paths for existing users.