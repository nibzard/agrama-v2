# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Agrama Development Guide

## Project Overview

This repository contains **Agrama**, a production temporal knowledge graph database system for collaborative AI coding, and **Agrama CodeGraph**, a fully operational Model Context Protocol server demonstrating multi-agent capabilities in real-world scenarios.

### Production Architecture
- **Agrama Database**: Production Zig-based temporal knowledge graph with validated CRDT collaboration, operational HNSW vector indices, and working Frontier Reduction Engine
- **Agrama CodeGraph MCP Server**: Fully functional Model Context Protocol server enabling real multi-agent collaboration
- **Observatory Web Interface**: Deployed React-based real-time visualization of live AI-human collaboration
- **AI Agent Integration**: Production support for Claude Code, Cursor, and custom AI agents

### Key Technologies
- **Zig**: Core database implementation for performance and memory safety
- **CRDT (Yjs)**: Conflict-free collaborative editing
- **HNSW**: Hierarchical Navigable Small World graphs for O(log n) semantic search
- **FRE**: Frontier Reduction Engine for O(m log^(2/3) n) graph traversal
- **MCP**: Model Context Protocol for AI agent integration
- **React/TypeScript**: Web Observatory interface

## References

References like scientific papers, standards, dependancies documentation and other supporting materials for development is saved in "references/" folder.

## Production Usage Commands

### Project Setup
```bash
# Build production system
zig build

# Start MCP server
./zig-out/bin/agrama mcp

# Run comprehensive tests
zig build test

# Build optimized for production
zig build -Doptimize=ReleaseSafe

# Run performance benchmarks
./zig-out/bin/benchmark_suite

# Run individual benchmark categories
./zig-out/bin/fre_benchmark
./zig-out/bin/hnsw_benchmark
./zig-out/bin/database_benchmark
./zig-out/bin/mcp_benchmark
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

### Task Master Usage Policy

**PROACTIVE TASK-MASTER INVOCATION REQUIRED:**

The @task-master subagent should be invoked proactively in the following situations:

1. **After Major Development Work**: Always invoke @task-master after completing significant features, phases, or milestones to update TODO.md status and plan next steps.

2. **Before Starting New Development Phases**: Use @task-master to coordinate team transitions, update priorities, and manage dependencies between subagents.

3. **When Multiple Tasks Complete**: Don't let completed tasks accumulate - invoke @task-master to mark them complete and update project status in real-time.

4. **During Project State Changes**: Release completion, architecture changes, or major decisions require @task-master coordination.

5. **Regular Status Updates**: For complex multi-day work, invoke @task-master daily to maintain accurate project tracking.

**Why This Matters:**
- TODO.md serves as the single source of truth for project status
- Other team members and stakeholders rely on accurate task tracking
- Project momentum and coordination depend on up-to-date status
- @task-master provides strategic oversight that prevents scope drift and maintains focus

**Example Usage:**
```
# After completing MCP server implementation
@task-master: Update TODO.md with MCP server completion, coordinate Phase 3 UI development

# After successful release
@task-master: Mark MVP release complete, update project status, plan Phase 4 advanced algorithms
```

## Architecture Deep Dive

### Temporal Knowledge Graph (Core)
The heart of Agrama is a temporal graph database that captures code evolution over time:

- **Anchor+Delta Storage**: Periodic snapshots with delta compression for 5× storage efficiency
- **CRDT Integration**: Yjs-based conflict-free collaboration enabling real-time multi-agent editing
- **Multi-Scale Embeddings**: Matryoshka embeddings (64D-3072D) with progressive precision
- **HNSW Vector Index**: O(log n) semantic search vs O(n) linear scan for 100-1000× speedup

### Frontier Reduction Engine (Performance)
Advanced graph traversal algorithm with improved complexity:

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

### Performance Targets (ACHIEVED)
- **FRE Graph Traversal**: 2.778ms P50 (target <5ms) ✅
- **Hybrid Query Engine**: 4.91ms P50 (target <10ms) ✅
- **MCP Tool Calls**: 0.255ms P50 (target <100ms) ✅
- **Database Storage**: 0.11ms P50 (target <10ms) ✅
- **Memory Pools**: 50-70% allocation reduction ✅

### Memory Safety (Critical)
- Use arena allocators for scoped operations
- Always pair allocations with `defer`
- GeneralPurposeAllocator in debug mode to catch leaks
- Memory pool system (`src/memory_pools.zig`) for 50-70% allocation reduction
- SIMD-aligned pools for vector operations (32-byte aligned)

## Key Implementation Details

### Core Architecture Files
- **`src/main.zig`**: CLI entry point with `serve`, `mcp`, and `primitive` commands
- **`src/root.zig`**: Module exports and public API definitions
- **`src/database.zig`**: Core temporal database with memory pool integration
- **`src/primitives.zig`**: 5-primitive system (store, retrieve, search, link, transform)
- **`src/triple_hybrid_search.zig`**: BM25 + HNSW + FRE search engine with caching
- **`src/mcp_compliant_server.zig`**: Model Context Protocol server implementation
- **`src/memory_pools.zig`**: TigerBeetle-inspired memory pool system

### Agrama Database Core Structure
```zig
// Core database with memory pool optimization
pub const Database = struct {
    allocator: Allocator,
    memory_pools: ?*MemoryPoolSystem,    // 50-70% allocation reduction
    current_files: HashMap(...),         // Current file contents
    file_histories: HashMap(...),        // Temporal change history
    fre: ?TrueFrontierReductionEngine,   // O(m log^(2/3) n) graph traversal
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
- Unit tests for all core algorithms and data structures (`zig build test`)
- Integration tests for MCP server and database operations
- Fuzz tests for robustness and security (`tests/fuzz_test_framework.zig`)
- Performance benchmarks with regression detection (`benchmarks/` directory)
- Memory safety validation (`tests/memory_safety_validator.zig`)
- 90%+ test coverage for core functionality

### Benchmark Architecture
The `benchmarks/` directory contains comprehensive performance testing:
- **`benchmark_suite.zig`**: Main benchmark runner with all categories
- **`fre_benchmarks.zig`**: Graph traversal performance (achieved 2.778ms P50)
- **`triple_hybrid_benchmarks.zig`**: Search performance (achieved 4.91ms P50)
- **`mcp_benchmarks.zig`**: MCP server performance (achieved 0.255ms P50)
- **`database_benchmarks.zig`**: Storage performance (achieved 0.11ms P50)
- **`memory_pool_benchmarks.zig`**: Memory allocation efficiency testing

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

This project represents a temporal knowledge graph database for AI-assisted collaborative development. The combination of temporal knowledge graphs, advanced algorithms (FRE, HNSW), and memory pool optimizations provides production-ready performance for code understanding and collaboration.

Always prioritize:
1. **Safety**: Memory safety and correctness over premature optimization
2. **Performance**: Maintain the achieved sub-10ms query targets through careful implementation
3. **Collaboration**: Enable seamless AI-human teamwork through comprehensive observability
4. **Quality**: Maintain high code standards through comprehensive testing and validation

Development principles:
- Never do wrappers and mocks, strive for excellence
- Never hype achievements, focus on measured results
- All performance claims must be backed by benchmark data
- Memory safety is critical - use arena allocators and memory pools appropriately
- Never use overhyped words like "world's first," "revolutionary," "game-changing", we are speaking to other developers, keep it real!