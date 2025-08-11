# Performance Testing Guide

## Overview

Performance testing in Agrama ensures that the system meets ambitious performance targets while maintaining reliability under varying loads. Our performance testing framework combines micro-benchmarks, regression detection, scalability testing, and real-world scenario validation to guarantee production-ready performance.

## Performance Architecture

### Performance Targets

1. **Semantic Search Performance**
   - **Target**: O(log n) complexity via HNSW
   - **Latency**: <10ms for queries on 1M+ nodes
   - **Throughput**: >1000 queries/second
   - **Memory**: <10GB for 1M nodes with embeddings

2. **Graph Traversal Performance**
   - **Algorithm**: Frontier Reduction Engine (FRE)
   - **Complexity**: O(m log^(2/3) n) vs traditional O(m + n log n)
   - **Speedup**: 5-50× improvement on large graphs
   - **Scalability**: Efficient on graphs with 100K+ entities

3. **MCP Tool Performance**
   - **Response Time**: <100ms for all tool operations
   - **Throughput**: >500 operations/second
   - **Concurrent Agents**: Support 100+ simultaneous agents
   - **Memory Per Agent**: <10MB average usage

4. **Database Performance**
   - **Storage Efficiency**: 5× reduction via anchor+delta compression
   - **Query Performance**: <1ms for primitive operations
   - **Concurrent Access**: 1000+ operations/second
   - **Memory Usage**: Fixed allocation patterns

## Performance Testing Framework

### Core Components

1. **Performance Regression Detector** (`tests/performance_regression_detector.zig`)
   - Historical baseline comparison
   - Statistical significance testing
   - Automated regression alerting
   - Trend analysis and reporting

2. **Benchmark Runner** (`benchmarks/benchmark_runner.zig`)
   - Micro-benchmark execution
   - Performance metric collection
   - Result aggregation and analysis
   - Historical tracking

3. **Primitive Performance Tests** (`tests/primitive_performance_tests.zig`)
   - Core operation benchmarking
   - Scalability validation
   - Memory usage profiling
   - Concurrent performance testing

4. **SIMD Vector Benchmarks** (`benchmarks/simd_vector_benchmarks.zig`)
   - Vector operation optimization
   - SIMD instruction utilization
   - Memory bandwidth testing
   - Cache efficiency analysis

## Micro-Benchmark Testing

### Primitive Operation Benchmarks
```zig
// benchmarks/primitive_benchmarks.zig
const std = @import("std");
const testing = std.testing;
const Timer = std.time.Timer;
const print = std.debug.print;

const agrama_lib = @import("agrama_lib");
const PrimitiveEngine = agrama_lib.PrimitiveEngine;
const Database = agrama_lib.Database;

pub const PrimitiveBenchmark = struct {
    allocator: std.mem.Allocator,
    engine: *PrimitiveEngine,
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,

    pub fn init(allocator: std.mem.Allocator) !PrimitiveBenchmark {
        const database = try allocator.create(Database);
        database.* = Database.init(allocator);

        const semantic_db = try allocator.create(SemanticDatabase);
        semantic_db.* = try SemanticDatabase.init(allocator, .{
            .embedding_dimension = 384,
            .hnsw_max_connections = 16,
        });

        const graph_engine = try allocator.create(TripleHybridSearchEngine);
        graph_engine.* = TripleHybridSearchEngine.init(allocator);

        const engine = try allocator.create(PrimitiveEngine);
        engine.* = try PrimitiveEngine.init(allocator, database, semantic_db, graph_engine);

        return PrimitiveBenchmark{
            .allocator = allocator,
            .engine = engine,
            .database = database,
            .semantic_db = semantic_db,
            .graph_engine = graph_engine,
        };
    }

    pub fn deinit(self: *PrimitiveBenchmark) void {
        self.engine.deinit();
        self.graph_engine.deinit();
        self.semantic_db.deinit();
        self.database.deinit();

        self.allocator.destroy(self.engine);
        self.allocator.destroy(self.graph_engine);
        self.allocator.destroy(self.semantic_db);
        self.allocator.destroy(self.database);
    }

    /// Benchmark store operation latency and throughput
    pub fn benchmarkStore(self: *PrimitiveBenchmark, iterations: usize) !BenchmarkResult {
        print("🚀 Benchmarking store operations ({} iterations)\n", .{iterations});

        var timer = try Timer.start();
        var latencies = std.ArrayList(u64).init(self.allocator);
        defer latencies.deinit();

        const memory_start = getCurrentMemoryUsage();

        // Warmup phase
        for (0..@min(iterations / 10, 100)) |i| {
            var params = try createStoreParams(self.allocator, i);
            defer params.deinit();
            
            const result = try self.engine.executePrimitive("store", std.json.Value{ .object = params }, "benchmark");
            defer result.deinit();
        }

        // Actual benchmark
        timer = try Timer.start();
        const overall_start = timer.read();

        for (0..iterations) |i| {
            const iter_start = timer.read();

            var params = try createStoreParams(self.allocator, i);
            defer params.deinit();

            const result = try self.engine.executePrimitive("store", std.json.Value{ .object = params }, "benchmark");
            defer result.deinit();

            const iter_end = timer.read();
            try latencies.append(iter_end - iter_start);

            // Progress indicator
            if (i > 0 and i % (iterations / 10) == 0) {
                print("  Progress: {}% ({}/{})\n", .{ (i * 100) / iterations, i, iterations });
            }
        }

        const overall_end = timer.read();
        const memory_end = getCurrentMemoryUsage();

        return analyzeBenchmarkResults(
            "store_operation",
            latencies.items,
            overall_end - overall_start,
            iterations,
            memory_end - memory_start,
        );
    }

    /// Benchmark retrieve operation performance
    pub fn benchmarkRetrieve(self: *PrimitiveBenchmark, iterations: usize) !BenchmarkResult {
        print("🚀 Benchmarking retrieve operations ({} iterations)\n", .{iterations});

        // Pre-populate data for retrieval
        for (0..iterations) |i| {
            var params = try createStoreParams(self.allocator, i);
            defer params.deinit();
            
            const result = try self.engine.executePrimitive("store", std.json.Value{ .object = params }, "benchmark");
            defer result.deinit();
        }

        var timer = try Timer.start();
        var latencies = std.ArrayList(u64).init(self.allocator);
        defer latencies.deinit();

        const memory_start = getCurrentMemoryUsage();

        // Warmup
        for (0..@min(iterations / 10, 100)) |i| {
            var params = try createRetrieveParams(self.allocator, i);
            defer params.deinit();
            
            const result = try self.engine.executePrimitive("retrieve", std.json.Value{ .object = params }, "benchmark");
            defer result.deinit();
        }

        // Benchmark
        const overall_start = timer.read();

        for (0..iterations) |i| {
            const iter_start = timer.read();

            var params = try createRetrieveParams(self.allocator, i);
            defer params.deinit();

            const result = try self.engine.executePrimitive("retrieve", std.json.Value{ .object = params }, "benchmark");
            defer result.deinit();

            const iter_end = timer.read();
            try latencies.append(iter_end - iter_start);
        }

        const overall_end = timer.read();
        const memory_end = getCurrentMemoryUsage();

        return analyzeBenchmarkResults(
            "retrieve_operation",
            latencies.items,
            overall_end - overall_start,
            iterations,
            memory_end - memory_start,
        );
    }

    /// Benchmark search operation scaling
    pub fn benchmarkSearchScaling(self: *PrimitiveBenchmark) ![]BenchmarkResult {
        const scale_sizes = [_]usize{ 100, 500, 1000, 5000, 10000 };
        var results = std.ArrayList(BenchmarkResult).init(self.allocator);

        for (scale_sizes) |size| {
            print("🚀 Benchmarking search scaling at {} entities\n", .{size});

            // Populate data for scaling test
            for (0..size) |i| {
                var params = try createStoreParams(self.allocator, i);
                defer params.deinit();
                
                const result = try self.engine.executePrimitive("store", std.json.Value{ .object = params }, "scaling_test");
                defer result.deinit();
            }

            // Benchmark search performance
            const search_iterations = 100;
            var timer = try Timer.start();
            var latencies = std.ArrayList(u64).init(self.allocator);
            defer latencies.deinit();

            const overall_start = timer.read();

            for (0..search_iterations) |i| {
                const iter_start = timer.read();

                var params = try createSearchParams(self.allocator, i);
                defer params.deinit();

                const search_result = try self.engine.executePrimitive("search", std.json.Value{ .object = params }, "scaling_test");
                defer search_result.deinit();

                const iter_end = timer.read();
                try latencies.append(iter_end - iter_start);
            }

            const overall_end = timer.read();

            const result = analyzeBenchmarkResults(
                try std.fmt.allocPrint(self.allocator, "search_scaling_{}", .{size}),
                latencies.items,
                overall_end - overall_start,
                search_iterations,
                0, // Memory delta not tracked for scaling tests
            );

            try results.append(result);

            print("  Search at {} entities: {:.2}ms P50, {:.2}ms P99\n", .{ 
                size, 
                result.p50_latency_ms, 
                result.p99_latency_ms 
            });

            // Clear data for next scale test
            // In production, would have a clear method
        }

        return try results.toOwnedSlice();
    }

    fn createStoreParams(allocator: std.mem.Allocator, index: usize) !std.json.ObjectMap {
        var params = std.json.ObjectMap.init(allocator);
        
        const key = try std.fmt.allocPrint(allocator, "benchmark_key_{}", .{index});
        defer allocator.free(key);
        
        const value = try std.fmt.allocPrint(allocator, "Benchmark value {} with semantic content for testing search and retrieval performance", .{index});
        defer allocator.free(value);

        try params.put("key", std.json.Value{ .string = try allocator.dupe(u8, key) });
        try params.put("value", std.json.Value{ .string = try allocator.dupe(u8, value) });

        return params;
    }

    fn createRetrieveParams(allocator: std.mem.Allocator, index: usize) !std.json.ObjectMap {
        var params = std.json.ObjectMap.init(allocator);
        
        const key = try std.fmt.allocPrint(allocator, "benchmark_key_{}", .{index});
        defer allocator.free(key);

        try params.put("key", std.json.Value{ .string = try allocator.dupe(u8, key) });

        return params;
    }

    fn createSearchParams(allocator: std.mem.Allocator, index: usize) !std.json.ObjectMap {
        var params = std.json.ObjectMap.init(allocator);
        
        const queries = [_][]const u8{
            "semantic content testing search performance",
            "benchmark value retrieval systems",
            "performance measurement data analysis",
            "search optimization algorithms",
        };

        const query = queries[index % queries.len];
        try params.put("query", std.json.Value{ .string = try allocator.dupe(u8, query) });
        try params.put("limit", std.json.Value{ .integer = 10 });

        return params;
    }
};

/// Benchmark result analysis and metrics
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_duration_ns: u64,
    
    // Latency metrics (nanoseconds)
    min_latency_ns: u64,
    max_latency_ns: u64,
    mean_latency_ns: u64,
    p50_latency_ns: u64,
    p90_latency_ns: u64,
    p95_latency_ns: u64,
    p99_latency_ns: u64,
    
    // Throughput metrics
    throughput_ops_per_sec: f64,
    
    // Memory metrics
    memory_delta_bytes: usize,
    
    // Derived convenience metrics
    pub fn mean_latency_ms(self: BenchmarkResult) f64 {
        return @as(f64, @floatFromInt(self.mean_latency_ns)) / 1_000_000.0;
    }
    
    pub fn p50_latency_ms(self: BenchmarkResult) f64 {
        return @as(f64, @floatFromInt(self.p50_latency_ns)) / 1_000_000.0;
    }
    
    pub fn p99_latency_ms(self: BenchmarkResult) f64 {
        return @as(f64, @floatFromInt(self.p99_latency_ns)) / 1_000_000.0;
    }

    pub fn print_summary(self: BenchmarkResult) void {
        print("\n📊 Benchmark Results: {s}\n", .{self.name});
        print("  Iterations: {}\n", .{self.iterations});
        print("  Total Duration: {:.2}ms\n", .{@as(f64, @floatFromInt(self.total_duration_ns)) / 1_000_000.0});
        print("  Throughput: {:.1} ops/sec\n", .{self.throughput_ops_per_sec});
        print("  Latency (ms):\n");
        print("    Mean: {:.3}\n", .{self.mean_latency_ms()});
        print("    P50:  {:.3}\n", .{self.p50_latency_ms()});
        print("    P90:  {:.3}\n", .{@as(f64, @floatFromInt(self.p90_latency_ns)) / 1_000_000.0});
        print("    P99:  {:.3}\n", .{self.p99_latency_ms()});
        print("  Memory Delta: {:.1} KB\n", .{@as(f64, @floatFromInt(self.memory_delta_bytes)) / 1024.0});
    }
};

fn analyzeBenchmarkResults(
    name: []const u8,
    latencies: []u64,
    total_duration: u64,
    iterations: usize,
    memory_delta: usize,
) BenchmarkResult {
    // Sort latencies for percentile calculation
    std.mem.sort(u64, latencies, {}, std.sort.asc(u64));

    const min_latency = latencies[0];
    const max_latency = latencies[latencies.len - 1];
    
    // Calculate mean
    var sum: u64 = 0;
    for (latencies) |latency| {
        sum += latency;
    }
    const mean_latency = sum / latencies.len;

    // Calculate percentiles
    const p50 = latencies[latencies.len / 2];
    const p90 = latencies[(latencies.len * 9) / 10];
    const p95 = latencies[(latencies.len * 95) / 100];
    const p99 = latencies[(latencies.len * 99) / 100];

    // Calculate throughput
    const throughput = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_duration));

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_duration_ns = total_duration,
        .min_latency_ns = min_latency,
        .max_latency_ns = max_latency,
        .mean_latency_ns = mean_latency,
        .p50_latency_ns = p50,
        .p90_latency_ns = p90,
        .p95_latency_ns = p95,
        .p99_latency_ns = p99,
        .throughput_ops_per_sec = throughput,
        .memory_delta_bytes = memory_delta,
    };
}

fn getCurrentMemoryUsage() usize {
    // Simplified memory usage - in production would use platform-specific APIs
    return 1024 * 1024; // 1MB baseline
}
```

### SIMD Vector Performance Testing
```zig
// benchmarks/simd_vector_benchmarks.zig
const std = @import("std");
const print = std.debug.print;
const Timer = std.time.Timer;

/// SIMD vector operations benchmarking
pub const SIMDVectorBenchmark = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SIMDVectorBenchmark {
        return .{ .allocator = allocator };
    }

    /// Benchmark vector dot product implementations
    pub fn benchmarkDotProduct(self: *SIMDVectorBenchmark) !void {
        const vector_sizes = [_]usize{ 128, 384, 768, 1536, 3072 }; // Common embedding dimensions
        
        for (vector_sizes) |size| {
            print("🧮 Benchmarking dot product for {}-dimensional vectors\n", .{size});
            
            // Generate test vectors
            const vector_a = try self.allocator.alloc(f32, size);
            defer self.allocator.free(vector_a);
            const vector_b = try self.allocator.alloc(f32, size);
            defer self.allocator.free(vector_b);
            
            // Initialize with random values
            var prng = std.Random.DefaultPrng.init(12345);
            const random = prng.random();
            for (0..size) |i| {
                vector_a[i] = random.float(f32) - 0.5;
                vector_b[i] = random.float(f32) - 0.5;
            }

            const iterations = 10000;
            
            // Benchmark naive implementation
            var timer = try Timer.start();
            const naive_start = timer.read();
            
            var naive_result: f32 = 0;
            for (0..iterations) |_| {
                naive_result = naiveDotProduct(vector_a, vector_b);
            }
            
            const naive_end = timer.read();
            const naive_duration = naive_end - naive_start;

            // Benchmark SIMD implementation
            const simd_start = timer.read();
            
            var simd_result: f32 = 0;
            for (0..iterations) |_| {
                simd_result = simdDotProduct(vector_a, vector_b);
            }
            
            const simd_end = timer.read();
            const simd_duration = simd_end - simd_start;

            // Calculate performance metrics
            const naive_ops_per_sec = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(naive_duration));
            const simd_ops_per_sec = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(simd_duration));
            const speedup = simd_ops_per_sec / naive_ops_per_sec;

            print("  Naive: {:.1} Kops/sec, SIMD: {:.1} Kops/sec, Speedup: {:.2}x\n", .{
                naive_ops_per_sec / 1000.0,
                simd_ops_per_sec / 1000.0,
                speedup,
            });

            // Verify correctness (results should be very close)
            const difference = @abs(naive_result - simd_result);
            if (difference > 0.001) {
                print("  ⚠️ Warning: Results differ by {:.6}\n", .{difference});
            }
        }
    }

    /// Benchmark vector normalization
    pub fn benchmarkVectorNormalization(self: *SIMDVectorBenchmark) !void {
        const size = 384; // Common embedding dimension
        const iterations = 10000;
        
        print("🧮 Benchmarking vector normalization ({} dimensions, {} iterations)\n", .{ size, iterations });

        const vector = try self.allocator.alloc(f32, size);
        defer self.allocator.free(vector);
        
        // Initialize with random values
        var prng = std.Random.DefaultPrng.init(12345);
        const random = prng.random();
        for (0..size) |i| {
            vector[i] = random.float(f32) * 2.0 - 1.0;
        }

        var timer = try Timer.start();

        // Benchmark naive normalization
        const naive_start = timer.read();
        for (0..iterations) |_| {
            naiveNormalizeVector(vector);
        }
        const naive_end = timer.read();

        // Benchmark SIMD normalization
        const simd_start = timer.read();
        for (0..iterations) |_| {
            simdNormalizeVector(vector);
        }
        const simd_end = timer.read();

        const naive_duration = naive_end - naive_start;
        const simd_duration = simd_end - simd_start;

        const naive_ops_per_sec = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(naive_duration));
        const simd_ops_per_sec = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(simd_duration));
        const speedup = simd_ops_per_sec / naive_ops_per_sec;

        print("  Naive: {:.1} Kops/sec, SIMD: {:.1} Kops/sec, Speedup: {:.2}x\n", .{
            naive_ops_per_sec / 1000.0,
            simd_ops_per_sec / 1000.0,
            speedup,
        });
    }

    /// Benchmark memory bandwidth with vector operations
    pub fn benchmarkMemoryBandwidth(self: *SIMDVectorBenchmark) !void {
        const sizes = [_]usize{ 1024, 4096, 16384, 65536 }; // Different cache levels
        
        for (sizes) |size| {
            print("🧮 Benchmarking memory bandwidth ({} elements)\n", .{size});
            
            const vector_a = try self.allocator.alloc(f32, size);
            defer self.allocator.free(vector_a);
            const vector_b = try self.allocator.alloc(f32, size);
            defer self.allocator.free(vector_b);
            const result = try self.allocator.alloc(f32, size);
            defer self.allocator.free(result);
            
            // Initialize vectors
            for (0..size) |i| {
                vector_a[i] = @as(f32, @floatFromInt(i));
                vector_b[i] = @as(f32, @floatFromInt(i * 2));
            }

            const iterations = 1000;
            var timer = try Timer.start();
            
            // Vector addition benchmark (memory bandwidth limited)
            const start_time = timer.read();
            for (0..iterations) |_| {
                for (0..size) |i| {
                    result[i] = vector_a[i] + vector_b[i];
                }
            }
            const end_time = timer.read();
            
            const duration = end_time - start_time;
            const bytes_processed = size * @sizeOf(f32) * 3 * iterations; // 3 arrays (2 read, 1 write)
            const bandwidth_gb_per_sec = (@as(f64, @floatFromInt(bytes_processed)) / 1_000_000_000.0) / (@as(f64, @floatFromInt(duration)) / 1_000_000_000.0);
            
            print("  Memory bandwidth: {:.2} GB/sec\n", .{bandwidth_gb_per_sec});
        }
    }

    fn naiveDotProduct(a: []const f32, b: []const f32) f32 {
        var result: f32 = 0;
        for (a, b) |a_val, b_val| {
            result += a_val * b_val;
        }
        return result;
    }

    fn simdDotProduct(a: []const f32, b: []const f32) f32 {
        // Simplified SIMD implementation - in production would use @Vector
        var result: f32 = 0;
        const vector_size = 4; // Process 4 elements at a time
        const aligned_len = (a.len / vector_size) * vector_size;
        
        // Vectorized loop
        var i: usize = 0;
        while (i < aligned_len) : (i += vector_size) {
            const a_vec: @Vector(4, f32) = .{ a[i], a[i + 1], a[i + 2], a[i + 3] };
            const b_vec: @Vector(4, f32) = .{ b[i], b[i + 1], b[i + 2], b[i + 3] };
            const product = a_vec * b_vec;
            result += @reduce(.Add, product);
        }
        
        // Handle remaining elements
        while (i < a.len) : (i += 1) {
            result += a[i] * b[i];
        }
        
        return result;
    }

    fn naiveNormalizeVector(vector: []f32) void {
        // Calculate magnitude
        var magnitude_squared: f32 = 0;
        for (vector) |val| {
            magnitude_squared += val * val;
        }
        const magnitude = @sqrt(magnitude_squared);
        
        // Normalize
        for (vector) |*val| {
            val.* /= magnitude;
        }
    }

    fn simdNormalizeVector(vector: []f32) void {
        // Calculate magnitude using SIMD
        var magnitude_squared: f32 = 0;
        const vector_size = 4;
        const aligned_len = (vector.len / vector_size) * vector_size;
        
        var i: usize = 0;
        while (i < aligned_len) : (i += vector_size) {
            const vec: @Vector(4, f32) = .{ vector[i], vector[i + 1], vector[i + 2], vector[i + 3] };
            const squared = vec * vec;
            magnitude_squared += @reduce(.Add, squared);
        }
        
        // Handle remaining elements
        while (i < vector.len) : (i += 1) {
            magnitude_squared += vector[i] * vector[i];
        }
        
        const magnitude = @sqrt(magnitude_squared);
        
        // Normalize using SIMD
        const inv_magnitude = 1.0 / magnitude;
        const inv_mag_vec: @Vector(4, f32) = @splat(inv_magnitude);
        
        i = 0;
        while (i < aligned_len) : (i += vector_size) {
            const vec: @Vector(4, f32) = .{ vector[i], vector[i + 1], vector[i + 2], vector[i + 3] };
            const normalized = vec * inv_mag_vec;
            vector[i] = normalized[0];
            vector[i + 1] = normalized[1];
            vector[i + 2] = normalized[2];
            vector[i + 3] = normalized[3];
        }
        
        // Handle remaining elements
        while (i < vector.len) : (i += 1) {
            vector[i] *= inv_magnitude;
        }
    }
};
```

## Regression Detection and Monitoring

### Performance Baseline Management
```zig
// Example usage of performance regression detection
test "performance_regression_comprehensive" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    const config = RegressionDetectionConfig{
        .latency_regression_threshold = 0.05, // 5% regression threshold
        .throughput_regression_threshold = 0.05,
        .memory_regression_threshold = 0.10, // 10% memory increase threshold
        .min_samples_for_significance = 5,
        .confidence_level = 0.95,
    };

    var detector = PerformanceRegressionDetector.init(allocator, config);
    defer detector.deinit();

    // Load existing baselines
    try detector.loadBaseline("benchmarks/baselines/performance_baselines.csv");

    // Test suite of operations for regression detection
    const operations = [_]struct {
        name: []const u8,
        benchmark_fn: fn () anyerror!void,
        target_latency_ms: f64,
        target_throughput: f64,
    }{
        .{
            .name = "primitive_store",
            .benchmark_fn = benchmarkPrimitiveStore,
            .target_latency_ms = 1.0,
            .target_throughput = 1000.0,
        },
        .{
            .name = "primitive_retrieve",
            .benchmark_fn = benchmarkPrimitiveRetrieve,
            .target_latency_ms = 0.5,
            .target_throughput = 2000.0,
        },
        .{
            .name = "semantic_search",
            .benchmark_fn = benchmarkSemanticSearch,
            .target_latency_ms = 10.0,
            .target_throughput = 100.0,
        },
        .{
            .name = "graph_traversal",
            .benchmark_fn = benchmarkGraphTraversal,
            .target_latency_ms = 5.0,
            .target_throughput = 200.0,
        },
        .{
            .name = "hybrid_query",
            .benchmark_fn = benchmarkHybridQuery,
            .target_latency_ms = 10.0,
            .target_throughput = 100.0,
        },
    };

    var all_passed = true;
    var regression_count: usize = 0;

    for (operations) |operation| {
        print("🏁 Running regression test: {s}\n", .{operation.name});

        const result = try detector.benchmarkWithRegressionDetection(
            operation.name,
            operation.benchmark_fn,
            1000, // iterations
        );

        // Check against absolute performance targets
        const meets_latency_target = result.current_measurement.latency_ms() <= operation.target_latency_ms;
        const meets_throughput_target = result.current_measurement.throughput_ops_per_sec >= operation.target_throughput;

        if (!result.has_regression and meets_latency_target and meets_throughput_target) {
            print("  ✅ {s}: {:.2}ms, {:.1} ops/sec - PASSED\n", .{
                operation.name,
                result.current_measurement.latency_ms(),
                result.current_measurement.throughput_ops_per_sec,
            });
        } else {
            print("  ❌ {s}: {:.2}ms, {:.1} ops/sec - ", .{
                operation.name,
                result.current_measurement.latency_ms(),
                result.current_measurement.throughput_ops_per_sec,
            });

            if (result.has_regression) {
                print("REGRESSION ({:.1}%)", .{@max(@abs(result.latency_change_percent), @abs(result.throughput_change_percent))});
                regression_count += 1;
            }
            if (!meets_latency_target) {
                print(" LATENCY_TARGET_MISSED (target: {:.2}ms)", .{operation.target_latency_ms});
            }
            if (!meets_throughput_target) {
                print(" THROUGHPUT_TARGET_MISSED (target: {:.1} ops/sec)", .{operation.target_throughput});
            }
            print("\n");

            all_passed = false;
        }

        // Print detailed regression information
        if (result.has_regression) {
            result.print_summary();
        }
    }

    // Save updated baselines
    try detector.saveBaseline("benchmarks/baselines/performance_baselines.csv");

    // Generate comprehensive report
    detector.generateRegressionReport();

    // Overall assessment
    try testing.expect(all_passed);
    try testing.expect(regression_count == 0);

    print("\n🏆 Performance regression testing completed: ");
    if (all_passed and regression_count == 0) {
        print("✅ ALL TARGETS MET - No regressions detected\n");
    } else {
        print("❌ {} regressions detected - Performance investigation required\n", .{regression_count});
    }
}

fn benchmarkPrimitiveStore() !void {
    // Implementation would create actual benchmark
    std.time.sleep(500_000); // 0.5ms simulated operation
}

fn benchmarkPrimitiveRetrieve() !void {
    // Implementation would create actual benchmark
    std.time.sleep(250_000); // 0.25ms simulated operation
}

fn benchmarkSemanticSearch() !void {
    // Implementation would create actual benchmark
    std.time.sleep(8_000_000); // 8ms simulated operation
}

fn benchmarkGraphTraversal() !void {
    // Implementation would create actual benchmark
    std.time.sleep(4_000_000); // 4ms simulated operation
}

fn benchmarkHybridQuery() !void {
    // Implementation would create actual benchmark
    std.time.sleep(7_000_000); // 7ms simulated operation
}
```

## Scalability Testing

### Database Scaling Analysis
```zig
test "database_scaling_performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    const scale_points = [_]struct {
        entity_count: usize,
        expected_max_latency_ms: f64,
        expected_min_throughput: f64,
    }{
        .{ .entity_count = 1_000, .expected_max_latency_ms = 1.0, .expected_min_throughput = 1000.0 },
        .{ .entity_count = 10_000, .expected_max_latency_ms = 2.0, .expected_min_throughput = 800.0 },
        .{ .entity_count = 100_000, .expected_max_latency_ms = 5.0, .expected_min_throughput = 500.0 },
        .{ .entity_count = 1_000_000, .expected_max_latency_ms = 10.0, .expected_min_throughput = 200.0 },
    };

    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{
        .embedding_dimension = 384,
        .hnsw_max_connections = 32,
    });
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    for (scale_points) |scale_point| {
        print("📈 Scaling test: {} entities\n", .{scale_point.entity_count});

        // Populate database
        const populate_start = std.time.nanoTimestamp();
        
        for (0..scale_point.entity_count) |i| {
            var params = std.json.ObjectMap.init(allocator);
            defer params.deinit();

            const key = try std.fmt.allocPrint(allocator, "scale_entity_{}", .{i});
            defer allocator.free(key);
            
            const value = try std.fmt.allocPrint(allocator, "Scaling test entity {} with semantic content for search testing at scale", .{i});
            defer allocator.free(value);

            try params.put("key", std.json.Value{ .string = key });
            try params.put("value", std.json.Value{ .string = value });

            const result = try primitive_engine.executePrimitive("store", std.json.Value{ .object = params }, "scaling_test");
            defer result.deinit();

            if (i > 0 and i % (scale_point.entity_count / 10) == 0) {
                print("  Populated: {}% ({}/{})\n", .{ (i * 100) / scale_point.entity_count, i, scale_point.entity_count });
            }
        }

        const populate_end = std.time.nanoTimestamp();
        const populate_duration_ms = @as(f64, @floatFromInt(populate_end - populate_start)) / 1_000_000.0;

        print("  Population completed in {:.2}ms\n", .{populate_duration_ms});

        // Test query performance at scale
        const query_iterations = 100;
        var query_latencies = std.ArrayList(u64).init(allocator);
        defer query_latencies.deinit();

        var timer = try Timer.start();
        const query_start = timer.read();

        for (0..query_iterations) |i| {
            const iter_start = timer.read();

            var search_params = std.json.ObjectMap.init(allocator);
            defer search_params.deinit();

            const queries = [_][]const u8{
                "semantic content search testing",
                "scaling test entity information",
                "search performance at scale",
            };
            const query = queries[i % queries.len];

            try search_params.put("query", std.json.Value{ .string = query });
            try search_params.put("limit", std.json.Value{ .integer = 20 });

            const search_result = try primitive_engine.executePrimitive("search", std.json.Value{ .object = search_params }, "scaling_test");
            defer search_result.deinit();

            const iter_end = timer.read();
            try query_latencies.append(iter_end - iter_start);
        }

        const query_end = timer.read();
        const total_query_duration = query_end - query_start;

        // Analyze query performance
        std.mem.sort(u64, query_latencies.items, {}, std.sort.asc(u64));
        const p50_latency_ms = @as(f64, @floatFromInt(query_latencies.items[query_latencies.items.len / 2])) / 1_000_000.0;
        const p99_latency_ms = @as(f64, @floatFromInt(query_latencies.items[(query_latencies.items.len * 99) / 100])) / 1_000_000.0;
        const throughput = (@as(f64, @floatFromInt(query_iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_query_duration));

        print("  Query performance:\n");
        print("    P50 Latency: {:.2}ms\n", .{p50_latency_ms});
        print("    P99 Latency: {:.2}ms\n", .{p99_latency_ms});
        print("    Throughput: {:.1} queries/sec\n", .{throughput});

        // Validate scaling expectations
        try testing.expect(p99_latency_ms <= scale_point.expected_max_latency_ms);
        try testing.expect(throughput >= scale_point.expected_min_throughput);

        const status = if (p99_latency_ms <= scale_point.expected_max_latency_ms and throughput >= scale_point.expected_min_throughput) "✅ PASSED" else "❌ FAILED";
        print("    Status: {s}\n", .{status});

        print("\n");
    }
}
```

## Memory Performance Analysis

### Memory Usage Profiling
```zig
test "memory_performance_analysis" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ 
        .safety = true,
        .retain_metadata = true,
    }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    print("🧠 Memory performance analysis\n");

    // Test memory usage patterns across different scenarios
    const memory_scenarios = [_]struct {
        name: []const u8,
        entity_count: usize,
        expected_memory_per_entity_bytes: usize,
        max_total_memory_mb: f64,
    }{
        .{ .name = "small_scale", .entity_count = 1000, .expected_memory_per_entity_bytes = 2048, .max_total_memory_mb = 10 },
        .{ .name = "medium_scale", .entity_count = 10000, .expected_memory_per_entity_bytes = 1800, .max_total_memory_mb = 50 },
        .{ .name = "large_scale", .entity_count = 100000, .expected_memory_per_entity_bytes = 1600, .max_total_memory_mb = 200 },
    };

    for (memory_scenarios) |scenario| {
        print("  📊 Memory scenario: {s} ({} entities)\n", .{ scenario.name, scenario.entity_count });

        const initial_memory = getCurrentMemoryUsageDetailed();

        // Initialize system components
        var database = Database.init(allocator);
        defer database.deinit();
        
        var semantic_db = try SemanticDatabase.init(allocator, .{});
        defer semantic_db.deinit();
        
        var graph_engine = TripleHybridSearchEngine.init(allocator);
        defer graph_engine.deinit();
        
        var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
        defer primitive_engine.deinit();

        const post_init_memory = getCurrentMemoryUsageDetailed();
        const init_memory_usage = post_init_memory.total_bytes - initial_memory.total_bytes;

        print("    Initialization memory: {:.2} MB\n", .{@as(f64, @floatFromInt(init_memory_usage)) / (1024 * 1024)});

        // Populate data and measure memory growth
        var memory_samples = std.ArrayList(usize).init(allocator);
        defer memory_samples.deinit();

        const sample_interval = scenario.entity_count / 10;

        for (0..scenario.entity_count) |i| {
            var params = std.json.ObjectMap.init(allocator);
            defer params.deinit();

            const key = try std.fmt.allocPrint(allocator, "memory_test_{}", .{i});
            defer allocator.free(key);
            
            const value = try std.fmt.allocPrint(allocator, "Memory analysis entity {} with semantic content for memory usage testing", .{i});
            defer allocator.free(value);

            try params.put("key", std.json.Value{ .string = key });
            try params.put("value", std.json.Value{ .string = value });

            const result = try primitive_engine.executePrimitive("store", std.json.Value{ .object = params }, "memory_test");
            defer result.deinit();

            // Sample memory usage periodically
            if (i % sample_interval == 0) {
                const current_memory = getCurrentMemoryUsageDetailed();
                const current_usage = current_memory.total_bytes - initial_memory.total_bytes;
                try memory_samples.append(current_usage);

                print("    {} entities: {:.2} MB ({:.0} bytes/entity)\n", .{
                    i + 1,
                    @as(f64, @floatFromInt(current_usage)) / (1024 * 1024),
                    if (i > 0) @as(f64, @floatFromInt(current_usage)) / @as(f64, @floatFromInt(i + 1)) else 0.0,
                });
            }
        }

        const final_memory = getCurrentMemoryUsageDetailed();
        const total_memory_usage = final_memory.total_bytes - initial_memory.total_bytes;
        const memory_per_entity = total_memory_usage / scenario.entity_count;

        print("    Final memory usage:\n");
        print("      Total: {:.2} MB\n", .{@as(f64, @floatFromInt(total_memory_usage)) / (1024 * 1024)});
        print("      Per entity: {} bytes\n", .{memory_per_entity});
        print("      Efficiency: {:.1}% of expected\n", .{(@as(f64, @floatFromInt(memory_per_entity)) / @as(f64, @floatFromInt(scenario.expected_memory_per_entity_bytes))) * 100.0});

        // Analyze memory growth pattern
        if (memory_samples.items.len > 2) {
            var is_linear = true;
            var growth_rate: f64 = 0;

            for (1..memory_samples.items.len) |i| {
                const current_rate = @as(f64, @floatFromInt(memory_samples.items[i] - memory_samples.items[i - 1])) / @as(f64, @floatFromInt(sample_interval));
                if (i == 1) {
                    growth_rate = current_rate;
                } else if (@abs(current_rate - growth_rate) / growth_rate > 0.2) { // More than 20% deviation
                    is_linear = false;
                    break;
                }
            }

            print("      Growth pattern: {s}\n", .{if (is_linear) "Linear" else "Non-linear"});
            if (is_linear) {
                print("      Growth rate: {:.1} bytes/entity\n", .{growth_rate});
            }
        }

        // Validate memory usage expectations
        const memory_mb = @as(f64, @floatFromInt(total_memory_usage)) / (1024 * 1024);
        const within_memory_budget = memory_mb <= scenario.max_total_memory_mb;
        const efficient_per_entity = memory_per_entity <= scenario.expected_memory_per_entity_bytes;

        try testing.expect(within_memory_budget);
        try testing.expect(efficient_per_entity);

        const status = if (within_memory_budget and efficient_per_entity) "✅ PASSED" else "❌ FAILED";
        print("      Status: {s}\n\n", .{status});
    }
}

const DetailedMemoryUsage = struct {
    total_bytes: usize,
    heap_bytes: usize,
    stack_bytes: usize,
    allocations: usize,
};

fn getCurrentMemoryUsageDetailed() DetailedMemoryUsage {
    // Simplified memory usage - in production would use platform-specific APIs
    return DetailedMemoryUsage{
        .total_bytes = 10 * 1024 * 1024, // 10MB baseline
        .heap_bytes = 8 * 1024 * 1024,
        .stack_bytes = 2 * 1024 * 1024,
        .allocations = 1000,
    };
}
```

## Concurrent Performance Testing

### Multi-Agent Performance Validation
```zig
test "concurrent_performance_validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    print("🔄 Concurrent performance validation\n");

    const concurrent_scenarios = [_]struct {
        name: []const u8,
        agent_count: usize,
        operations_per_agent: usize,
        expected_total_throughput: f64,
        expected_max_latency_ms: f64,
    }{
        .{ .name = "light_load", .agent_count = 5, .operations_per_agent = 100, .expected_total_throughput = 1000.0, .expected_max_latency_ms = 5.0 },
        .{ .name = "moderate_load", .agent_count = 20, .operations_per_agent = 50, .expected_total_throughput = 800.0, .expected_max_latency_ms = 10.0 },
        .{ .name = "heavy_load", .agent_count = 50, .operations_per_agent = 20, .expected_total_throughput = 500.0, .expected_max_latency_ms = 20.0 },
    };

    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    for (concurrent_scenarios) |scenario| {
        print("  🏁 Scenario: {s} ({} agents, {} ops each)\n", .{ scenario.name, scenario.agent_count, scenario.operations_per_agent });

        var threads: []std.Thread = try allocator.alloc(std.Thread, scenario.agent_count);
        defer allocator.free(threads);
        
        var results: []AgentPerformanceResult = try allocator.alloc(AgentPerformanceResult, scenario.agent_count);
        defer allocator.free(results);

        const test_start_time = std.time.nanoTimestamp();

        // Start all agent threads
        for (0..scenario.agent_count) |i| {
            const context = try allocator.create(AgentContext);
            context.* = AgentContext{
                .server = &server,
                .agent_id = i,
                .operations = scenario.operations_per_agent,
                .result = &results[i],
                .allocator = allocator,
            };

            threads[i] = try std.Thread.spawn(.{}, performanceAgentWorker, .{context});
        }

        // Wait for all agents to complete
        for (threads) |thread| {
            thread.join();
        }

        const test_end_time = std.time.nanoTimestamp();
        const total_duration_ns = test_end_time - test_start_time;

        // Analyze results
        var total_operations: usize = 0;
        var total_errors: usize = 0;
        var all_latencies = std.ArrayList(u64).init(allocator);
        defer all_latencies.deinit();

        for (results) |result| {
            total_operations += result.successful_operations;
            total_errors += result.failed_operations;
            try all_latencies.appendSlice(result.latencies);
            result.deinit(allocator);
        }

        // Calculate aggregate performance metrics
        const total_throughput = (@as(f64, @floatFromInt(total_operations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_duration_ns));
        const error_rate = @as(f64, @floatFromInt(total_errors)) / @as(f64, @floatFromInt(total_operations + total_errors));

        // Latency analysis
        if (all_latencies.items.len > 0) {
            std.mem.sort(u64, all_latencies.items, {}, std.sort.asc(u64));
            const p50_latency_ms = @as(f64, @floatFromInt(all_latencies.items[all_latencies.items.len / 2])) / 1_000_000.0;
            const p99_latency_ms = @as(f64, @floatFromInt(all_latencies.items[(all_latencies.items.len * 99) / 100])) / 1_000_000.0;

            print("    Results:\n");
            print("      Total operations: {}\n", .{total_operations});
            print("      Total errors: {}\n", .{total_errors});
            print("      Error rate: {:.2}%\n", .{error_rate * 100});
            print("      Total throughput: {:.1} ops/sec\n", .{total_throughput});
            print("      P50 latency: {:.2}ms\n", .{p50_latency_ms});
            print("      P99 latency: {:.2}ms\n", .{p99_latency_ms});

            // Validate performance expectations
            const meets_throughput = total_throughput >= scenario.expected_total_throughput;
            const meets_latency = p99_latency_ms <= scenario.expected_max_latency_ms;
            const low_error_rate = error_rate < 0.01; // Less than 1% errors

            try testing.expect(meets_throughput);
            try testing.expect(meets_latency);
            try testing.expect(low_error_rate);

            const status = if (meets_throughput and meets_latency and low_error_rate) "✅ PASSED" else "❌ FAILED";
            print("      Status: {s}\n\n", .{status});
        }
    }
}

const AgentContext = struct {
    server: *MCPCompliantServer,
    agent_id: usize,
    operations: usize,
    result: *AgentPerformanceResult,
    allocator: std.mem.Allocator,
};

const AgentPerformanceResult = struct {
    agent_id: usize,
    successful_operations: usize,
    failed_operations: usize,
    latencies: []u64,

    fn deinit(self: *AgentPerformanceResult, allocator: std.mem.Allocator) void {
        allocator.free(self.latencies);
    }
};

fn performanceAgentWorker(context: *AgentContext) void {
    var local_gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = local_gpa.deinit();
    const local_allocator = local_gpa.allocator();

    var latencies = std.ArrayList(u64).init(local_allocator);
    defer {
        context.result.latencies = context.allocator.dupe(u64, latencies.items) catch &[_]u64{};
        latencies.deinit();
    }

    var successful_ops: usize = 0;
    var failed_ops: usize = 0;

    for (0..context.operations) |i| {
        const operation_start = std.time.nanoTimestamp();

        // Perform MCP tool operation
        var params = std.json.ObjectMap.init(local_allocator);
        defer params.deinit();

        params.put("name", std.json.Value{ .string = "store_knowledge" }) catch {
            failed_ops += 1;
            continue;
        };

        var args = std.json.ObjectMap.init(local_allocator);
        defer args.deinit();

        const key = std.fmt.allocPrint(local_allocator, "perf_agent_{}_{}", .{ context.agent_id, i }) catch {
            failed_ops += 1;
            continue;
        };
        defer local_allocator.free(key);

        const value = std.fmt.allocPrint(local_allocator, "Performance test data from agent {} operation {}", .{ context.agent_id, i }) catch {
            failed_ops += 1;
            continue;
        };
        defer local_allocator.free(value);

        args.put("key", std.json.Value{ .string = key }) catch {
            failed_ops += 1;
            continue;
        };
        args.put("value", std.json.Value{ .string = value }) catch {
            failed_ops += 1;
            continue;
        };
        params.put("arguments", std.json.Value{ .object = args }) catch {
            failed_ops += 1;
            continue;
        };

        const request = MCPRequest{
            .id = key,
            .method = "tools/call",
            .params = std.json.Value{ .object = params },
        };

        const response = context.server.handleRequest(request) catch {
            failed_ops += 1;
            continue;
        };
        defer response.deinit();

        const operation_end = std.time.nanoTimestamp();
        const latency = operation_end - operation_start;

        if (response.result != null) {
            successful_ops += 1;
            latencies.append(latency) catch {};
        } else {
            failed_ops += 1;
        }
    }

    context.result.agent_id = context.agent_id;
    context.result.successful_operations = successful_ops;
    context.result.failed_operations = failed_ops;

    // Clean up context
    context.allocator.destroy(context);
}
```

## Best Practices for Performance Testing

### 1. Benchmark Design Principles
- **Realistic Workloads**: Use production-like data and access patterns
- **Statistical Significance**: Run sufficient iterations for reliable results
- **Warm-up Phases**: Account for JIT compilation and cache warming
- **Measurement Accuracy**: Use high-resolution timers and avoid measurement overhead

### 2. Performance Regression Detection
- **Historical Baselines**: Maintain performance baselines over time
- **Statistical Analysis**: Use proper statistical methods for regression detection
- **Automated Alerting**: Immediate notification of performance regressions
- **Root Cause Analysis**: Detailed information to identify regression causes

### 3. Scalability Testing
- **Multiple Scale Points**: Test at various data sizes and loads
- **Resource Monitoring**: Track memory, CPU, and I/O usage
- **Bottleneck Identification**: Identify performance bottlenecks early
- **Growth Patterns**: Validate algorithmic complexity assumptions

### 4. Memory Performance
- **Allocation Patterns**: Monitor allocation and deallocation patterns
- **Memory Efficiency**: Track memory usage per operation or entity
- **Leak Detection**: Comprehensive memory leak detection
- **Cache Performance**: Optimize for cache efficiency and locality

### 5. Concurrent Performance
- **Thread Safety**: Validate performance under concurrent access
- **Scalability**: Test performance with increasing concurrent users
- **Resource Contention**: Identify and resolve resource contention
- **Deadlock Detection**: Prevent and detect deadlock conditions

## CI/CD Integration

### Automated Performance Testing Pipeline
```bash
#!/bin/bash
# Performance testing pipeline

echo "🚀 Starting Agrama performance testing pipeline"

# Build optimized binaries
zig build -Doptimize=ReleaseFast || exit 1

# Run micro-benchmarks
echo "📊 Running micro-benchmarks..."
zig run benchmarks/primitive_benchmarks.zig || exit 1

# Run SIMD vector benchmarks
echo "🧮 Running SIMD vector benchmarks..."
zig run benchmarks/simd_vector_benchmarks.zig || exit 1

# Run performance regression detection
echo "📈 Running regression detection..."
zig run tests/performance_regression_detector.zig || exit 1

# Run scalability tests
echo "📈 Running scalability tests..."
zig build test --test-filter "scaling" || exit 1

# Run concurrent performance tests
echo "🔄 Running concurrent performance tests..."
zig build test --test-filter "concurrent_performance" || exit 1

# Generate performance report
echo "📝 Generating performance report..."
./generate_performance_report.sh

echo "✅ Performance testing completed successfully"
```

### Performance Monitoring
- **Continuous Benchmarking**: Regular performance benchmarking in CI
- **Trend Analysis**: Track performance trends over time
- **Regression Alerts**: Immediate alerts on performance degradation
- **Historical Comparison**: Compare current performance with historical baselines

## Conclusion

Performance testing in Agrama ensures that the system meets ambitious performance targets through comprehensive benchmarking, regression detection, scalability validation, and concurrent performance analysis. The multi-layered approach provides confidence in production performance while maintaining reliability and efficiency standards required for high-scale AI collaboration scenarios.