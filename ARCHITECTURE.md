# Agrama Architecture

## Overview

Agrama is a temporal knowledge graph database designed for AI-human collaboration. At its core, it provides a powerful graph database with temporal tracking, semantic search, and advanced traversal algorithms. Multiple interfaces allow different types of clients to interact with the system.

```
┌─────────────────────────────────────────────────────────────┐
│                        Agrama Server                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │                  Core Components                    │     │
│  ├────────────────────────────────────────────────────┤     │
│  │                                                     │     │
│  │  • Temporal Database (anchor+delta compression)    │     │
│  │  • Semantic Search (HNSW vector indices)           │     │
│  │  • Graph Engine (FRE traversal algorithm)          │     │
│  │  • Primitive Engine (5 core operations)            │     │
│  │  • Orchestration Context (participant management)  │     │
│  │                                                     │     │
│  └────────────────────────────────────────────────────┘     │
│                            ▲                                 │
│                            │                                 │
│  ┌─────────────────────────┴──────────────────────────┐     │
│  │              Interface Adapters Layer              │     │
│  ├────────────────────────────────────────────────────┤     │
│  │                                                     │     │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────┐ │     │
│  │  │     MCP     │  │  WebSocket   │  │   HTTP   │ │     │
│  │  │  Interface  │  │  Interface   │  │  (future)│ │     │
│  │  └─────────────┘  └──────────────┘  └──────────┘ │     │
│  │                                                     │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌─────────┐         ┌─────────────┐      ┌─────────┐
   │   AI    │         │ Observatory │      │  REST   │
   │ Agents  │         │   Web UI    │      │ Clients │
   └─────────┘         └─────────────┘      └─────────┘
    (via MCP)          (via WebSocket)       (future)
```

## Core System

The core of Agrama is independent of any specific protocol or interface. It provides:

### 1. Temporal Database (`src/database.zig`)
- **Anchor+Delta Storage**: Periodic snapshots with delta compression for 5× storage efficiency
- **File History Tracking**: Complete version history for all stored entities
- **CRDT Support**: Conflict-free replicated data types for collaborative editing

### 2. Semantic Database (`src/semantic_database.zig`)
- **HNSW Indices**: Hierarchical Navigable Small World graphs for O(log n) semantic search
- **Matryoshka Embeddings**: Multi-scale embeddings (64D-3072D) with progressive precision
- **Vector Operations**: Optimized similarity search and clustering

### 3. Graph Engine (`src/triple_hybrid_search.zig`)
- **BM25 Lexical Search**: Traditional text search with TF-IDF scoring
- **Semantic Vector Search**: Neural embedding-based similarity
- **FRE Graph Traversal**: O(m log^(2/3) n) complexity for dense graphs
- **Hybrid Scoring**: Combines all three approaches for optimal results

### 4. Primitive Engine (`src/primitive_engine.zig`)
The 5 core operations that all interfaces use:
- **STORE**: Save data with rich metadata and provenance
- **RETRIEVE**: Access data with full history and context
- **SEARCH**: Unified search across all modalities
- **LINK**: Create knowledge graph relationships
- **TRANSFORM**: Apply data transformations

### 5. Orchestration Context (`src/orchestration_context.zig`)
- **Participant Management**: Track humans and AI agents as equal collaborators
- **Activity Monitoring**: Record contributions and context
- **Collaborative Events**: Pattern discovery, consensus, conflict resolution

## Interface Adapters

Interfaces are **adapters** that translate between external protocols and Agrama's core primitives. They are optional and can be enabled/disabled independently.

### MCP Interface (`src/interfaces/mcp/`)
**Purpose**: Enable AI agents to interact with Agrama

The Model Context Protocol (MCP) is a standardized protocol for AI agent communication. Our MCP interface:
- Translates MCP requests to Agrama primitives
- Manages agent sessions
- Provides tool definitions for AI consumption
- Maintains protocol compliance with MCP specification

**Important**: MCP is just ONE way to interact with Agrama, not the core of the system.

### WebSocket Interface (`src/interfaces/websocket/`)
**Purpose**: Real-time event streaming for web clients

The WebSocket interface enables:
- Observatory web UI connections
- Live collaboration monitoring
- Event broadcasting
- Push-based updates

### Future Interfaces

#### HTTP REST Interface (planned)
- Traditional REST API
- CRUD operations
- OpenAPI specification
- Browser-friendly

#### gRPC Interface (planned)
- High-performance RPC
- Streaming support
- Protocol buffers
- Language-agnostic

## Key Design Principles

### 1. Core-Interface Separation
The core system is completely independent of interface protocols. New interfaces can be added without modifying core functionality.

### 2. Primitive-Based Architecture
All operations decompose to the 5 primitives. This ensures consistency across interfaces and enables powerful composition.

### 3. Temporal-First Design
Every piece of data has history. The system is designed for time-travel queries and understanding evolution.

### 4. Collaborative by Default
Multiple participants (human and AI) can work simultaneously. The orchestration layer manages coordination without central control.

### 5. Performance Critical
- <1ms P50 latency for primitive operations
- Memory pools reduce allocations by 50-70%
- SIMD-optimized vector operations
- Lock-free data structures where possible

## File Organization

```
src/
├── core/                      # Core Agrama components
│   ├── database.zig          # Temporal database
│   ├── semantic_database.zig # Vector search
│   ├── graph_engine.zig      # Graph algorithms
│   ├── primitives.zig        # Core operations
│   └── orchestration.zig     # Participant coordination
│
├── interfaces/               # Protocol adapters
│   ├── mcp/                 # Model Context Protocol
│   │   └── mcp_interface.zig
│   ├── websocket/           # Real-time streaming
│   │   └── websocket_interface.zig
│   └── http/                # REST API (future)
│       └── http_interface.zig
│
├── algorithms/              # Advanced algorithms
│   ├── fre_true.zig        # Frontier Reduction Engine
│   ├── hnsw.zig           # HNSW implementation
│   └── crdt.zig           # CRDT algorithms
│
└── agrama_server.zig      # Main server orchestration
```

## Usage Examples

### Starting with Different Interfaces

```bash
# Start with all interfaces
agrama serve --all

# MCP interface only (for AI agents)
agrama serve --mcp

# WebSocket only (for Observatory)
agrama serve --websocket --port 8080

# Multiple specific interfaces
agrama serve --mcp --websocket
```

### Direct Core Access (Embedded)

```zig
const agrama = @import("agrama");

// Use Agrama as a library without any interfaces
var server = try agrama.AgramaServer.init(allocator, .{
    .enable_mcp = false,
    .enable_websocket = false,
});

// Direct primitive execution
const result = try server.executePrimitive("store", params, "embedded_app");
```

## Performance Characteristics

### Storage
- **Compression**: 5× reduction via anchor+delta
- **Write Speed**: 0.11ms P50 for database operations
- **Memory Usage**: <10GB for 1M entities

### Search
- **Vector Search**: O(log n) with HNSW
- **Hybrid Query**: 4.91ms P50 for complex queries
- **Graph Traversal**: 2.778ms P50 with FRE

### Interfaces
- **MCP Tools**: 0.255ms P50 response time
- **WebSocket**: <1ms broadcast latency
- **Concurrent Connections**: 100+ participants

## Security Considerations

### Interface Layer
- Authentication per interface type
- Rate limiting and quotas
- TLS/SSL for network interfaces

### Core Layer
- Input validation on all primitives
- Memory safety via Zig's compile-time checks
- Audit logging for all operations

### Data Layer
- Encryption at rest (planned)
- Versioned access control
- Immutable history logs

## Future Enhancements

### Near Term
- HTTP REST interface
- GraphQL interface
- Prometheus metrics endpoint

### Medium Term
- Distributed clustering
- Cross-region replication
- Advanced CRDT types

### Long Term
- Native language SDKs
- Embedded database mode
- Query optimization engine