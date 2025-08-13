# Technology Stack & Build System

## Primary Technology Stack

- **Language**: Zig 0.14+ (systems programming language with compile-time safety)
- **Runtime**: Native binary with no dependencies
- **Architecture**: Multi-interface server with core-adapter separation
- **Memory Management**: Custom memory pools with TigerBeetle-inspired optimization
- **Protocols**: MCP (Model Context Protocol), WebSocket, JSON-RPC 2.0

## Core Dependencies

- **Zig Standard Library**: Core data structures, allocators, JSON parsing
- **No External Dependencies**: Self-contained implementation for maximum reliability

## Build System

Uses Zig's native build system (`build.zig`) with comprehensive build targets:

### Essential Commands

```bash
# Build the project
zig build

# Run the main server
zig build run

# Run all tests
zig build test

# Start MCP server (primary interface)
./zig-out/bin/agrama mcp

# Start with custom dimensions
./zig-out/bin/agrama mcp --dimensions 1024

# Test database functionality
./zig-out/bin/agrama test-db
```

### Development Commands

```bash
# Format code (always run before commits)
zig fmt .

# Run comprehensive test suite
zig build test-all

# Run integration tests
zig build test-integration

# Run primitive-specific tests
zig build test-primitives

# Run performance benchmarks
zig build bench

# Quick benchmark for development
zig build bench-quick

# Memory pool demonstration
zig build demo-memory-pools
```

### Specialized Build Targets

```bash
# Individual component benchmarks
zig build bench-hnsw          # HNSW vector search
zig build bench-fre           # FRE graph traversal
zig build bench-database      # Database operations
zig build bench-mcp           # MCP server performance

# Test categories
zig build test-primitives-unit        # Unit tests only
zig build test-primitives-security    # Security validation
zig build test-primitives-performance # Performance tests
zig build test-concurrent             # Concurrency tests
zig build test-fuzz                   # Fuzz testing

# Validation and debugging
zig build validate            # Performance validation with optimized build
zig build security-report     # Security summary report
```

## Architecture Components

### Core System (src/)
- **Database**: `database.zig` - Temporal knowledge graph with anchor+delta compression
- **Semantic Search**: `semantic_database.zig` - HNSW vector indices with Matryoshka embeddings
- **Graph Engine**: `triple_hybrid_search.zig` - BM25 + HNSW + FRE hybrid search
- **Primitives**: `primitives.zig` - 5 core operations (1,614 lines)
- **Primitive Engine**: `primitive_engine.zig` - Execution orchestration
- **Memory Pools**: `memory_pools.zig` - TigerBeetle-inspired optimization

### Algorithms (src/)
- **HNSW**: `hnsw.zig` - Hierarchical Navigable Small World graphs
- **FRE**: `fre_true.zig` - Frontier Reduction Engine for graph traversal
- **CRDT**: `crdt.zig` - Conflict-free replicated data types
- **BM25**: `bm25.zig` - Text search ranking

### Interfaces (src/)
- **MCP Server**: `mcp_primitive_server.zig` - Model Context Protocol interface
- **WebSocket**: `websocket.zig` - Real-time event streaming
- **Main Server**: `agrama_server.zig` - Multi-interface orchestration

## Performance Characteristics

### Algorithmic Complexity
- **HNSW Search**: O(log n) semantic similarity
- **FRE Traversal**: O(m log^(2/3) n) graph operations
- **Database Storage**: O(1) with anchor+delta compression
- **Memory Pools**: 50-70% allocation overhead reduction

### Memory Management
- **Arena Allocators**: Scoped memory management with automatic cleanup
- **Memory Pools**: Reusable allocations for frequent operations
- **SIMD Alignment**: 32-byte aligned pools for vector operations
- **GeneralPurposeAllocator**: Debug mode with leak detection

## Development Workflow

### Code Quality Standards
```bash
# Always format before commits
zig fmt .

# Verify compilation
zig build

# Run tests
zig build test

# Performance validation for critical changes
zig build bench-quick
```

### Testing Strategy
- **Unit Tests**: Individual component validation
- **Integration Tests**: Cross-component functionality
- **Performance Tests**: Latency and throughput validation
- **Security Tests**: Memory safety and input validation
- **Fuzz Tests**: Random input robustness

### Memory Safety
- **Compile-time Safety**: Zig's built-in memory safety features
- **Runtime Validation**: GeneralPurposeAllocator with safety checks
- **Leak Detection**: Comprehensive memory leak tracking
- **Arena Pattern**: Scoped allocations with automatic cleanup

## Configuration

### Server Configuration
- **MCP Interface**: Enabled by default for AI agents
- **WebSocket Interface**: Optional for real-time clients (port 8080)
- **HNSW Dimensions**: Configurable (default: 768)
- **Memory Pools**: Enabled by default for performance

### Performance Tuning
- **Vector Dimensions**: 64D-3072D with Matryoshka embeddings
- **HNSW Parameters**: max_connections=16, ef_construction=200
- **Memory Pool Sizes**: Configurable per allocation pattern
- **Concurrent Participants**: Up to 100+ simultaneous agents

## Deployment

### Production Build
```bash
# Optimized release build
zig build -Doptimize=ReleaseFast

# Start production MCP server
./zig-out/bin/agrama mcp
```

### Development Build
```bash
# Debug build with safety checks
zig build -Doptimize=Debug

# Enable memory leak detection
zig build test -Doptimize=Debug
```

## Web Interface (Optional)

Located in `web/` directory with React + TypeScript:

```bash
cd web
npm install
npm run dev    # Development server
npm run build  # Production build
```

The Observatory interface connects to WebSocket on port 8080 for real-time monitoring.