//! Agrama Benchmark Framework Demo
//!
//! This demo showcases the benchmarking framework with a simple test
//! to verify everything is working correctly before running full benchmarks.

const std = @import("std");
const benchmark_runner = @import("benchmark_runner.zig");

const BenchmarkRunner = benchmark_runner.BenchmarkRunner;
const BenchmarkConfig = benchmark_runner.BenchmarkConfig;
const BenchmarkResult = benchmark_runner.BenchmarkResult;
const BenchmarkInterface = benchmark_runner.BenchmarkInterface;
const BenchmarkCategory = benchmark_runner.BenchmarkCategory;
const Timer = benchmark_runner.Timer;
const Allocator = benchmark_runner.Allocator;

const print = std.debug.print;

/// Demo benchmark - Simple arithmetic operations
fn demoBenchmark(allocator: Allocator, config: BenchmarkConfig) !BenchmarkResult {
    const iterations = config.iterations;

    print("  🧪 Running demo benchmark with {} iterations...\n", .{iterations});

    var latencies = std.ArrayList(f64).init(allocator);
    defer latencies.deinit();

    var timer = try Timer.start();

    // Warmup
    for (0..config.warmup_iterations) |_| {
        const result = performArithmetic();
        _ = result;
    }

    // Benchmark
    for (0..iterations) |_| {
        timer.reset();
        const result = performArithmetic();
        _ = result;
        const latency_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try latencies.append(latency_ms);
    }

    // Calculate statistics
    const p50 = benchmark_runner.percentile(latencies.items, 50);
    const p99 = benchmark_runner.percentile(latencies.items, 99);
    const mean_latency = benchmark_runner.mean(latencies.items);
    const throughput = 1000.0 / mean_latency;

    return BenchmarkResult{
        .name = "Demo Arithmetic Benchmark",
        .category = .system,
        .p50_latency = p50,
        .p90_latency = benchmark_runner.percentile(latencies.items, 90),
        .p99_latency = p99,
        .p99_9_latency = benchmark_runner.percentile(latencies.items, 99.9),
        .mean_latency = mean_latency,
        .throughput_qps = throughput,
        .operations_per_second = throughput,
        .memory_used_mb = 1.0, // Minimal memory usage
        .cpu_utilization = 5.0,
        .speedup_factor = 1000.0, // Demo speedup
        .accuracy_score = 1.0,
        .dataset_size = iterations,
        .iterations = iterations,
        .duration_seconds = mean_latency * @as(f64, @floatFromInt(iterations)) / 1000.0,
        .passed_targets = p50 < 0.01 and throughput > 100_000, // Very fast operations
    };
}

fn performArithmetic() u64 {
    var result: u64 = 1;
    for (0..1000) |i| {
        result = result * 2 + i;
        result = result % 1_000_000;
    }
    return result;
}

/// Demo memory benchmark
fn demoMemoryBenchmark(allocator: Allocator, config: BenchmarkConfig) !BenchmarkResult {
    const allocation_size = 1024 * 1024; // 1MB allocations
    const iterations = @min(config.iterations, 100); // Limit for memory test

    print("  💾 Running demo memory benchmark with {} iterations...\n", .{iterations});

    var latencies = std.ArrayList(f64).init(allocator);
    defer latencies.deinit();

    var timer = try Timer.start();

    for (0..iterations) |_| {
        timer.reset();

        // Allocate, use, and free memory
        const memory = try allocator.alloc(u8, allocation_size);
        defer allocator.free(memory);

        // Touch memory to ensure allocation
        for (memory, 0..) |*byte, i| {
            byte.* = @as(u8, @intCast(i % 256));
        }

        const latency_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try latencies.append(latency_ms);
    }

    const mean_latency = benchmark_runner.mean(latencies.items);

    return BenchmarkResult{
        .name = "Demo Memory Allocation",
        .category = .system,
        .p50_latency = benchmark_runner.percentile(latencies.items, 50),
        .p90_latency = benchmark_runner.percentile(latencies.items, 90),
        .p99_latency = benchmark_runner.percentile(latencies.items, 99),
        .p99_9_latency = benchmark_runner.percentile(latencies.items, 99.9),
        .mean_latency = mean_latency,
        .throughput_qps = 1000.0 / mean_latency,
        .operations_per_second = 1000.0 / mean_latency,
        .memory_used_mb = @as(f64, @floatFromInt(allocation_size * iterations)) / (1024 * 1024),
        .cpu_utilization = 15.0,
        .speedup_factor = 5.0,
        .accuracy_score = 1.0,
        .dataset_size = iterations,
        .iterations = iterations,
        .duration_seconds = mean_latency * @as(f64, @floatFromInt(iterations)) / 1000.0,
        .passed_targets = mean_latency < 10.0, // Should be under 10ms for 1MB allocation
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n🧪 AGRAMA BENCHMARK FRAMEWORK DEMO\n", .{});
    print("========================================\n", .{});
    print("This demo validates the benchmarking infrastructure\n", .{});
    print("before running the full Agrama performance suite.\n\n", .{});

    const config = BenchmarkConfig{
        .dataset_size = 1000,
        .iterations = 500,
        .warmup_iterations = 50,
        .verbose_output = true,
    };

    var runner = BenchmarkRunner.init(allocator, config);
    defer runner.deinit();

    // Register demo benchmarks
    try runner.registry.register(BenchmarkInterface{
        .name = "Demo Arithmetic Benchmark",
        .category = .system,
        .description = "Simple arithmetic operations to test framework",
        .runFn = demoBenchmark,
    });

    try runner.registry.register(BenchmarkInterface{
        .name = "Demo Memory Allocation",
        .category = .system,
        .description = "Memory allocation and deallocation performance",
        .runFn = demoMemoryBenchmark,
    });

    // Run demo benchmarks
    try runner.runCategory(.system);

    print("\n🎯 DEMO SUMMARY\n", .{});
    print("====================\n", .{});

    var passed: usize = 0;
    for (runner.results.items) |result| {
        if (result.passed_targets) passed += 1;
    }

    if (passed == runner.results.items.len) {
        print("✅ All demo benchmarks passed!\n");
        print("🚀 Benchmark framework is working correctly.\n");
        print("🎯 Ready to run full Agrama performance validation.\n\n");
        print("Next steps:\n");
        print("  zig build bench-quick    # Quick benchmark suite\n");
        print("  zig build bench          # Full benchmark suite\n");
        print("  zig build validate       # Optimized performance validation\n");
    } else {
        print("❌ Some demo benchmarks failed.\n");
        print("🔧 Check benchmark framework implementation.\n");
    }

    print("\n");
}

test "demo_benchmark_components" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test arithmetic function
    const result = performArithmetic();
    try std.testing.expect(result < 1_000_000);

    // Test benchmark runner basic functionality
    const config = BenchmarkConfig{ .dataset_size = 10, .iterations = 10 };
    var runner = BenchmarkRunner.init(allocator, config);
    defer runner.deinit();

    try std.testing.expect(runner.results.items.len == 0);
}
