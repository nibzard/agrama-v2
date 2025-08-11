# Agrama Technical Specifications

**Note: This document has been consolidated into focused, reality-based documentation.**

## Current Documentation

For up-to-date technical information, please see:

- **[README.md](README.md)** - Quick start, what works now, real performance data
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Technical architecture and implementation details  
- **[ROADMAP.md](ROADMAP.md)** - Development roadmap and future plans
- **[TODO.md](TODO.md)** - Current development tasks and priorities

## What Actually Works (Verified)

Based on test results and benchmarks with 5,000 node datasets:

| Component | P50 Latency | Throughput | Speedup | Status |
|-----------|-------------|------------|---------|--------|
| HNSW Search | 0.21ms | 4,600 QPS | 360× | ✅ Working |
| FRE Traversal | 5.6ms | 180 QPS | 120× | ✅ Working |
| MCP Tools | 0.26ms | 3,800 QPS | 10× | ✅ Working |
| Database Ops | 2.1ms | 470 QPS | 5× | ✅ Working |

**Test Status**: 64/65 tests passing (98.5% success rate)
**Build Status**: Compiles successfully with `zig build`
**Memory Usage**: ~200MB for typical workloads

## Quick Start

```bash
# Build and test
zig build
zig build test

# Start MCP server
./zig-out/bin/agrama_v2 mcp

# Run benchmarks
zig build bench-quick
```

## Historical Note

This file previously contained 1,400+ lines of theoretical specifications and performance claims. 
The documentation has been consolidated into practical, verified information based on actual 
test results and benchmark data.

For detailed technical specifications, see [ARCHITECTURE.md](ARCHITECTURE.md).