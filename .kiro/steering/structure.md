# Project Structure & Organization

## Repository Layout

```
agrama-v2/
├── src/                    # Core Zig implementation
├── tests/                  # Comprehensive test suite
├── benchmarks/             # Performance validation
├── web/                    # Observatory web interface (React)
├── docs/                   # Documentation (VitePress)
├── tools/                  # Development utilities
├── archive/                # Legacy implementations
├── references/             # Research papers and specs
└── zig-out/               # Build artifacts
```

## Core Source Structure (src/)

### Primary Components
- **`main.zig`** - Entry point and CLI interface
- **`root.zig`** - Library exports and public API
- **`agrama_server.zig`** - Multi-interface server orchestration

### Core Primitives System
- **`primitives.zig`** - 5 core operations implementation (1,614 lines)
- **`primitive_engine.zig`** - Execution engine with observability
- **`primitive_demo.zig`** - Usage examples and demonstrations

### Database & Storage
- **`database.zig`** - Temporal knowledge graph with anchor+delta compression
- **`semantic_database.zig`** - HNSW vector search with Matryoshka embeddings
- **`persistent_graph.zig`** - Graph persistence and recovery

### Search & Algorithms
- **`triple_hybrid_search.zig`** - BM25 + HNSW + FRE combined search
- **`hnsw.zig`** / **`hnsw_optimized.zig`** - Vector similarity search
- **`fre_true.zig`** - Frontier Reduction Engine for graph traversal
- **`bm25.zig`** - Text search and ranking
- **`bidirectional_dijkstra.zig`** - Graph pathfinding

### Memory Management
- **`memory_pools.zig`** - TigerBeetle-inspired memory optimization
- **`memory_pools_fixed.zig`** - Fixed-size pool implementations

### Interfaces & Protocols
- **`mcp_primitive_server.zig`** - Model Context Protocol interface (primary)
- **`websocket.zig`** - Real-time event streaming
- **`authenticated_websocket.zig`** - Secure WebSocket implementation

### Collaboration & CRDT
- **`crdt.zig`** - Conflict-free replicated data types
- **`crdt_manager.zig`** - CRDT orchestration
- **`orchestration_context.zig`** - Multi-participant coordination

### Utilities
- **`conversation_parser.zig`** - Chat/conversation processing
- **`graph_builder.zig`** - Dynamic graph construction
- **`mcp_utils.zig`** - MCP protocol utilities

## Testing Structure (tests/)

### Test Categories
- **`test_runner.zig`** - Main test orchestration
- **`test_infrastructure.zig`** - Comprehensive test framework
- **`integration_test.zig`** - Cross-component validation

### Primitive Testing
- **`primitive_test_runner.zig`** - Primitive-specific test suite
- **`primitive_tests.zig`** - Unit tests for all 5 primitives
- **`primitive_integration_tests.zig`** - Integration validation
- **`primitive_security_tests.zig`** - Security and safety tests
- **`primitive_performance_tests.zig`** - Performance validation

### Specialized Testing
- **`concurrent_stress_tests.zig`** - Multi-agent concurrency
- **`fuzz_test_framework.zig`** - Random input robustness
- **`memory_safety_validator.zig`** - Memory leak detection
- **`performance_regression_detector.zig`** - Performance monitoring

## Benchmarking Structure (benchmarks/)

### Benchmark Categories
- **`benchmark_suite.zig`** - Comprehensive performance validation
- **`benchmark_runner.zig`** - Benchmark orchestration framework

### Component Benchmarks
- **`hnsw_benchmarks.zig`** - Vector search performance
- **`fre_benchmarks.zig`** - Graph traversal performance
- **`database_benchmarks.zig`** - Storage and retrieval performance
- **`mcp_benchmarks.zig`** - Protocol interface performance
- **`triple_hybrid_benchmarks.zig`** - Combined search performance

### Specialized Benchmarks
- **`simd_vector_benchmarks.zig`** - SIMD optimization validation
- **`persistent_fre_benchmarks.zig`** - Persistent graph performance
- **`synthetic_graph_benchmark.zig`** - Large-scale graph testing

## Documentation Structure (docs/)

### Architecture Documentation
- **`architecture/`** - System design and component interaction
- **`mcp/`** - Model Context Protocol integration
- **`performance/`** - Performance characteristics and optimization
- **`testing/`** - Testing strategy and frameworks

### User Documentation
- **`frontend/`** - Observatory web interface documentation
- **`index.md`** - Main documentation entry point

## Web Interface Structure (web/)

### React Application
- **`src/`** - React components and application logic
- **`public/`** - Static assets and resources
- **`package.json`** - Node.js dependencies and scripts

### Configuration
- **`vite.config.ts`** - Build configuration
- **`tsconfig.json`** - TypeScript configuration
- **`eslint.config.js`** - Code quality rules

## Development Tools (tools/)

### Data Processing
- **`conversation_processor.py`** - Chat data analysis
- **`llm_analyzer.py`** - LLM interaction analysis
- **`synthetic_graphs/`** - Test data generation

### Security & Validation
- **`websocket_security_test.zig`** - Security validation
- **`websocket_security_summary.zig`** - Security reporting

## Archive Structure (archive/)

Contains legacy implementations for reference:
- **`mcp_server.zig`** - Original MCP implementation
- **`enhanced_mcp_server.zig`** - Enhanced MCP with database
- **`mcp_compliant_server.zig`** - Protocol-compliant version

## File Naming Conventions

### Zig Files
- **Snake case**: `primitive_engine.zig`, `memory_pools.zig`
- **Descriptive names**: Clearly indicate component purpose
- **Consistent suffixes**: `_test.zig`, `_benchmark.zig`, `_demo.zig`

### Test Files
- **Component tests**: `{component}_test.zig`
- **Integration tests**: `{feature}_integration_test.zig`
- **Performance tests**: `{component}_benchmarks.zig`

### Documentation
- **Uppercase**: `README.md`, `ARCHITECTURE.md`, `TODO.md`
- **Descriptive**: Clear indication of content and purpose

## Code Organization Principles

### Separation of Concerns
- **Core vs Interface**: Clear separation between core functionality and protocol adapters
- **Algorithm vs Implementation**: Algorithms in separate files from their usage
- **Test vs Production**: Complete separation of test and production code

### Dependency Management
- **Minimal Dependencies**: Self-contained implementation with only Zig stdlib
- **Clear Imports**: Explicit imports with descriptive names
- **Interface Boundaries**: Well-defined interfaces between components

### Memory Management Patterns
- **Arena Allocators**: Scoped memory management with automatic cleanup
- **Memory Pools**: Reusable allocations for performance-critical paths
- **RAII Pattern**: Resource cleanup with defer statements

## Development Workflow

### File Creation Guidelines
1. **Start with tests**: Create test file before implementation
2. **Clear interfaces**: Define public API before implementation
3. **Documentation**: Include comprehensive documentation comments
4. **Memory safety**: Use appropriate allocator patterns

### Code Quality Standards
- **Zig formatting**: Always run `zig fmt .` before commits
- **Comprehensive testing**: >95% coverage for critical components
- **Performance validation**: Benchmark critical paths
- **Memory safety**: Zero leaks in debug builds

### Build Artifact Organization
- **`zig-out/bin/`** - Executable binaries
- **`zig-out/lib/`** - Static libraries
- **Build targets**: Organized by functionality (test, bench, demo)

This structure supports the primitive-based architecture while maintaining clear separation between core functionality, interfaces, testing, and documentation.