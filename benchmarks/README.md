# Benchmark-Driven Development

## Why Benchmark-Driven Development?

Agrama's core value proposition is **performance at scale**. Our algorithms promise revolutionary improvements:
- **HNSW**: 100-1000× faster semantic search than linear scan
- **FRE**: 5-50× faster graph traversal than Dijkstra
- **Anchor+Delta**: 5× storage efficiency over naive approaches
- **Query Response**: Sub-10ms for hybrid queries on 1M+ nodes

Without rigorous benchmarking, these are just claims. Benchmark-driven development ensures we:
1. **Validate** algorithmic complexity claims with real data
2. **Prevent** performance regressions during development
3. **Guide** optimization efforts with empirical evidence
4. **Demonstrate** value to users with reproducible metrics

## Benchmark Categories

### 1. Algorithmic Benchmarks
Validate theoretical complexity bounds with empirical measurements.

```
benchmarks/
├── hnsw/                 # O(log n) semantic search validation
│   ├── build_time.zig    # Index construction performance
│   ├── query_time.zig    # Search performance vs dataset size
│   └── recall.zig        # Accuracy vs speed tradeoffs
├── fre/                  # O(m log^(2/3) n) traversal validation
│   ├── dijkstra_comparison.zig
│   ├── scaling.zig       # Performance vs graph size
│   └── frontier_size.zig # Memory usage patterns
└── crdt/                 # Conflict resolution performance
    ├── merge_time.zig
    └── memory_overhead.zig
```

### 2. System Benchmarks
End-to-end performance of integrated components.

```
benchmarks/
├── hybrid_query/         # Combined semantic + graph queries
│   ├── latency_p50.zig
│   ├── latency_p99.zig
│   └── throughput.zig
├── storage/              # Anchor+delta compression
│   ├── compression_ratio.zig
│   ├── write_throughput.zig
│   └── read_latency.zig
└── mcp_server/           # AI agent tool performance
    ├── tool_latency.zig
    └── concurrent_agents.zig
```

### 3. Regression Benchmarks
Continuous performance monitoring across commits.

```
benchmarks/
└── regression/
    ├── baseline.json     # Performance baseline
    ├── runner.zig        # Automated benchmark runner
    └── reporter.zig      # Regression detection & alerts
```

## Benchmark Development Workflow

### 1. Define Performance Target
Before implementing any feature, establish measurable performance goals:

```zig
// Example: HNSW query benchmark target
const TARGET_SPECS = .{
    .dataset_size = 1_000_000,      // 1M vectors
    .dimension = 1536,               // OpenAI embedding size
    .query_count = 10_000,
    .p50_target_ms = 1.0,            // 50th percentile < 1ms
    .p99_target_ms = 10.0,           // 99th percentile < 10ms
    .recall_target = 0.95,           // 95% recall@10
};
```

### 2. Implement Benchmark First
Write the benchmark before the feature (TDD for performance):

```zig
test "HNSW query performance meets targets" {
    const index = try HNSW.build(test_vectors);
    
    var timer = Timer.start();
    var latencies = ArrayList(f64).init(allocator);
    
    for (queries) |query| {
        timer.reset();
        _ = try index.search(query, 10);
        try latencies.append(timer.read());
    }
    
    const p50 = percentile(latencies, 50);
    const p99 = percentile(latencies, 99);
    
    try expect(p50 < TARGET_SPECS.p50_target_ms);
    try expect(p99 < TARGET_SPECS.p99_target_ms);
}
```

### 3. Iterate Until Target Met
Use profiling data to guide optimization:

```bash
# Run benchmark with profiling
zig build bench -Dprofile=true

# Analyze hotspots
perf report

# Iterate on implementation
# Re-run benchmark
```

### 4. Guard Against Regression
Add to continuous benchmark suite:

```zig
// benchmarks/regression/suite.zig
pub const REGRESSION_SUITE = .{
    .{ "hnsw_query", hnsw.query_benchmark },
    .{ "fre_traversal", fre.traversal_benchmark },
    .{ "hybrid_query", hybrid.query_benchmark },
};

// Automatically run on CI
// Alert if >5% performance degradation
```

## Benchmark Guidelines

### DO:
- **Measure first, optimize second** - Profile before optimizing
- **Use realistic datasets** - Synthetic data hides real bottlenecks
- **Benchmark at scale** - Small datasets hide algorithmic complexity
- **Track memory AND time** - Space-time tradeoffs matter
- **Include warmup runs** - Avoid JIT/cache effects
- **Report percentiles** - Averages hide tail latency
- **Version benchmarks** - Track performance over time

### DON'T:
- **Micro-optimize prematurely** - Focus on algorithmic wins first
- **Benchmark in debug mode** - Always use ReleaseSafe or ReleaseFast
- **Ignore variance** - High variance indicates unstable performance
- **Cherry-pick results** - Report comprehensive metrics
- **Benchmark without context** - Include hardware/OS specs

## Benchmark Infrastructure

### Running Benchmarks
```bash
# Run all benchmarks
zig build bench

# Run specific category
zig build bench -Dcategory=hnsw

# Run with comparison to baseline
zig build bench -Dcompare=true

# Generate performance report
zig build bench -Dreport=html
```

### Benchmark Utilities
```zig
// benchmarks/utils.zig
pub const BenchmarkTimer = struct { ... };
pub const DataGenerator = struct { ... };
pub const MetricsReporter = struct { ... };
pub const RegressionDetector = struct { ... };
```

### CI Integration
```yaml
# .github/workflows/benchmark.yml
on: [push, pull_request]
jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: goto-bus-stop/setup-zig@v1
      - run: zig build bench -Dcompare=true
      - uses: actions/upload-artifact@v2
        with:
          name: benchmark-results
          path: benchmarks/results/
```

## Performance Targets Summary

| Component | Metric | Target | Rationale |
|-----------|---------|---------|-----------|
| HNSW Search | P50 Latency | <1ms | Enables real-time UX |
| HNSW Search | P99 Latency | <10ms | Acceptable tail latency |
| FRE Traversal | vs Dijkstra | 5-50× faster | Justifies complexity |
| Hybrid Query | P50 Latency | <10ms | Sub-perceptual delay |
| Storage | Compression | 5× reduction | Cost-effective at scale |
| MCP Tools | Response Time | <100ms | Smooth AI interaction |
| Memory | 1M nodes | <10GB | Fits in typical RAM |
| Throughput | Queries/sec | >1000 | Supports many agents |

## Benchmark-First Development Process

1. **Receive requirement** → Define performance target
2. **Write benchmark** → Encode target as test
3. **Run benchmark** → Establish baseline (will fail)
4. **Implement feature** → Focus on correctness first
5. **Optimize** → Use profiling to meet targets
6. **Verify** → Benchmark confirms target met
7. **Guard** → Add to regression suite
8. **Document** → Update performance characteristics

This approach ensures Agrama delivers on its performance promises with empirical evidence, not just theoretical claims.

## Current Benchmark Status

| Benchmark | Status | Target | Current | Notes |
|-----------|---------|---------|----------|--------|
| HNSW Build | 🔴 Not Started | - | - | Awaiting implementation |
| HNSW Query | 🔴 Not Started | <1ms P50 | - | Awaiting implementation |
| FRE Traversal | 🔴 Not Started | 5× Dijkstra | - | Awaiting implementation |
| Hybrid Query | 🔴 Not Started | <10ms P50 | - | Awaiting implementation |
| Anchor+Delta | 🔴 Not Started | 5× compression | - | Awaiting implementation |
| MCP Latency | 🔴 Not Started | <100ms | - | Awaiting implementation |

Legend: 🟢 Passing | 🟡 Degraded | 🔴 Failing/Not Started

---

*"Performance is a feature. Benchmark-driven development ensures we deliver it."*