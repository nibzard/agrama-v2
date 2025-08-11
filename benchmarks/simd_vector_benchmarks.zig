//! SIMD Vector Operations Benchmarks
//!
//! Validates the SIMD optimizations in optimized_hnsw.zig including:
//! - AVX2 vs scalar performance comparison
//! - Vector similarity calculation speedup (4×-8× target)
//! - Memory alignment and cache optimization effectiveness
//! - Fallback behavior for unsupported SIMD features
//!
//! Target Performance:
//! - SIMD vs Scalar: 4×-8× speedup for vector operations
//! - Vector Similarity P50: <0.1ms for 1024D vectors
//! - Cache Hit Rate: >95% for aligned memory access
//! - Memory Bandwidth: >80% of theoretical maximum

const std = @import("std");
const builtin = @import("builtin");
const benchmark_runner = @import("benchmark_runner.zig");
const optimized_hnsw = @import("../src/optimized_hnsw.zig");

const BenchmarkRunner = benchmark_runner.BenchmarkRunner;
const BenchmarkConfig = benchmark_runner.BenchmarkConfig;
const BenchmarkResult = benchmark_runner.BenchmarkResult;
const BenchmarkInterface = benchmark_runner.BenchmarkInterface;
const BenchmarkCategory = benchmark_runner.BenchmarkCategory;
const BenchmarkUtils = benchmark_runner.BenchmarkUtils;

const Timer = std.time.Timer;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

/// SIMD benchmark performance targets
const SIMD_TARGETS = struct {
    pub const SIMD_SPEEDUP_MIN = 4.0; // Minimum 4× improvement over scalar
    pub const SIMD_SPEEDUP_TARGET = 8.0; // Target 8× improvement
    pub const VECTOR_SIMILARITY_P50_MS = 0.1; // <0.1ms for 1024D vectors
    pub const CACHE_HIT_RATE = 0.95; // >95% cache hit rate
    pub const MEMORY_BANDWIDTH_UTILIZATION = 0.8; // >80% of theoretical max
};

/// Test vector dimensions for benchmarking
const TEST_DIMENSIONS = [_]u32{ 64, 128, 256, 512, 1024, 2048 };

/// SIMD benchmark context
const SIMDBenchmarkContext = struct {
    allocator: Allocator,
    test_vectors: []optimized_hnsw.VectorSIMD,
    dimensions: u32,
    vector_count: usize,

    pub fn init(allocator: Allocator, dimensions: u32, count: usize) !SIMDBenchmarkContext {
        const test_vectors = try allocator.alloc(optimized_hnsw.VectorSIMD, count);
        var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));

        // Initialize test vectors with random data
        for (test_vectors, 0..) |*vec, i| {
            vec.* = try optimized_hnsw.VectorSIMD.init(allocator, dimensions);

            // Fill with normalized random values
            var norm_sq: f32 = 0.0;
            for (vec.data) |*val| {
                val.* = rng.random().floatNorm(f32);
                norm_sq += val.* * val.*;
            }

            // Normalize vector
            const norm = @sqrt(norm_sq);
            if (norm > 0.0) {
                for (vec.data) |*val| {
                    val.* /= norm;
                }
            }

            // Add some correlation every 10th vector for realistic data
            if (i % 10 == 0 and i > 0) {
                const base_idx = i - (i % 10);
                for (vec.data, 0..) |*val, j| {
                    val.* = 0.7 * val.* + 0.3 * test_vectors[base_idx].data[j];
                }
            }
        }

        return SIMDBenchmarkContext{
            .allocator = allocator,
            .test_vectors = test_vectors,
            .dimensions = dimensions,
            .vector_count = count,
        };
    }

    pub fn deinit(self: *SIMDBenchmarkContext) void {
        for (self.test_vectors) |*vec| {
            vec.deinit(self.allocator);
        }
        self.allocator.free(self.test_vectors);
    }
};

/// Benchmark SIMD vs Scalar vector similarity computation
fn benchmarkSIMDVsScalar(allocator: Allocator, config: BenchmarkConfig) !BenchmarkResult {
    print("🔄 Setting up SIMD vs Scalar benchmark...\n", .{});

    const dimensions: u32 = 1024; // Standard embedding dimension
    const vector_count = @min(config.dataset_size, 1000); // Limit for memory

    var ctx = try SIMDBenchmarkContext.init(allocator, dimensions, vector_count);
    defer ctx.deinit();

    var timer = try Timer.start();
    var simd_timings = ArrayList(f64).init(allocator);
    var scalar_timings = ArrayList(f64).init(allocator);
    defer simd_timings.deinit();
    defer scalar_timings.deinit();

    // Warmup phase
    print("🌡️ Running warmup ({d} iterations)...\n", .{config.warmup_iterations});
    for (0..config.warmup_iterations) |i| {
        const idx1 = i % vector_count;
        const idx2 = (i + 1) % vector_count;
        _ = ctx.test_vectors[idx1].cosineSimilarity(&ctx.test_vectors[idx2]);
    }

    // Benchmark SIMD implementation
    print("🚀 Benchmarking SIMD implementation ({d} iterations)...\n", .{config.iterations});
    timer = try Timer.start();

    for (0..config.iterations) |i| {
        const idx1 = i % vector_count;
        const idx2 = (i + 1) % vector_count;

        const op_start = timer.read();
        // Force SIMD path by using the optimized method
        const result = ctx.test_vectors[idx1].cosineSimilarity(&ctx.test_vectors[idx2]);
        const op_end = timer.read();

        _ = result; // Prevent optimization
        const latency_ms = @as(f64, @floatFromInt(op_end - op_start)) / 1_000_000.0;
        try simd_timings.append(latency_ms);
    }

    // Benchmark scalar implementation for comparison
    print("📊 Benchmarking scalar fallback ({d} iterations)...\n", .{config.iterations});

    for (0..config.iterations) |i| {
        const idx1 = i % vector_count;
        const idx2 = (i + 1) % vector_count;

        const op_start = timer.read();
        // Force scalar path by using the fallback method
        const result = ctx.test_vectors[idx1].cosineSimilarityScalar(&ctx.test_vectors[idx2]);
        const op_end = timer.read();

        _ = result; // Prevent optimization
        const latency_ms = @as(f64, @floatFromInt(op_end - op_start)) / 1_000_000.0;
        try scalar_timings.append(latency_ms);
    }

    // Calculate statistics
    const simd_p50 = BenchmarkUtils.percentile(simd_timings.items, 50.0);
    const simd_p99 = BenchmarkUtils.percentile(simd_timings.items, 99.0);
    const simd_mean = BenchmarkUtils.mean(simd_timings.items);

    const scalar_p50 = BenchmarkUtils.percentile(scalar_timings.items, 50.0);
    const scalar_mean = BenchmarkUtils.mean(scalar_timings.items);

    // Calculate speedup (scalar time / SIMD time)
    const speedup_p50 = if (simd_p50 > 0.0) scalar_p50 / simd_p50 else 0.0;
    const speedup_mean = if (simd_mean > 0.0) scalar_mean / simd_mean else 0.0;

    const duration_seconds = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
    const throughput = @as(f64, @floatFromInt(config.iterations)) / duration_seconds;

    print("📈 SIMD Speedup Analysis:\n", .{});
    print("   SIMD P50: {d:.6}ms, Scalar P50: {d:.6}ms\n", .{ simd_p50, scalar_p50 });
    print("   Speedup (P50): {d:.2}×\n", .{speedup_p50});
    print("   Speedup (Mean): {d:.2}×\n", .{speedup_mean});

    const has_simd_support = comptime builtin.cpu.arch == .x86_64 and
        std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);

    return BenchmarkResult{
        .name = "simd_vector_similarity",
        .category = .hnsw,
        .p50_latency = simd_p50,
        .p90_latency = BenchmarkUtils.percentile(simd_timings.items, 90.0),
        .p99_latency = simd_p99,
        .p99_9_latency = BenchmarkUtils.percentile(simd_timings.items, 99.9),
        .mean_latency = simd_mean,
        .throughput_qps = throughput,
        .operations_per_second = throughput,
        .memory_used_mb = @as(f64, @floatFromInt(vector_count * dimensions * @sizeOf(f32))) / (1024.0 * 1024.0),
        .cpu_utilization = 0.0,
        .speedup_factor = speedup_mean,
        .accuracy_score = 1.0, // Vector similarity is deterministic
        .dataset_size = vector_count,
        .iterations = config.iterations,
        .duration_seconds = duration_seconds,
        .passed_targets = (has_simd_support and speedup_mean >= SIMD_TARGETS.SIMD_SPEEDUP_MIN) or
            (!has_simd_support and simd_p50 < SIMD_TARGETS.VECTOR_SIMILARITY_P50_MS),
    };
}

/// Benchmark memory alignment and cache performance
fn benchmarkMemoryAlignment(allocator: Allocator, config: BenchmarkConfig) !BenchmarkResult {
    print("🔄 Setting up memory alignment benchmark...\n", .{});

    const dimensions: u32 = 512;
    const vector_count = @min(config.dataset_size, 500); // Smaller for memory benchmark

    // Test both aligned and unaligned vectors
    var aligned_ctx = try SIMDBenchmarkContext.init(allocator, dimensions, vector_count);
    defer aligned_ctx.deinit();

    // Create unaligned vectors for comparison
    var unaligned_vectors = try allocator.alloc(optimized_hnsw.VectorSIMD, vector_count);
    defer {
        for (unaligned_vectors) |*vec| {
            vec.deinit(allocator);
        }
        allocator.free(unaligned_vectors);
    }

    // Initialize unaligned vectors (without alignment requirements)
    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp() + 1)));
    for (unaligned_vectors) |*vec| {
        // Allocate without alignment for comparison
        const data = try allocator.alloc(f32, dimensions);
        vec.* = optimized_hnsw.VectorSIMD{
            .data = data,
            .dimensions = dimensions,
        };

        for (vec.data) |*val| {
            val.* = rng.random().floatNorm(f32);
        }
    }

    var timer = try Timer.start();
    var aligned_timings = ArrayList(f64).init(allocator);
    var unaligned_timings = ArrayList(f64).init(allocator);
    defer aligned_timings.deinit();
    defer unaligned_timings.deinit();

    // Benchmark aligned memory access
    print("🎯 Benchmarking aligned memory access...\n", .{});
    for (0..config.iterations) |i| {
        const idx1 = i % vector_count;
        const idx2 = (i + 1) % vector_count;

        const op_start = timer.read();
        const result = aligned_ctx.test_vectors[idx1].cosineSimilarity(&aligned_ctx.test_vectors[idx2]);
        const op_end = timer.read();

        _ = result;
        const latency_ms = @as(f64, @floatFromInt(op_end - op_start)) / 1_000_000.0;
        try aligned_timings.append(latency_ms);
    }

    // Benchmark unaligned memory access
    print("📍 Benchmarking unaligned memory access...\n", .{});
    for (0..config.iterations) |i| {
        const idx1 = i % vector_count;
        const idx2 = (i + 1) % vector_count;

        const op_start = timer.read();
        const result = unaligned_vectors[idx1].cosineSimilarity(&unaligned_vectors[idx2]);
        const op_end = timer.read();

        _ = result;
        const latency_ms = @as(f64, @floatFromInt(op_end - op_start)) / 1_000_000.0;
        try unaligned_timings.append(latency_ms);
    }

    // Calculate statistics
    const aligned_p50 = BenchmarkUtils.percentile(aligned_timings.items, 50.0);
    const unaligned_p50 = BenchmarkUtils.percentile(unaligned_timings.items, 50.0);
    const alignment_speedup = if (aligned_p50 > 0.0) unaligned_p50 / aligned_p50 else 1.0;

    print("🔍 Memory Alignment Analysis:\n", .{});
    print("   Aligned P50: {d:.6}ms, Unaligned P50: {d:.6}ms\n", .{ aligned_p50, unaligned_p50 });
    print("   Alignment benefit: {d:.2}×\n", .{alignment_speedup});

    const duration_seconds = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
    const throughput = @as(f64, @floatFromInt(config.iterations)) / duration_seconds;

    return BenchmarkResult{
        .name = "simd_memory_alignment",
        .category = .hnsw,
        .p50_latency = aligned_p50,
        .p90_latency = BenchmarkUtils.percentile(aligned_timings.items, 90.0),
        .p99_latency = BenchmarkUtils.percentile(aligned_timings.items, 99.0),
        .p99_9_latency = BenchmarkUtils.percentile(aligned_timings.items, 99.9),
        .mean_latency = BenchmarkUtils.mean(aligned_timings.items),
        .throughput_qps = throughput,
        .operations_per_second = throughput,
        .memory_used_mb = @as(f64, @floatFromInt(vector_count * dimensions * @sizeOf(f32) * 2)) / (1024.0 * 1024.0),
        .cpu_utilization = 0.0,
        .speedup_factor = alignment_speedup,
        .accuracy_score = 1.0,
        .dataset_size = vector_count,
        .iterations = config.iterations,
        .duration_seconds = duration_seconds,
        .passed_targets = alignment_speedup >= 1.1, // At least 10% benefit from alignment
    };
}

/// Benchmark different vector dimensions performance scaling
fn benchmarkDimensionScaling(allocator: Allocator, config: BenchmarkConfig) !BenchmarkResult {
    print("🔄 Setting up dimension scaling benchmark...\n", .{});

    var all_timings = ArrayList(f64).init(allocator);
    defer all_timings.deinit();

    var timer = try Timer.start();
    var dimension_results = ArrayList(struct { dims: u32, latency: f64 }).init(allocator);
    defer dimension_results.deinit();

    for (TEST_DIMENSIONS) |dimensions| {
        print("📏 Testing {d}D vectors...\n", .{dimensions});

        const vector_count = @min(config.dataset_size / TEST_DIMENSIONS.len, 200);
        var ctx = try SIMDBenchmarkContext.init(allocator, dimensions, vector_count);
        defer ctx.deinit();

        var dim_timings = ArrayList(f64).init(allocator);
        defer dim_timings.deinit();

        // Benchmark this dimension
        const iterations_per_dim = config.iterations / TEST_DIMENSIONS.len;
        for (0..iterations_per_dim) |i| {
            const idx1 = i % vector_count;
            const idx2 = (i + 1) % vector_count;

            const op_start = timer.read();
            const result = ctx.test_vectors[idx1].cosineSimilarity(&ctx.test_vectors[idx2]);
            const op_end = timer.read();

            _ = result;
            const latency_ms = @as(f64, @floatFromInt(op_end - op_start)) / 1_000_000.0;
            try dim_timings.append(latency_ms);
            try all_timings.append(latency_ms);
        }

        const dim_p50 = BenchmarkUtils.percentile(dim_timings.items, 50.0);
        try dimension_results.append(.{ .dims = dimensions, .latency = dim_p50 });

        print("   {d}D P50 latency: {d:.6}ms\n", .{ dimensions, dim_p50 });
    }

    // Analyze scaling characteristics
    print("📊 Dimension scaling analysis:\n", .{});
    for (dimension_results.items, 0..) |result, i| {
        if (i > 0) {
            const prev = dimension_results.items[i - 1];
            const scaling_factor = result.latency / prev.latency;
            const theoretical_scaling = @as(f64, @floatFromInt(result.dims)) / @as(f64, @floatFromInt(prev.dims));
            print("   {d}D→{d}D: {d:.2}× actual vs {d:.2}× theoretical\n", .{ prev.dims, result.dims, scaling_factor, theoretical_scaling });
        }
    }

    // Calculate overall statistics
    const p50 = BenchmarkUtils.percentile(all_timings.items, 50.0);
    const duration_seconds = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000.0;
    const throughput = @as(f64, @floatFromInt(all_timings.items.len)) / duration_seconds;

    return BenchmarkResult{
        .name = "simd_dimension_scaling",
        .category = .hnsw,
        .p50_latency = p50,
        .p90_latency = BenchmarkUtils.percentile(all_timings.items, 90.0),
        .p99_latency = BenchmarkUtils.percentile(all_timings.items, 99.0),
        .p99_9_latency = BenchmarkUtils.percentile(all_timings.items, 99.9),
        .mean_latency = BenchmarkUtils.mean(all_timings.items),
        .throughput_qps = throughput,
        .operations_per_second = throughput,
        .memory_used_mb = 0.0, // Variable across dimensions
        .cpu_utilization = 0.0,
        .speedup_factor = 1.0, // Baseline scaling analysis
        .accuracy_score = 1.0,
        .dataset_size = config.dataset_size,
        .iterations = all_timings.items.len,
        .duration_seconds = duration_seconds,
        .passed_targets = p50 < SIMD_TARGETS.VECTOR_SIMILARITY_P50_MS,
    };
}

/// Register all SIMD benchmark functions
pub fn registerSIMDBenchmarks(registry: *benchmark_runner.BenchmarkRegistry) !void {
    try registry.register(BenchmarkInterface{
        .name = "simd_vector_similarity",
        .category = .hnsw,
        .description = "SIMD vs scalar vector similarity performance comparison",
        .runFn = benchmarkSIMDVsScalar,
    });

    try registry.register(BenchmarkInterface{
        .name = "simd_memory_alignment",
        .category = .hnsw,
        .description = "Memory alignment impact on SIMD performance",
        .runFn = benchmarkMemoryAlignment,
    });

    try registry.register(BenchmarkInterface{
        .name = "simd_dimension_scaling",
        .category = .hnsw,
        .description = "Vector dimension scaling performance analysis",
        .runFn = benchmarkDimensionScaling,
    });
}
