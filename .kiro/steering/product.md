# Agrama - Memory Substrate for the AI Agent Age

Agrama is a revolutionary temporal knowledge graph that serves as shared memory and communication substrate for multi-agent AI systems. Built in Zig for sub-millisecond performance, it represents a paradigm shift from building complex tools for AI agents to providing simple primitives that LLMs can compose into any memory architecture they need.

## Core Philosophy

**From Complex → Simple**: Replace 50+ parameter tools with 5 composable primitives  
**From Fixed → Adaptive**: Let LLMs design their own memory patterns  
**From Single → Multi-Agent**: Enable seamless collaboration through shared primitives  
**From Static → Temporal**: Full history and evolution tracking for all operations

## The 5 Core Primitives

1. **STORE**: Universal storage with rich metadata and provenance tracking
2. **RETRIEVE**: Data access with history and context
3. **SEARCH**: Unified search (semantic/lexical/graph/temporal/hybrid)
4. **LINK**: Knowledge graph relationships with metadata
5. **TRANSFORM**: Extensible operation registry for data transformation

## Key Features

- **Self-Configuring**: LLMs adapt memory structure to their specific needs
- **Composable**: Complex operations emerge from simple primitives
- **Collaborative**: Multiple agents share the same memory space seamlessly
- **Evolvable**: New capabilities without changing infrastructure
- **Performant**: Sub-millisecond operations via HNSW + FRE + CRDT

## Target Performance

- **Response Time**: <1ms P50 for primitive operations
- **Throughput**: 1000+ primitive ops/second
- **Memory Usage**: Fixed allocation <10GB for 1M entities
- **Storage Efficiency**: 5× reduction through anchor+delta compression

## Current Status

**Production Ready**: All critical stability issues resolved with 71/71 tests passing (100% success rate). Core primitive system implemented with comprehensive memory optimization and full observability.