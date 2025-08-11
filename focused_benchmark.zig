const std = @import("std");
const print = std.debug.print;

const benchmark_runner = @import("benchmarks/benchmark_runner.zig");
const fre_benchmarks = @import("benchmarks/fre_benchmarks.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🎯 FOCUSED BENCHMARK: FRE OPTIMIZATION VALIDATION\n", .{});
    print("==================================================\n", .{});

    const config = benchmark_runner.BenchmarkConfig{
        .dataset_size = 1000, // Smaller dataset
        .iterations = 50, // Fewer iterations
        .warmup_iterations = 5,
        .verbose_output = true,
        .max_duration_seconds = 30.0, // 30 second timeout
    };

    var runner = benchmark_runner.BenchmarkRunner.init(allocator, config);
    defer runner.deinit();

    // Register only FRE benchmarks
    try fre_benchmarks.registerFREBenchmarks(&runner.registry);

    print("\n🚀 Running FRE benchmarks with optimizations...\n", .{});
    try runner.runCategory(.fre);

    print("\n📋 PERFORMANCE SUMMARY:\n", .{});
    for (runner.results.items) |result| {
        print("  {s}: {d:.3}ms P50, {d:.1}× speedup - {s}\n", .{ result.name, result.p50_latency, result.speedup_factor, if (result.passed_targets) "✅ PASSED" else "❌ FAILED" });
    }

    // Check if critical FRE target is met
    var fre_target_met = false;
    for (runner.results.items) |result| {
        if (std.mem.indexOf(u8, result.name, "FRE vs Dijkstra") != null) {
            fre_target_met = result.p50_latency <= 5.0; // Target <5ms
            break;
        }
    }

    print("\n🏆 CRITICAL FRE TARGET: {s}\n", .{if (fre_target_met) "✅ MET - Production Ready!" else "❌ NOT MET - Needs Work"});
}
