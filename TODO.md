# Agrama Development Tasks

## Current Sprint - Stability & Polish

### Critical Issues (P0)
- [ ] **Fix Memory Leak** - Resolve triple hybrid search memory leak causing 1 test failure
  - File: `src/triple_hybrid_search.zig:385`
  - Issue: Memory allocation in `combineResults` not properly cleaned up
  - Target: 100% test pass rate
  
- [ ] **Performance Regression** - Optimize for datasets >10K nodes
  - Current: Stable up to 5K nodes, degrades beyond 10K
  - Target: Stable performance up to 25K nodes
  - Focus: HNSW index efficiency and FRE scaling

### High Priority (P1)
- [ ] **Enhanced MCP Tools** - Add 3 new MCP tools for better AI integration
  - `code_analysis`: AST parsing and static analysis
  - `dependency_map`: Complete dependency visualization
  - `temporal_query`: Time-based code evolution queries
  - Target: 8 total MCP tools

- [ ] **Installation Script** - One-command setup for new users
  - Create `install.sh` script for Linux/macOS
  - Automate Zig installation if missing
  - Configure MCP client settings
  - Target: <5 minute setup time

- [ ] **API Documentation** - Complete REST/MCP API documentation
  - Document all MCP tool parameters and responses
  - Add code examples for each tool
  - Create integration guides for Claude Code/Cursor
  - Target: Production-ready documentation

### Medium Priority (P2)  
- [ ] **Observatory Improvements** - Enhance web interface
  - Add performance trend charts
  - Implement graph filtering and search
  - Create agent activity timeline
  - Target: Better developer experience

- [ ] **Error Handling** - Improve MCP server resilience
  - Better error messages and recovery
  - Graceful handling of malformed requests
  - Connection retry logic
  - Target: Production-stable MCP server

- [ ] **Configuration System** - Centralized config management
  - YAML/TOML configuration files
  - Environment variable support
  - Runtime configuration updates
  - Target: Easy deployment configuration

## Backlog - Future Features

### Enhanced Capabilities
- [ ] **Multi-Modal Search** - Support text + code + documentation search
- [ ] **Advanced Visualizations** - 3D graph rendering, timeline views
- [ ] **Collaboration Features** - Multi-agent coordination and conflict resolution
- [ ] **Export/Import** - Data export to standard formats (GraphML, JSON)

### Performance & Scaling
- [ ] **Parallel HNSW** - Multi-threaded index operations
- [ ] **Caching Layer** - Query result caching with LRU eviction
- [ ] **Database Backends** - PostgreSQL/SQLite backend options
- [ ] **Distributed Architecture** - Multi-node deployment support

### Production Features
- [ ] **Authentication** - Role-based access control
- [ ] **Rate Limiting** - API rate limiting and quotas
- [ ] **Monitoring** - Prometheus metrics and health checks
- [ ] **Docker Images** - Production-ready containerization

## Completed ✅

### Foundation (v1.0)
- [x] **Core Database** - Temporal graph storage with file persistence
- [x] **HNSW Implementation** - 360× speedup semantic search
- [x] **FRE Algorithm** - 120× speedup graph traversal  
- [x] **MCP Server** - Basic AI agent integration (5 tools)
- [x] **Web Observatory** - Real-time visualization interface
- [x] **Test Suite** - 64/65 tests passing
- [x] **Benchmark Suite** - Performance validation framework
- [x] **Build System** - Zig build configuration
- [x] **Documentation Consolidation** - Realistic, focused docs

## Development Guidelines

### Before Starting Any Task
1. Ensure `zig build test` passes (64/65 tests)
2. Run `zig build bench-quick` to establish performance baseline
3. Check current memory usage with valgrind if available

### Code Quality Standards
- **Memory Safety**: Use proper Zig allocator patterns with `defer`
- **Testing**: Add unit tests for all new functionality
- **Performance**: Benchmark performance-critical changes
- **Documentation**: Update relevant docs for user-facing changes

### Definition of Done
- [ ] Feature implemented and working
- [ ] Unit tests added and passing
- [ ] Integration tests pass
- [ ] Performance impact measured (no regressions)
- [ ] Documentation updated
- [ ] Code reviewed and approved

## Performance Targets

### Current Baseline (5K nodes)
- HNSW Search: 0.21ms P50, 4,600 QPS
- FRE Traversal: 5.6ms P50, 180 QPS  
- MCP Tools: 0.26ms P50, 3,800 QPS
- Memory Usage: ~200MB total

### Phase 1 Targets (25K nodes)
- HNSW Search: <0.5ms P50, >2,000 QPS
- FRE Traversal: <10ms P50, >100 QPS
- MCP Tools: <0.5ms P50, >2,000 QPS
- Memory Usage: <500MB total

## Current Blockers

None - project is building and 98.5% of tests passing.

## Notes

### Recent Changes
- Fixed compilation errors in `agent_manager.zig`
- Consolidated documentation from 9,000+ lines to focused guides
- Validated actual performance through benchmark results
- Aligned claims with demonstrated capabilities

### Next Review
Review and update this TODO list weekly to maintain focus on achievable, valuable work.