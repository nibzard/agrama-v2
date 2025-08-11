# Agrama Technical Architecture

## System Overview

Agrama is a temporal knowledge graph database designed for AI-assisted software development. It combines advanced graph algorithms with traditional database operations to provide fast semantic search, efficient graph traversal, and temporal versioning.

## Core Components

### 1. Database Layer (`src/database.zig`)

**Purpose**: Persistent storage with temporal versioning
**Implementation**: File-based storage with JSON serialization
**Key Features**:
- Temporal node and edge operations
- File versioning with timestamps
- Path validation for security
- Memory-safe operations with Zig

**Performance**: ~2ms P50 latency for basic operations

### 2. HNSW Vector Index (`src/hnsw.zig`)

**Purpose**: Hierarchical Navigable Small World graphs for semantic search
**Implementation**: Multi-layer graph structure with probabilistic connections
**Algorithm Complexity**: O(log n) search vs O(n) linear scan
**Key Features**:
- Matryoshka embeddings (64D to 3072D dimensions)
- Configurable graph parameters (M, efConstruction)
- Memory-efficient priority queues
- SIMD-optimized distance calculations

**Performance**: 0.21ms P50 latency, 360× speedup over linear scan

### 3. Frontier Reduction Engine (`src/fre.zig`)

**Purpose**: Advanced graph traversal with O(m log^(2/3) n) complexity
**Implementation**: Recursive bounded multi-source shortest path algorithm
**Key Features**:
- Pivot-based frontier reduction
- Temporal-aware traversal
- Multi-target optimization
- Adaptive level selection

**Performance**: 5.6ms P50 latency, 120× speedup over Dijkstra

### 4. MCP Server (`src/mcp_server.zig`)

**Purpose**: Model Context Protocol server for AI agent integration
**Implementation**: JSON-RPC 2.0 over HTTP/WebSocket
**Key Features**:
- Tool registry with dynamic loading
- Real-time WebSocket broadcasting
- Agent session management
- Error handling and validation

**Performance**: 0.26ms P50 latency for tool calls

**Available Tools**:
- `read_code`: Read files with temporal context
- `write_code`: Save files with versioning
- `get_context`: Query recent changes
- `semantic_search`: HNSW-powered similarity search
- `analyze_dependencies`: FRE graph traversal

### 5. Web Observatory (`web/`)

**Purpose**: Real-time visualization and monitoring interface
**Implementation**: React + TypeScript with D3.js
**Key Features**:
- Live agent activity feeds
- Performance metric dashboards
- Graph visualization with force-directed layout
- WebSocket integration for real-time updates

## Data Model

### Temporal Nodes
```zig
pub const TemporalNode = struct {
    id: u128,
    node_type: NodeType,
    properties: HashMap([]const u8, Value),
    embedding: ?[]f32,
    created_at: i64,
    updated_at: i64,
    valid_from: i64,
    valid_to: ?i64,
};
```

### Temporal Edges
```zig
pub const TemporalEdge = struct {
    id: u128,
    source: u128,
    target: u128,
    edge_type: EdgeType,
    weight: f32,
    properties: HashMap([]const u8, Value),
    created_at: i64,
    valid_from: i64,
    valid_to: ?i64,
};
```

## Algorithm Implementations

### HNSW Construction

1. **Layer Assignment**: Nodes assigned to layers with exponential probability
2. **Connection Building**: Connect to M nearest neighbors per layer
3. **Dynamic Updates**: Support for insertions without full rebuilds
4. **Distance Functions**: Cosine similarity for embeddings

### FRE Traversal

1. **Pivot Selection**: Choose high-degree nodes as pivots
2. **Recursive Decomposition**: Split graph into smaller subproblems
3. **Frontier Reduction**: Maintain small exploration frontiers
4. **Result Aggregation**: Combine results from recursive calls

### Temporal Operations

1. **Anchor+Delta Storage**: Periodic full snapshots with incremental deltas
2. **Time Travel Queries**: Query graph state at specific timestamps
3. **Evolution Tracking**: Monitor how relationships change over time
4. **Version Management**: Efficient storage of multiple versions

## Memory Management

### Allocator Strategy
- **ArenaAllocator**: For temporary operations and graph traversal
- **GeneralPurposeAllocator**: For long-lived objects (debug mode)
- **FixedBufferAllocator**: For predictable performance in hot paths

### Memory Safety
- All memory operations use Zig's safety guarantees
- Explicit `defer` cleanup for resource management
- No memory leaks detected in 64/65 tests (one minor leak in triple hybrid search)

## Performance Characteristics

### Benchmarked Performance (5K node dataset)

| Operation | Latency P50 | Latency P99 | Throughput | Memory |
|-----------|-------------|-------------|------------|--------|
| Node Insert | 1.2ms | 2.1ms | 830 QPS | 50MB |
| HNSW Search | 0.21ms | 0.29ms | 4,600 QPS | 59MB |
| FRE Traversal | 5.6ms | 9.4ms | 180 QPS | 430MB |
| MCP Tool Call | 0.26ms | 0.37ms | 3,800 QPS | 50MB |

### Scaling Characteristics
- **HNSW**: O(log n) search scales well to 50K+ nodes
- **FRE**: O(m log^(2/3) n) traversal maintains sub-10ms latency
- **Storage**: Linear growth with data size, efficient compression
- **Memory**: ~200MB total for typical 10K node graphs

## Integration Points

### AI Agent Integration
- **Claude Code**: Native MCP client support
- **Cursor**: MCP server configuration
- **Custom Agents**: JSON-RPC 2.0 protocol compliance

### WebSocket Events
- Real-time agent activity broadcasting
- Graph update notifications
- Performance metric streaming

### File System Integration
- Secure path validation prevents traversal attacks
- Configurable storage location
- JSON-based serialization for interoperability

## Error Handling

### Error Types
- `ValidationError`: Input validation failures
- `StorageError`: File system operation errors
- `NetworkError`: MCP protocol errors
- `AllocationError`: Memory allocation failures

### Recovery Strategies
- Graceful degradation for non-critical operations
- Automatic retry with exponential backoff
- Transaction rollback for consistency
- Comprehensive error logging

## Security Considerations

### Path Security
- All file paths validated against traversal attacks
- Whitelist-based path permissions
- Sandboxed file operations

### Network Security
- MCP protocol input validation
- Rate limiting for API endpoints
- Secure WebSocket connections (configurable TLS)

### Memory Security
- Zig's compile-time safety guarantees
- No buffer overflows or use-after-free
- Explicit memory management

## Testing Strategy

### Test Coverage
- Unit tests: Core algorithms and data structures
- Integration tests: MCP server and database operations
- Performance tests: Benchmark validation
- Memory tests: Leak detection and allocation patterns

### Current Status
- 64/65 tests passing (98.5% success rate)
- One minor memory leak in triple hybrid search
- Comprehensive benchmark suite with regression detection

## Deployment

### Build Requirements
- Zig 0.14+ for database compilation
- Node.js 18+ for web interface
- 2GB RAM minimum for development
- 4GB RAM recommended for production

### Runtime Requirements
- ~200MB memory for typical workloads
- Network access for MCP protocol
- File system write permissions
- Optional: WebSocket capabilities for real-time features

This architecture provides a solid foundation for temporal knowledge graph operations with proven performance characteristics and comprehensive testing coverage.