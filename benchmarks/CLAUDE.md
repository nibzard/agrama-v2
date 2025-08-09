# CLAUDE.md - Benchmark Development Instructions

This file provides specific guidance to Claude Code when developing benchmarks for Agrama.

## Benchmark Development Priority

**ALWAYS implement benchmarks BEFORE features.** This is non-negotiable for Agrama's performance-critical components.

## Benchmark Implementation Workflow

### 1. When Asked to Implement a Feature
```bash
# STOP! First check if benchmark exists
ls benchmarks/<feature_category>/

# If no benchmark exists, create it FIRST
# Example: Implementing HNSW search
touch benchmarks/hnsw/query_benchmark.zig
```

### 2. Benchmark Structure Template
```zig
// benchmarks/<category>/<feature>_benchmark.zig
const std = @import("std");
const Timer = std.time.Timer;
const expect = std.testing.expect;

// Define performance targets FIRST
const PERFORMANCE_TARGETS = .{
    .p50_ms = 1.0,
    .p99_ms = 10.0,
    .throughput_qps = 1000,
    .memory_mb = 100,
};

// Benchmark harness
pub fn benchmark(allocator: std.mem.Allocator) !BenchmarkResult {
    // Setup
    const dataset = try generateDataset(allocator);
    defer dataset.deinit();
    
    // Warmup (critical for accurate measurements)
    for (0..100) |_| {
        _ = try runOperation(dataset);
    }
    
    // Measure
    var latencies = std.ArrayList(f64).init(allocator);
    defer latencies.deinit();
    
    var timer = try Timer.start();
    const iterations = 10_000;
    
    for (0..iterations) |_| {
        timer.reset();
        _ = try runOperation(dataset);
        try latencies.append(@as(f64, @floatFromInt(timer.read())) / 1_000_000.0);
    }
    
    // Calculate metrics
    return .{
        .p50 = percentile(latencies.items, 50),
        .p99 = percentile(latencies.items, 99),
        .throughput = @as(f64, iterations) / total_time_seconds,
        .memory_used = process.memoryUsed(),
    };
}

// Test that validates performance targets
test "performance meets targets" {
    const result = try benchmark(std.testing.allocator);
    
    try expect(result.p50 <= PERFORMANCE_TARGETS.p50_ms);
    try expect(result.p99 <= PERFORMANCE_TARGETS.p99_ms);
    try expect(result.throughput >= PERFORMANCE_TARGETS.throughput_qps);
    try expect(result.memory_used <= PERFORMANCE_TARGETS.memory_mb * 1024 * 1024);
}
```

### 3. Data Generation Rules
```zig
// ALWAYS use realistic data distributions
pub fn generateDataset(allocator: Allocator, size: usize) !Dataset {
    // DO: Use realistic distributions
    // - Zipfian for access patterns
    // - Gaussian for numeric values
    // - Real text for string data
    
    // DON'T: Use uniform random data
    // This hides cache effects and real-world patterns
}
```

### 4. Benchmark Categories to Implement

#### Critical Path Benchmarks (P0 - Implement First)
```
benchmarks/
├── hnsw/
│   ├── build_benchmark.zig      # Index construction speed
│   ├── query_benchmark.zig      # Search performance
│   └── memory_benchmark.zig     # Memory efficiency
├── fre/
│   ├── traversal_benchmark.zig  # Graph traversal speed
│   └── frontier_benchmark.zig   # Frontier management
└── hybrid/
    └── query_benchmark.zig       # Combined semantic+graph
```

#### System Benchmarks (P1 - After Core Features)
```
benchmarks/
├── storage/
│   ├── compression_benchmark.zig # Anchor+delta efficiency
│   └── io_benchmark.zig         # Disk I/O performance
├── crdt/
│   └── merge_benchmark.zig      # CRDT merge performance
└── mcp/
    └── tool_benchmark.zig        # MCP tool latency
```

## Benchmark Execution Commands

```bash
# After creating a benchmark, ALWAYS run it
zig build bench -Dfile=benchmarks/hnsw/query_benchmark.zig

# Generate performance profile
zig build bench -Dprofile=true -Dfile=benchmarks/hnsw/query_benchmark.zig

# Compare against baseline
zig build bench -Dcompare=baseline.json -Dfile=benchmarks/hnsw/query_benchmark.zig

# Run all benchmarks in category
zig build bench -Dcategory=hnsw

# Generate HTML report
zig build bench -Dreport=html > benchmarks/results/report.html
```

## Performance Analysis Workflow

When a benchmark fails to meet targets:

1. **Profile First**
```bash
# Generate flamegraph
zig build bench -Dflamegraph=true
# Output: benchmarks/results/flamegraph.svg
```

2. **Identify Hotspots**
```bash
# Use perf on Linux
perf record -g zig-out/bin/benchmark
perf report
```

3. **Optimize Systematically**
```zig
// Document optimization attempts
// benchmarks/optimizations.md
## Attempt 1: Cache-friendly data layout
- Change: Restructured Node to fit cache line
- Result: 15% improvement in P50 latency
- Status: Kept

## Attempt 2: SIMD vectorization
- Change: Used @Vector for distance calculations
- Result: 40% improvement in throughput
- Status: Kept
```

## Benchmark Result Interpretation

### Reading Benchmark Output
```
HNSW Query Benchmark Results:
============================
Dataset: 1,000,000 vectors, 1536 dimensions
Queries: 10,000 random vectors

Latency Percentiles:
  P50:  0.89ms ✅ (target: <1ms)
  P90:  2.34ms ✅ (target: <5ms)
  P99:  8.72ms ✅ (target: <10ms)
  P99.9: 15.23ms ⚠️ (target: <15ms)

Throughput: 1,123 QPS ✅ (target: >1000)
Memory: 8.2GB ✅ (target: <10GB)
Recall@10: 0.967 ✅ (target: >0.95)
```

### Regression Detection
```zig
// Automatically flag performance regressions
const REGRESSION_THRESHOLD = 0.05; // 5% degradation

pub fn detectRegression(baseline: BenchmarkResult, current: BenchmarkResult) !void {
    if (current.p50 > baseline.p50 * (1 + REGRESSION_THRESHOLD)) {
        std.log.warn("Performance regression detected: P50 degraded by {d:.1}%", .{
            (current.p50 / baseline.p50 - 1) * 100
        });
        return error.PerformanceRegression;
    }
}
```

## Common Benchmark Pitfalls to Avoid

### 1. Benchmarking Debug Builds
```bash
# WRONG - Debug builds have safety checks
zig build bench

# CORRECT - Use optimized builds
zig build bench -Doptimize=ReleaseSafe
```

### 2. Insufficient Warmup
```zig
// WRONG - First iterations affected by cold cache
for (0..iterations) |i| {
    latencies[i] = measureOperation();
}

// CORRECT - Warmup before measuring
for (0..warmup_iterations) |_| {
    _ = runOperation(); // Discard results
}
for (0..iterations) |i| {
    latencies[i] = measureOperation();
}
```

### 3. Unrealistic Data
```zig
// WRONG - Uniform random hides patterns
const data = try random.generateUniform(size);

// CORRECT - Realistic distributions
const data = try generator.generateZipfian(size, skew=1.2);
```

### 4. Ignoring Memory
```zig
// WRONG - Only measuring time
const time = timer.read();

// CORRECT - Track memory too
const result = .{
    .time = timer.read(),
    .memory = process.memoryUsed(),
    .allocations = allocator.stats.allocations,
};
```

## Benchmark-First Examples

### Example 1: Implementing HNSW Search
```bash
# User: "Implement HNSW search functionality"

# Step 1: Create benchmark FIRST
touch benchmarks/hnsw/search_benchmark.zig

# Step 2: Define targets in benchmark
# PERFORMANCE_TARGETS = .{ .p50_ms = 1.0, .recall = 0.95 }

# Step 3: Run benchmark (will fail - no implementation)
zig build bench -Dfile=benchmarks/hnsw/search_benchmark.zig
# Error: HNSW.search not found

# Step 4: Implement minimal version
touch src/hnsw.zig
# Implement basic search

# Step 5: Run benchmark again
zig build bench -Dfile=benchmarks/hnsw/search_benchmark.zig
# P50: 45ms ❌ (target: 1ms)

# Step 6: Optimize until targets met
# - Add hierarchical layers
# - Implement pruning
# - Cache-align structures

# Step 7: Verify targets met
zig build bench -Dfile=benchmarks/hnsw/search_benchmark.zig
# P50: 0.89ms ✅ (target: 1ms)
```

### Example 2: Implementing FRE
```bash
# User: "Implement Frontier Reduction Engine"

# Step 1: Create comparison benchmark
touch benchmarks/fre/dijkstra_comparison.zig

# Step 2: Implement Dijkstra baseline
# Measure Dijkstra performance first

# Step 3: Define FRE targets
# Must be 5× faster than Dijkstra baseline

# Step 4: Implement FRE with benchmark validation
# Continue until 5× speedup achieved
```

## Integration with CI/CD

```yaml
# .github/workflows/benchmark.yml
name: Performance Benchmarks
on: [push, pull_request]

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        
      - name: Run Benchmarks
        run: |
          zig build bench -Doptimize=ReleaseSafe
          
      - name: Check for Regressions
        run: |
          zig build bench-compare -Dbaseline=main
          
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: benchmark-results
          path: benchmarks/results/
          
      - name: Comment on PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v6
        with:
          script: |
            const results = require('./benchmarks/results/summary.json');
            await github.rest.issues.createComment({
              issue_number: context.issue.number,
              body: generateBenchmarkComment(results)
            });
```

## Quick Reference Commands

```bash
# Create new benchmark
mkdir -p benchmarks/<category>
touch benchmarks/<category>/<feature>_benchmark.zig

# Run single benchmark
zig build bench -Dfile=benchmarks/<category>/<feature>_benchmark.zig

# Run with optimization
zig build bench -Doptimize=ReleaseFast -Dfile=<path>

# Generate profile
zig build bench -Dprofile=true -Dfile=<path>

# Compare with baseline
zig build bench -Dcompare=baseline.json -Dfile=<path>

# Run all benchmarks
zig build bench

# Generate report
zig build bench -Dreport=html > report.html
```

## Remember

1. **Benchmark BEFORE implementing** - Encode targets as tests
2. **Use realistic data** - Synthetic data hides real issues
3. **Measure comprehensively** - Time, memory, percentiles
4. **Guard against regression** - Every commit runs benchmarks
5. **Profile before optimizing** - Data-driven optimization
6. **Document optimizations** - Track what worked and why

The benchmark suite is as important as the test suite. Without it, Agrama's performance claims are just marketing.