# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Agrama Development Guide

## Project Overview

This repository contains **Agrama**, a temporal knowledge graph database system for collaborative AI coding, and **Agrama CodeGraph**, a Model Context Protocol server that demonstrates the system in real-world scenarios.

### Core Architecture
- **Agrama Database**: Zig-based temporal knowledge graph with CRDT collaboration, HNSW vector indices, and Frontier Reduction Engine
- **Agrama CodeGraph MCP Server**: Model Context Protocol server enabling AI agent collaboration  
- **Observatory Web Interface**: React-based real-time visualization of AI-human collaboration
- **AI Agent Integration**: Supports Claude Code, Cursor, and custom AI agents

### Key Technologies
- **Zig**: Core database implementation for performance and memory safety
- **CRDT (Yjs)**: Conflict-free collaborative editing
- **HNSW**: Hierarchical Navigable Small World graphs for O(log n) semantic search
- **FRE**: Frontier Reduction Engine for O(m log^(2/3) n) graph traversal
- **MCP**: Model Context Protocol for AI agent integration
- **React/TypeScript**: Web Observatory interface

## Development Commands

### Project Setup
```bash
# Initialize Zig project (when ready)
zig init-lib agrama

# Start CodeGraph MCP server (future)
agrama codegraph serve

# Run tests
zig build test

# Build optimized
zig build -Doptimize=ReleaseSafe
```

### Core Development Loop
```bash
# MANDATORY after every change:
zig fmt .                    # Format code
zig build                    # Verify compilation
zig build test               # Run tests

# Full validation before commits:
zig fmt . && zig build && zig build test && echo "✓ Ready to commit"
```

## Task Management

**ALL development work must be tracked in TODO.md using the established style guide.**

- Tasks use priority levels [P0] Critical → [P3] Low
- Include context, acceptance criteria, dependencies, estimates
- Update status: [ ] not started, [~] in progress, [x] completed, [!] blocked
- Use categories: Core, MCP, Web, API, Docs, Test, Deploy
- Reference SPECS.md and MVP.md for requirements

## Architecture Deep Dive

### Temporal Knowledge Graph (Core)
The heart of Agrama is a temporal graph database that captures code evolution over time:

- **Anchor+Delta Storage**: Periodic snapshots with delta compression for 5× storage efficiency
- **CRDT Integration**: Yjs-based conflict-free collaboration enabling real-time multi-agent editing
- **Multi-Scale Embeddings**: Matryoshka embeddings (64D-3072D) with progressive precision
- **HNSW Vector Index**: O(log n) semantic search vs O(n) linear scan for 100-1000× speedup

### Frontier Reduction Engine (Performance)
Revolutionary graph traversal algorithm breaking the "sorting barrier":

- **Complexity**: O(m log^(2/3) n) vs traditional O(m + n log n) Dijkstra
- **Applications**: Dependency analysis, impact assessment, semantic discovery
- **Real Impact**: 5-50× speedup on large codebases (100K+ entities)

### MCP Server (Integration)
Model Context Protocol server bridging AI agents to the knowledge graph:

- **Core Tools**: read_code, write_code, analyze_dependencies, get_context, record_decision
- **Real-time Events**: WebSocket broadcasting of all agent actions
- **Multi-Agent Support**: 3+ concurrent agents with sub-100ms tool response times

### Observatory Interface (Visualization)
React-based web interface providing unprecedented visibility:

- **Knowledge Graph Viz**: D3.js real-time force-directed graph of code entities
- **Agent Activity Feed**: Live stream of AI agent actions and decisions  
- **Human Command Interface**: Natural language commands to guide AI agents
- **Temporal Analytics**: Evolution tracking and pattern recognition

## Development Team (AI Subagents)

This project uses specialized AI subagents located in `.claude/agents/`:

- **@task-master**: Project coordination, TODO.md management, sprint planning
- **@db-engineer**: Zig development, temporal database, core algorithms  
- **@mcp-specialist**: MCP server, AI agent integration, real-time communication
- **@frontend-engineer**: React Observatory interface, D3.js visualization
- **@perf-engineer**: Algorithm optimization, FRE, HNSW implementation
- **@qa-engineer**: Testing framework, quality assurance, CI/CD

Use `@subagent-name` for explicit invocation or let them activate automatically based on task context.

## Critical Development Rules

### MANDATORY Workflow
```bash
# After EVERY file modification:
zig build                    # Verify compilation
zig build test               # Run tests  
zig fmt .                    # Format code

# Before ANY commit:
zig build && zig build test && echo "✓ Ready to commit"
```

### Performance Targets
- **Semantic Search**: O(log n) via HNSW, 100-1000× faster than linear scan
- **Graph Traversal**: O(m log^(2/3) n) via FRE vs O(m + n log n) traditional  
- **Query Response**: Sub-10ms for hybrid semantic+graph queries on 1M+ nodes
- **MCP Tool Calls**: Sub-100ms response times
- **Storage Efficiency**: 5× reduction through anchor+delta compression

### Memory Safety (Critical)
- Use arena allocators for scoped operations
- Always pair allocations with `defer`
- GeneralPurposeAllocator in debug mode to catch leaks
- Fixed memory pools for predictable performance (TigerBeetle approach)

## Key Implementation Details

### Agrama Database Core Structure
```zig
// Core database interface from SPECS.md
pub const TemporalGraphDB = struct {
    // Hierarchical memory allocators
    page_pool: FixedBufferAllocator,        // 4KB pages for graph data  
    embedding_pool: FixedBufferAllocator,   // Variable-size embedding storage
    crdt_arena: ArenaAllocator,             // Transaction-scoped CRDT operations

    // Primary operations
    pub fn createNode(self: *TemporalGraphDB, node: TemporalNode) !NodeID;
    pub fn createEdge(self: *TemporalGraphDB, edge: TemporalEdge) !EdgeID;
    pub fn timeTravel(self: *TemporalGraphDB, timestamp: i64) !GraphSnapshot;
    pub fn hybridSearch(self: *TemporalGraphDB, query: HybridQuery) !QueryResult;
};
```

### MCP Tools Implementation Pattern
```zig
// MCP tools follow this pattern from MVP.md
const readCodeTool = MCPTool{
    .name = "read_code", 
    .description = "Read and analyze code files with full context",
    .parameters = &[_]MCPParameter{ /* ... */ },
    .handler = struct {
        fn execute(params: MCPParameters, context: *MCPContext) !MCPResult {
            // 1. Read file content
            // 2. Add historical context if requested  
            // 3. Add dependency context
            // 4. Add semantic context (similar code via HNSW)
            // 5. Return comprehensive result
        }
    },
};
```

### Error Handling Pattern
- Define specific error sets for each domain (ValidationError, NetworkError, etc.)
- Combine error sets with `||` operator 
- Always include context in error messages
- Use `catch |err| switch (err)` for detailed error handling

### Testing Requirements
- Unit tests for all core algorithms and data structures
- Integration tests for MCP server and database operations  
- Fuzz tests for robustness and security
- Performance benchmarks with regression detection
- 90%+ test coverage for core functionality

## Documentation References

- **SPECS.md**: Complete technical specification for Agrama temporal knowledge graph database
- **MVP.md**: Agrama CodeGraph MCP server and Observatory implementation plan
- **TODO.md**: Development task tracker with priority-based workflow
- **SUBAGENTS.md**: AI developer team documentation and coordination guide

## Success Criteria

### Technical Targets (from SPECS.md)
- **Storage Efficiency**: 5× reduction through anchor+delta compression
- **Semantic Search**: O(log n) via HNSW vs O(n) linear scan  
- **Graph Traversal**: O(m log^(2/3) n) via FRE vs O(m + n log n) Dijkstra
- **Query Performance**: Sub-10ms for hybrid semantic+graph queries on 1M+ nodes
- **Concurrent Agents**: Support 100+ simultaneous AI agents
- **Memory Usage**: Fixed allocation <10GB for 1M nodes

### MVP Deliverables (from MVP.md)  
- **MCP Server**: Tool registry with core AI agent tools
- **Web Observatory**: React interface with real-time knowledge graph visualization  
- **Agent Integration**: Claude Code, Cursor, custom agent support
- **Human Commands**: Natural language interface to guide AI agents
- **Complete Traceability**: All agent decisions recorded and explainable

## Final Notes

This project represents a fundamental breakthrough in AI-assisted collaborative development. The combination of temporal knowledge graphs, advanced algorithms (FRE, HNSW), and real-time multi-agent coordination creates unprecedented capabilities for code understanding and collaboration.

Always prioritize:
1. **Safety**: Memory safety and correctness over premature optimization  
2. **Performance**: Meet the ambitious algorithmic targets through careful implementation
3. **Collaboration**: Enable seamless AI-human teamwork through comprehensive observability
4. **Quality**: Maintain high code standards through comprehensive testing and validation