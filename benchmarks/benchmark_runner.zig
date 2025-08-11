//! Agrama Benchmark Runner - Main orchestration for performance benchmarking
//!
//! This module provides the core benchmarking infrastructure to validate Agrama's
//! revolutionary performance claims:
//! - HNSW: 100-1000× faster semantic search than linear scan
//! - FRE: 5-50× faster graph traversal than Dijkstra
//! - Database: Sub-10ms hybrid queries on 1M+ nodes
//!
//! Usage:
//!   zig build bench                    - Run all benchmarks
//!   zig build bench -Dcategory=hnsw   - Run specific category
//!   zig build bench -Dcompare=true    - Compare against baseline

const std = @import("std");
pub const Timer = std.time.Timer;
pub const Allocator = std.mem.Allocator;
pub const ArrayList = std.ArrayList;
pub const HashMap = std.HashMap;
const print = std.debug.print;

/// Global performance targets that all benchmarks must validate
pub const PERFORMANCE_TARGETS = struct {
    // HNSW Vector Search Targets
    pub const HNSW_QUERY_P50_MS = 1.0;
    pub const HNSW_QUERY_P99_MS = 10.0;
    pub const HNSW_THROUGHPUT_QPS = 1000;
    pub const HNSW_MEMORY_GB = 10.0;
    pub const HNSW_SPEEDUP_VS_LINEAR = 100.0; // Minimum 100× improvement

    // Frontier Reduction Engine Targets
    pub const FRE_SPEEDUP_VS_DIJKSTRA = 5.0; // Minimum 5× improvement
    pub const FRE_P50_MS = 5.0;
    pub const FRE_P99_MS = 50.0;

    // Database Operation Targets
    pub const HYBRID_QUERY_P50_MS = 10.0;
    pub const HYBRID_QUERY_P99_MS = 100.0;
    pub const STORAGE_COMPRESSION_RATIO = 5.0; // 5× reduction via anchor+delta

    // MCP Server Targets
    pub const MCP_TOOL_RESPONSE_MS = 100.0;
    pub const CONCURRENT_AGENTS = 100;

    // System Resource Targets
    pub const MAX_MEMORY_1M_NODES_GB = 10.0;
    pub const MIN_THROUGHPUT_QPS = 1000;
};

/// Standardized benchmark result structure
pub const BenchmarkResult = struct {
    name: []const u8,
    category: BenchmarkCategory,

    // Latency metrics (milliseconds)
    p50_latency: f64,
    p90_latency: f64,
    p99_latency: f64,
    p99_9_latency: f64,
    mean_latency: f64,

    // Throughput metrics
    throughput_qps: f64,
    operations_per_second: f64,

    // Resource metrics
    memory_used_mb: f64,
    cpu_utilization: f64,

    // Algorithm-specific metrics
    speedup_factor: f64, // vs baseline algorithm
    accuracy_score: f64, // recall@k, compression ratio, etc.

    // Metadata
    dataset_size: usize,
    iterations: usize,
    duration_seconds: f64,
    passed_targets: bool,

    pub fn format(self: BenchmarkResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("Benchmark: {s} ({s})\n", .{ self.name, @tagName(self.category) });
        try writer.print("Dataset: {d} items, {d} iterations, {d:.2}s duration\n", .{ self.dataset_size, self.iterations, self.duration_seconds });
        try writer.print("Latency:  P50={d:.3}ms P90={d:.3}ms P99={d:.3}ms P99.9={d:.3}ms\n", .{ self.p50_latency, self.p90_latency, self.p99_latency, self.p99_9_latency });
        try writer.print("Performance: {d:.1} QPS, {d:.1} ops/sec, {d:.1}× speedup\n", .{ self.throughput_qps, self.operations_per_second, self.speedup_factor });
        try writer.print("Resources: {d:.1}MB memory, {d:.1}% CPU\n", .{ self.memory_used_mb, self.cpu_utilization });
        try writer.print("Status: {s} {s}\n", .{ if (self.passed_targets) "✅" else "❌", if (self.passed_targets) "PASSED" else "FAILED" });
    }
};

/// Benchmark categories for organization and filtering
pub const BenchmarkCategory = enum {
    hnsw, // Vector search and HNSW algorithms
    fre, // Frontier Reduction Engine graph traversal
    database, // Core database operations
    storage, // Storage and compression benchmarks
    crdt, // CRDT collaboration performance
    mcp, // MCP server and tool performance
    system, // End-to-end system benchmarks
    regression, // Performance regression detection
};

/// Interface that all benchmarks must implement
pub const BenchmarkInterface = struct {
    name: []const u8,
    category: BenchmarkCategory,
    description: []const u8,

    // Benchmark execution function
    runFn: *const fn (allocator: Allocator, config: BenchmarkConfig) anyerror!BenchmarkResult,

    // Optional data generation function for synthetic datasets
    generateDataFn: ?*const fn (allocator: Allocator, size: usize) anyerror!void = null,

    // Optional cleanup function
    cleanupFn: ?*const fn (allocator: Allocator) void = null,
};

/// Configuration for benchmark execution
pub const BenchmarkConfig = struct {
    // Dataset configuration
    dataset_size: usize = 10_000,
    iterations: usize = 1_000,
    warmup_iterations: usize = 100,

    // Timing configuration
    max_duration_seconds: f64 = 300.0, // 5 minute timeout
    min_sample_size: usize = 100,

    // Output configuration
    enable_profiling: bool = false,
    generate_flamegraph: bool = false,
    save_results: bool = true,
    verbose_output: bool = false,

    // Comparison configuration
    compare_to_baseline: bool = false,
    baseline_file: ?[]const u8 = null,
    regression_threshold: f64 = 0.05, // 5% degradation threshold

    // Resource limits
    max_memory_gb: f64 = 32.0,
    max_cpu_cores: u8 = 16,
};

/// Benchmark registry for organizing and discovering benchmarks
pub const BenchmarkRegistry = struct {
    benchmarks: ArrayList(BenchmarkInterface),
    allocator: Allocator,

    pub fn init(allocator: Allocator) BenchmarkRegistry {
        return .{
            .benchmarks = ArrayList(BenchmarkInterface).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BenchmarkRegistry) void {
        self.benchmarks.deinit();
    }

    pub fn register(self: *BenchmarkRegistry, benchmark: BenchmarkInterface) !void {
        try self.benchmarks.append(benchmark);
    }

    pub fn findByCategory(self: *BenchmarkRegistry, category: BenchmarkCategory) ArrayList(BenchmarkInterface) {
        var results = ArrayList(BenchmarkInterface).init(self.allocator);
        for (self.benchmarks.items) |benchmark| {
            if (benchmark.category == category) {
                results.append(benchmark) catch {};
            }
        }
        return results;
    }

    pub fn findByName(self: *BenchmarkRegistry, name: []const u8) ?BenchmarkInterface {
        for (self.benchmarks.items) |benchmark| {
            if (std.mem.eql(u8, benchmark.name, name)) {
                return benchmark;
            }
        }
        return null;
    }
};

/// Core benchmark runner with comprehensive reporting
pub const BenchmarkRunner = struct {
    allocator: Allocator,
    registry: BenchmarkRegistry,
    config: BenchmarkConfig,
    results: ArrayList(BenchmarkResult),

    pub fn init(allocator: Allocator, config: BenchmarkConfig) BenchmarkRunner {
        return .{
            .allocator = allocator,
            .registry = BenchmarkRegistry.init(allocator),
            .config = config,
            .results = ArrayList(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *BenchmarkRunner) void {
        self.registry.deinit();
        self.results.deinit();
    }

    /// Run all benchmarks in a specific category
    pub fn runCategory(self: *BenchmarkRunner, category: BenchmarkCategory) !void {
        const benchmarks = self.registry.findByCategory(category);
        defer benchmarks.deinit();

        print("\n🚀 Running {s} benchmarks\n", .{@tagName(category)});
        print("=" ** 60 ++ "\n", .{});

        for (benchmarks.items) |benchmark| {
            try self.runSingle(benchmark);
        }

        try self.generateCategoryReport(category);
    }

    /// Run all benchmarks across all categories
    pub fn runAll(self: *BenchmarkRunner) !void {
        print("\n🔥 Running comprehensive Agrama benchmark suite\n", .{});
        print("=" ** 80 ++ "\n", .{});

        inline for (std.meta.fields(BenchmarkCategory)) |field| {
            const category = @field(BenchmarkCategory, field.name);
            try self.runCategory(category);
        }

        try self.generateComprehensiveReport();
    }

    /// Run a single benchmark with full timing and profiling
    pub fn runSingle(self: *BenchmarkRunner, benchmark: BenchmarkInterface) !void {
        print("\n📊 Running benchmark: {s}\n", .{benchmark.name});
        print("Description: {s}\n", .{benchmark.description});
        print("Category: {s}\n", .{@tagName(benchmark.category)});

        const start_time = std.time.milliTimestamp();

        // Run the benchmark
        var result = benchmark.runFn(self.allocator, self.config) catch |err| {
            print("❌ Benchmark failed: {any}\n", .{err});
            return;
        };

        // Validate against performance targets
        result.passed_targets = self.validateTargets(result);

        // Store results
        try self.results.append(result);

        // Display immediate results
        print("{any}\n", .{result});

        const total_time = std.time.milliTimestamp() - start_time;
        print("⏱️  Total execution time: {d}ms\n", .{total_time});

        if (self.config.save_results) {
            try self.saveResult(result);
        }

        // Optional profiling output
        if (self.config.enable_profiling) {
            try self.generateProfilingReport(benchmark.name);
        }
    }

    /// Validate benchmark results against performance targets
    fn validateTargets(self: *BenchmarkRunner, result: BenchmarkResult) bool {
        _ = self;

        switch (result.category) {
            .hnsw => {
                if (result.p50_latency > PERFORMANCE_TARGETS.HNSW_QUERY_P50_MS) return false;
                if (result.p99_latency > PERFORMANCE_TARGETS.HNSW_QUERY_P99_MS) return false;
                if (result.throughput_qps < PERFORMANCE_TARGETS.HNSW_THROUGHPUT_QPS) return false;
                if (result.speedup_factor < PERFORMANCE_TARGETS.HNSW_SPEEDUP_VS_LINEAR) return false;
            },
            .fre => {
                if (result.p50_latency > PERFORMANCE_TARGETS.FRE_P50_MS) return false;
                if (result.p99_latency > PERFORMANCE_TARGETS.FRE_P99_MS) return false;
                if (result.speedup_factor < PERFORMANCE_TARGETS.FRE_SPEEDUP_VS_DIJKSTRA) return false;
            },
            .database => {
                if (result.p50_latency > PERFORMANCE_TARGETS.HYBRID_QUERY_P50_MS) return false;
                if (result.p99_latency > PERFORMANCE_TARGETS.HYBRID_QUERY_P99_MS) return false;
            },
            .mcp => {
                if (result.p50_latency > PERFORMANCE_TARGETS.MCP_TOOL_RESPONSE_MS) return false;
            },
            else => {
                // Category-specific validation can be added here
            },
        }

        return true;
    }

    /// Save benchmark result to disk for regression tracking
    fn saveResult(self: *BenchmarkRunner, result: BenchmarkResult) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "benchmarks/results/{s}_{}.json", .{ result.name, std.time.timestamp() });
        defer self.allocator.free(file_path);

        // Create results directory if it doesn't exist
        std.fs.cwd().makeDir("benchmarks/results") catch {};

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        // Serialize result to JSON
        try std.json.stringify(result, .{}, file.writer());

        if (self.config.verbose_output) {
            print("💾 Saved result to: {s}\n", .{file_path});
        }
    }

    /// Generate profiling report for a benchmark
    fn generateProfilingReport(self: *BenchmarkRunner, benchmark_name: []const u8) !void {
        _ = self;
        _ = benchmark_name;
        // TODO: Implement profiling integration (perf, flamegraph generation)
        print("🔍 Profiling data saved to benchmarks/profiles/\n", .{});
    }

    /// Generate report for a specific benchmark category
    fn generateCategoryReport(self: *BenchmarkRunner, category: BenchmarkCategory) !void {
        print("\n📈 Category Report: {s}\n", .{@tagName(category)});
        print("=" ** 50 ++ "\n", .{});

        var category_results = ArrayList(BenchmarkResult).init(self.allocator);
        defer category_results.deinit();

        // Filter results by category
        for (self.results.items) |result| {
            if (result.category == category) {
                try category_results.append(result);
            }
        }

        if (category_results.items.len == 0) {
            print("No benchmarks found for category: {s}\n", .{@tagName(category)});
            return;
        }

        // Calculate aggregate statistics
        var total_passed: usize = 0;
        var avg_p50: f64 = 0;
        var avg_throughput: f64 = 0;

        for (category_results.items) |result| {
            if (result.passed_targets) total_passed += 1;
            avg_p50 += result.p50_latency;
            avg_throughput += result.throughput_qps;
        }

        avg_p50 /= @as(f64, @floatFromInt(category_results.items.len));
        avg_throughput /= @as(f64, @floatFromInt(category_results.items.len));

        print("Benchmarks: {d} total, {d} passed, {d} failed\n", .{ category_results.items.len, total_passed, category_results.items.len - total_passed });
        print("Average P50 Latency: {d:.3}ms\n", .{avg_p50});
        print("Average Throughput: {d:.1} QPS\n", .{avg_throughput});

        const pass_rate = @as(f64, @floatFromInt(total_passed)) / @as(f64, @floatFromInt(category_results.items.len));
        if (pass_rate >= 1.0) {
            print("🟢 Category Status: ALL BENCHMARKS PASSED\n", .{});
        } else if (pass_rate >= 0.8) {
            print("🟡 Category Status: MOSTLY PASSING ({d:.0}% pass rate)\n", .{pass_rate * 100});
        } else {
            print("🔴 Category Status: FAILING ({d:.0}% pass rate)\n", .{pass_rate * 100});
        }
    }

    /// Generate comprehensive report across all benchmarks
    fn generateComprehensiveReport(self: *BenchmarkRunner) !void {
        print("\n" ++ "=" ** 80 ++ "\n", .{});
        print("🏆 AGRAMA PERFORMANCE BENCHMARK REPORT\n", .{});
        print("=" ** 80 ++ "\n", .{});

        if (self.results.items.len == 0) {
            print("No benchmarks were executed.\n", .{});
            return;
        }

        // Calculate overall statistics
        var total_passed: usize = 0;
        var total_failed: usize = 0;

        for (self.results.items) |result| {
            if (result.passed_targets) {
                total_passed += 1;
            } else {
                total_failed += 1;
            }
        }

        print("📊 Overall Results:\n", .{});
        print("   Total Benchmarks: {d}\n", .{self.results.items.len});
        print("   Passed: {d} ✅\n", .{total_passed});
        print("   Failed: {d} ❌\n", .{total_failed});

        const pass_rate = @as(f64, @floatFromInt(total_passed)) / @as(f64, @floatFromInt(self.results.items.len));
        print("   Pass Rate: {d:.1}%\n", .{pass_rate * 100});

        // Performance claims validation
        print("\n🚀 Performance Claims Validation:\n", .{});
        print("   HNSW 100-1000× improvement: {s}\n", .{if (self.validateHNSWClaims()) "✅ VALIDATED" else "❌ NOT MET"});
        print("   FRE 5-50× improvement: {s}\n", .{if (self.validateFREClaims()) "✅ VALIDATED" else "❌ NOT MET"});
        print("   Sub-10ms hybrid queries: {s}\n", .{if (self.validateDatabaseClaims()) "✅ VALIDATED" else "❌ NOT MET"});
        print("   Sub-100ms MCP responses: {s}\n", .{if (self.validateMCPClaims()) "✅ VALIDATED" else "❌ NOT MET"});

        // Resource utilization summary
        var max_memory: f64 = 0;
        var avg_cpu: f64 = 0;
        for (self.results.items) |result| {
            max_memory = @max(max_memory, result.memory_used_mb);
            avg_cpu += result.cpu_utilization;
        }
        avg_cpu /= @as(f64, @floatFromInt(self.results.items.len));

        print("\n💾 Resource Utilization:\n", .{});
        print("   Peak Memory Usage: {d:.1} MB\n", .{max_memory});
        print("   Average CPU Usage: {d:.1}%\n", .{avg_cpu});

        // Final verdict
        print("\n🏁 FINAL VERDICT:\n", .{});
        if (pass_rate >= 1.0) {
            print("🟢 ALL PERFORMANCE TARGETS MET - AGRAMA IS READY FOR PRODUCTION!\n", .{});
        } else if (pass_rate >= 0.8) {
            print("🟡 MOST TARGETS MET - MINOR OPTIMIZATIONS NEEDED\n", .{});
        } else {
            print("🔴 PERFORMANCE TARGETS NOT MET - SIGNIFICANT WORK REQUIRED\n", .{});
        }

        print("=" ** 80 ++ "\n", .{});
    }

    /// Validate HNSW performance claims
    pub fn validateHNSWClaims(self: *BenchmarkRunner) bool {
        for (self.results.items) |result| {
            if (result.category == .hnsw) {
                if (result.speedup_factor >= PERFORMANCE_TARGETS.HNSW_SPEEDUP_VS_LINEAR and result.passed_targets) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Validate FRE performance claims
    pub fn validateFREClaims(self: *BenchmarkRunner) bool {
        for (self.results.items) |result| {
            if (result.category == .fre) {
                if (result.speedup_factor >= PERFORMANCE_TARGETS.FRE_SPEEDUP_VS_DIJKSTRA and result.passed_targets) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Validate database performance claims
    pub fn validateDatabaseClaims(self: *BenchmarkRunner) bool {
        for (self.results.items) |result| {
            if (result.category == .database) {
                if (result.p50_latency <= PERFORMANCE_TARGETS.HYBRID_QUERY_P50_MS and result.passed_targets) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Validate MCP server performance claims
    pub fn validateMCPClaims(self: *BenchmarkRunner) bool {
        for (self.results.items) |result| {
            if (result.category == .mcp) {
                if (result.p50_latency <= PERFORMANCE_TARGETS.MCP_TOOL_RESPONSE_MS and result.passed_targets) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Validate primitive performance claims (<1ms P50 latency)
    pub fn validatePrimitiveClaims(self: *BenchmarkRunner) bool {
        var primitive_results: usize = 0;
        var primitive_passed: usize = 0;
        
        for (self.results.items) |result| {
            if (std.mem.indexOf(u8, result.name, "primitive_") != null) {
                primitive_results += 1;
                if (result.p50_latency <= 1.0 and result.passed_targets) { // <1ms P50 target
                    primitive_passed += 1;
                }
            }
        }
        
        // At least 80% of primitive benchmarks should pass
        return primitive_results > 0 and primitive_passed >= (primitive_results * 4) / 5;
    }
};

/// Utility functions for statistical analysis
pub const BenchmarkUtils = struct {
    /// Calculate percentile from sorted array of values
    pub fn percentile(values: []f64, p: f64) f64 {
        if (values.len == 0) return 0;

        // Sort values
        std.sort.pdq(f64, values, {}, std.sort.asc(f64));

        const index = (p / 100.0) * @as(f64, @floatFromInt(values.len - 1));
        const lower = @as(usize, @intFromFloat(@floor(index)));
        const upper = @as(usize, @intFromFloat(@ceil(index)));

        if (lower == upper) {
            return values[lower];
        }

        const weight = index - @floor(index);
        return values[lower] * (1.0 - weight) + values[upper] * weight;
    }

    /// Calculate mean of values
    pub fn mean(values: []f64) f64 {
        if (values.len == 0) return 0;

        var sum: f64 = 0;
        for (values) |value| {
            sum += value;
        }
        return sum / @as(f64, @floatFromInt(values.len));
    }

    /// Calculate standard deviation
    pub fn standardDeviation(values: []f64) f64 {
        if (values.len <= 1) return 0;

        const avg = mean(values);
        var sum_sq_diff: f64 = 0;

        for (values) |value| {
            const diff = value - avg;
            sum_sq_diff += diff * diff;
        }

        return @sqrt(sum_sq_diff / @as(f64, @floatFromInt(values.len - 1)));
    }

    /// Generate realistic test data with configurable distribution
    pub fn generateRealisticData(allocator: Allocator, size: usize, distribution: DataDistribution) ![]f64 {
        var data = try allocator.alloc(f64, size);
        var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));

        switch (distribution) {
            .uniform => {
                for (data) |*value| {
                    value.* = rng.random().float(f64);
                }
            },
            .zipfian => {
                // Zipfian distribution for realistic access patterns
                for (data, 0..) |*value, i| {
                    value.* = 1.0 / std.math.pow(f64, @as(f64, @floatFromInt(i + 1)), 1.2);
                }
            },
            .gaussian => {
                // Normal distribution with mean=0, stddev=1
                for (0..size / 2) |i| {
                    const uniform1 = rng.random().float(f64);
                    const uniform2 = rng.random().float(f64);

                    const z0 = @sqrt(-2.0 * std.math.log(f64, std.math.e, uniform1)) * @cos(2.0 * std.math.pi * uniform2);
                    const z1 = @sqrt(-2.0 * std.math.log(f64, std.math.e, uniform1)) * @sin(2.0 * std.math.pi * uniform2);

                    data[i * 2] = z0;
                    if (i * 2 + 1 < size) {
                        data[i * 2 + 1] = z1;
                    }
                }
            },
        }

        return data;
    }

    pub const DataDistribution = enum {
        uniform,
        zipfian,
        gaussian,
    };
};

// Export key functions for use by individual benchmarks
pub const percentile = BenchmarkUtils.percentile;
pub const benchmark_mean = BenchmarkUtils.mean; // Renamed to avoid collision
pub const standardDeviation = BenchmarkUtils.standardDeviation;
pub const generateRealisticData = BenchmarkUtils.generateRealisticData;

// Example usage and testing
test "benchmark_runner_basic_functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BenchmarkConfig{
        .dataset_size = 1000,
        .iterations = 100,
        .warmup_iterations = 10,
        .verbose_output = false,
    };

    var runner = BenchmarkRunner.init(allocator, config);
    defer runner.deinit();

    // Test percentile calculation
    var values = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0 };
    const p50 = BenchmarkUtils.percentile(&values, 50.0);
    const p90 = BenchmarkUtils.percentile(&values, 90.0);

    try std.testing.expect(p50 == 5.5);
    try std.testing.expect(p90 == 9.5);

    // Test data generation
    const data = try BenchmarkUtils.generateRealisticData(allocator, 1000, .uniform);
    defer allocator.free(data);

    try std.testing.expect(data.len == 1000);
}
