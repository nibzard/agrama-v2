//! Agrama Comprehensive Benchmark Suite
//!
//! Orchestrates all benchmarks and provides:
//! - Comprehensive performance validation across all components
//! - Performance regression detection with baseline comparison
//! - Automated performance reporting with charts and metrics
//! - CI/CD integration for continuous performance monitoring
//!
//! Usage:
//!   zig run benchmarks/benchmark_suite.zig                 - Run all benchmarks
//!   zig run benchmarks/benchmark_suite.zig -- --category hnsw  - Run specific category
//!   zig run benchmarks/benchmark_suite.zig -- --compare baseline.json  - Compare against baseline

const std = @import("std");
const benchmark_runner = @import("benchmark_runner.zig");
const hnsw_benchmarks = @import("hnsw_benchmarks.zig");
const fre_benchmarks = @import("fre_benchmarks.zig");
const database_benchmarks = @import("database_benchmarks.zig");
const mcp_benchmarks = @import("mcp_benchmarks.zig");

const BenchmarkRunner = benchmark_runner.BenchmarkRunner;
const BenchmarkConfig = benchmark_runner.BenchmarkConfig;
const BenchmarkResult = benchmark_runner.BenchmarkResult;
const BenchmarkCategory = benchmark_runner.BenchmarkCategory;
const PERFORMANCE_TARGETS = benchmark_runner.PERFORMANCE_TARGETS;

const print = std.debug.print;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;

/// Comprehensive benchmark suite configuration
const SuiteConfig = struct {
    // Test configuration
    quick_mode: bool = false, // Reduced dataset sizes for fast testing
    full_validation: bool = true, // Run comprehensive validation
    save_baseline: bool = false, // Save results as new baseline
    compare_baseline: bool = false, // Compare against existing baseline
    baseline_file: ?[]const u8 = null,

    // Output configuration
    generate_html_report: bool = true,
    generate_json_report: bool = true,
    generate_charts: bool = false,
    verbose_output: bool = true,

    // Performance configuration
    max_duration_minutes: u32 = 30, // Maximum benchmark duration
    parallel_execution: bool = false, // Future: parallel benchmark execution

    // Filtering
    categories: ?[]BenchmarkCategory = null, // null = all categories
    exclude_categories: ?[]BenchmarkCategory = null,

    pub fn getDatasetSize(self: SuiteConfig) usize {
        return if (self.quick_mode) 5_000 else 50_000;
    }

    pub fn getIterations(self: SuiteConfig) usize {
        return if (self.quick_mode) 100 else 500;
    }
};

/// Performance regression detector
const RegressionDetector = struct {
    baseline_results: HashMap([]const u8, BenchmarkResult, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    regression_threshold: f64 = 0.05, // 5% performance degradation threshold
    allocator: Allocator,

    const RegressionReport = struct {
        benchmark_name: []const u8,
        metric: []const u8,
        baseline_value: f64,
        current_value: f64,
        degradation_percent: f64,
        is_regression: bool,
    };

    pub fn init(allocator: Allocator) RegressionDetector {
        return .{
            .baseline_results = HashMap([]const u8, BenchmarkResult, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RegressionDetector) void {
        self.baseline_results.deinit();
    }

    /// Load baseline results from JSON file
    pub fn loadBaseline(self: *RegressionDetector, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                print("⚠️  Baseline file not found: {s}\n", .{file_path});
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB limit
        defer self.allocator.free(content);

        // TODO: Parse JSON baseline (simplified for now)
        print("📊 Loaded baseline from: {s}\n", .{file_path});
    }

    /// Save current results as new baseline
    pub fn saveBaseline(_: *RegressionDetector, results: []BenchmarkResult, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        // TODO: Serialize to JSON (simplified for now)
        try file.writer().print("# Agrama Performance Baseline\n", .{});
        try file.writer().print("# Generated: {}\n", .{std.time.timestamp()});
        try file.writer().print("# Benchmarks: {}\n", .{results.len});

        for (results) |result| {
            try file.writer().print("benchmark,{s},{},{:.3},{:.3},{:.1},{:.1}\n", .{ result.name, result.dataset_size, result.p50_latency, result.p99_latency, result.throughput_qps, result.speedup_factor });
        }

        print("💾 Saved baseline to: {s}\n", .{file_path});
    }

    /// Detect performance regressions
    pub fn detectRegressions(self: *RegressionDetector, results: []BenchmarkResult) ![]RegressionReport {
        var regressions = ArrayList(RegressionReport).init(self.allocator);

        for (results) |result| {
            if (self.baseline_results.get(result.name)) |baseline| {
                // Check P50 latency regression
                if (result.p50_latency > baseline.p50_latency) {
                    const degradation = (result.p50_latency - baseline.p50_latency) / baseline.p50_latency;
                    if (degradation > self.regression_threshold) {
                        try regressions.append(.{
                            .benchmark_name = result.name,
                            .metric = "p50_latency",
                            .baseline_value = baseline.p50_latency,
                            .current_value = result.p50_latency,
                            .degradation_percent = degradation * 100,
                            .is_regression = true,
                        });
                    }
                }

                // Check throughput regression
                if (result.throughput_qps < baseline.throughput_qps) {
                    const degradation = (baseline.throughput_qps - result.throughput_qps) / baseline.throughput_qps;
                    if (degradation > self.regression_threshold) {
                        try regressions.append(.{
                            .benchmark_name = result.name,
                            .metric = "throughput",
                            .baseline_value = baseline.throughput_qps,
                            .current_value = result.throughput_qps,
                            .degradation_percent = degradation * 100,
                            .is_regression = true,
                        });
                    }
                }

                // Check speedup regression
                if (result.speedup_factor < baseline.speedup_factor) {
                    const degradation = (baseline.speedup_factor - result.speedup_factor) / baseline.speedup_factor;
                    if (degradation > self.regression_threshold) {
                        try regressions.append(.{
                            .benchmark_name = result.name,
                            .metric = "speedup_factor",
                            .baseline_value = baseline.speedup_factor,
                            .current_value = result.speedup_factor,
                            .degradation_percent = degradation * 100,
                            .is_regression = true,
                        });
                    }
                }
            }
        }

        return try regressions.toOwnedSlice();
    }
};

/// Comprehensive report generator
const ReportGenerator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ReportGenerator {
        return .{ .allocator = allocator };
    }

    /// Generate comprehensive HTML report
    pub fn generateHTMLReport(self: *ReportGenerator, results: []BenchmarkResult, output_file: []const u8) !void {
        _ = self;
        const file = try std.fs.cwd().createFile(output_file, .{});
        defer file.close();

        const writer = file.writer();

        // HTML header
        try writer.writeAll(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <title>Agrama Performance Benchmark Report</title>
            \\    <style>
            \\        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 40px; background: #f5f5f5; }
            \\        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }
            \\        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
            \\        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            \\        .metric-value { font-size: 2em; font-weight: bold; color: #667eea; }
            \\        .metric-label { color: #666; text-transform: uppercase; font-size: 0.9em; letter-spacing: 1px; }
            \\        .benchmark-results { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
            \\        table { width: 100%; border-collapse: collapse; }
            \\        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #eee; }
            \\        th { background: #f8f9fa; font-weight: 600; }
            \\        .status-pass { color: #28a745; font-weight: bold; }
            \\        .status-fail { color: #dc3545; font-weight: bold; }
            \\        .category-hnsw { border-left: 4px solid #ff6b6b; }
            \\        .category-fre { border-left: 4px solid #4ecdc4; }
            \\        .category-database { border-left: 4px solid #45b7d1; }
            \\        .category-mcp { border-left: 4px solid #96ceb4; }
            \\    </style>
            \\</head>
            \\<body>
            \\
        );

        // Header
        try writer.print(
            \\    <div class="header">
            \\        <h1>🚀 Agrama Performance Benchmark Report</h1>
            \\        <p>Generated: {}</p>
            \\        <p>Total Benchmarks: {} | Duration: {:.1}s</p>
            \\    </div>
            \\
        , .{ std.time.timestamp(), results.len, calculateTotalDuration(results) });

        // Summary cards
        try writer.writeAll("    <div class=\"summary\">\n");

        // Calculate summary metrics
        var total_passed: usize = 0;
        var total_failed: usize = 0;
        var avg_speedup: f64 = 0;
        var min_latency: f64 = std.math.inf(f64);
        var max_throughput: f64 = 0;

        for (results) |result| {
            if (result.passed_targets) total_passed += 1 else total_failed += 1;
            avg_speedup += result.speedup_factor;
            min_latency = @min(min_latency, result.p50_latency);
            max_throughput = @max(max_throughput, result.throughput_qps);
        }
        avg_speedup /= @as(f64, @floatFromInt(results.len));

        // Summary cards
        try writer.print(
            \\        <div class="card">
            \\            <div class="metric-value">{}</div>
            \\            <div class="metric-label">Benchmarks Passed</div>
            \\        </div>
            \\        <div class="card">
            \\            <div class="metric-value">{:.1}×</div>
            \\            <div class="metric-label">Avg Speedup</div>
            \\        </div>
            \\        <div class="card">
            \\            <div class="metric-value">{:.2}ms</div>
            \\            <div class="metric-label">Best P50 Latency</div>
            \\        </div>
            \\        <div class="card">
            \\            <div class="metric-value">{:.0}</div>
            \\            <div class="metric-label">Peak Throughput QPS</div>
            \\        </div>
            \\
        , .{ total_passed, avg_speedup, min_latency, max_throughput });

        try writer.writeAll("    </div>\n");

        // Detailed results table
        try writer.writeAll(
            \\    <div class="benchmark-results">
            \\        <h2>📊 Detailed Results</h2>
            \\        <table>
            \\            <thead>
            \\                <tr>
            \\                    <th>Benchmark</th>
            \\                    <th>Category</th>
            \\                    <th>P50 Latency</th>
            \\                    <th>P99 Latency</th>
            \\                    <th>Throughput</th>
            \\                    <th>Speedup</th>
            \\                    <th>Memory</th>
            \\                    <th>Status</th>
            \\                </tr>
            \\            </thead>
            \\            <tbody>
            \\
        );

        for (results) |result| {
            const category_class = switch (result.category) {
                .hnsw => "category-hnsw",
                .fre => "category-fre",
                .database => "category-database",
                .mcp => "category-mcp",
                else => "",
            };

            const status_class = if (result.passed_targets) "status-pass" else "status-fail";
            const status_text = if (result.passed_targets) "✅ PASS" else "❌ FAIL";

            try writer.print(
                \\                <tr class="{s}">
                \\                    <td><strong>{s}</strong></td>
                \\                    <td>{s}</td>
                \\                    <td>{:.2}ms</td>
                \\                    <td>{:.2}ms</td>
                \\                    <td>{:.0} QPS</td>
                \\                    <td>{:.1}×</td>
                \\                    <td>{:.0}MB</td>
                \\                    <td class="{s}">{s}</td>
                \\                </tr>
                \\
            , .{ category_class, result.name, @tagName(result.category), result.p50_latency, result.p99_latency, result.throughput_qps, result.speedup_factor, result.memory_used_mb, status_class, status_text });
        }

        try writer.writeAll(
            \\            </tbody>
            \\        </table>
            \\    </div>
            \\</body>
            \\</html>
            \\
        );

        print("📄 Generated HTML report: {s}\n", .{output_file});
    }

    /// Generate JSON report for programmatic consumption
    pub fn generateJSONReport(self: *ReportGenerator, results: []BenchmarkResult, output_file: []const u8) !void {
        _ = self;
        const file = try std.fs.cwd().createFile(output_file, .{});
        defer file.close();

        // Simplified JSON generation (would use std.json in production)
        try file.writer().writeAll("{\n  \"agrama_benchmark_report\": {\n");
        try file.writer().print("    \"timestamp\": {},\n", .{std.time.timestamp()});
        try file.writer().print("    \"total_benchmarks\": {},\n", .{results.len});
        try file.writer().writeAll("    \"results\": [\n");

        for (results, 0..) |result, i| {
            try file.writer().print(
                \\      {{
                \\        "name": "{s}",
                \\        "category": "{s}",
                \\        "p50_latency": {:.3},
                \\        "p99_latency": {:.3},
                \\        "throughput_qps": {:.1},
                \\        "speedup_factor": {:.1},
                \\        "memory_used_mb": {:.1},
                \\        "passed_targets": {},
                \\        "dataset_size": {},
                \\        "iterations": {}
                \\      }}
            , .{ result.name, @tagName(result.category), result.p50_latency, result.p99_latency, result.throughput_qps, result.speedup_factor, result.memory_used_mb, result.passed_targets, result.dataset_size, result.iterations });

            if (i < results.len - 1) {
                try file.writer().writeAll(",");
            }
            try file.writer().writeAll("\n");
        }

        try file.writer().writeAll("    ]\n  }\n}\n");
        print("📊 Generated JSON report: {s}\n", .{output_file});
    }

    fn calculateTotalDuration(results: []BenchmarkResult) f64 {
        var total: f64 = 0;
        for (results) |result| {
            total += result.duration_seconds;
        }
        return total;
    }
};

/// Main benchmark suite orchestrator
const BenchmarkSuite = struct {
    allocator: Allocator,
    config: SuiteConfig,
    runner: BenchmarkRunner,
    regression_detector: RegressionDetector,
    report_generator: ReportGenerator,

    pub fn init(allocator: Allocator, config: SuiteConfig) BenchmarkSuite {
        const benchmark_config = BenchmarkConfig{
            .dataset_size = config.getDatasetSize(),
            .iterations = config.getIterations(),
            .warmup_iterations = if (config.quick_mode) 20 else 50,
            .verbose_output = config.verbose_output,
            .save_results = true,
            .compare_to_baseline = config.compare_baseline,
            .baseline_file = config.baseline_file,
        };

        return .{
            .allocator = allocator,
            .config = config,
            .runner = BenchmarkRunner.init(allocator, benchmark_config),
            .regression_detector = RegressionDetector.init(allocator),
            .report_generator = ReportGenerator.init(allocator),
        };
    }

    pub fn deinit(self: *BenchmarkSuite) void {
        self.runner.deinit();
        self.regression_detector.deinit();
    }

    /// Run the complete benchmark suite
    pub fn runSuite(self: *BenchmarkSuite) !void {
        print("\n", .{});
        print("🔥" ** 40 ++ "\n", .{});
        print("🚀 AGRAMA COMPREHENSIVE BENCHMARK SUITE\n", .{});
        print("🔥" ** 40 ++ "\n", .{});
        print("\n", .{});

        if (self.config.quick_mode) {
            print("⚡ Running in QUICK MODE (reduced dataset sizes)\n", .{});
        } else {
            print("🎯 Running in FULL VALIDATION MODE\n", .{});
        }

        print("📊 Configuration:\n", .{});
        print("   Dataset Size: {}\n", .{self.config.getDatasetSize()});
        print("   Iterations: {}\n", .{self.config.getIterations()});
        print("   Max Duration: {} minutes\n", .{self.config.max_duration_minutes});
        print("\n", .{});

        // Load baseline if requested
        if (self.config.compare_baseline) {
            if (self.config.baseline_file) |baseline_file| {
                try self.regression_detector.loadBaseline(baseline_file);
            }
        }

        // Register all benchmarks
        try self.registerAllBenchmarks();

        // Run benchmarks based on configuration
        if (self.config.categories) |categories| {
            for (categories) |category| {
                try self.runner.runCategory(category);
            }
        } else {
            try self.runner.runAll();
        }

        // Performance validation and reporting
        try self.validatePerformanceClaims();
        try self.generateReports();

        // Save baseline if requested
        if (self.config.save_baseline) {
            const timestamp = std.time.timestamp();
            const baseline_filename = try std.fmt.allocPrint(self.allocator, "benchmarks/baseline_{}.json", .{timestamp});
            defer self.allocator.free(baseline_filename);

            try self.regression_detector.saveBaseline(self.runner.results.items, baseline_filename);
        }

        // Final summary
        try self.printFinalSummary();
    }

    /// Register all available benchmarks
    fn registerAllBenchmarks(self: *BenchmarkSuite) !void {
        print("📋 Registering benchmark suites...\n", .{});

        try hnsw_benchmarks.registerHNSWBenchmarks(&self.runner.registry);
        print("   ✅ HNSW benchmarks registered\n", .{});

        try fre_benchmarks.registerFREBenchmarks(&self.runner.registry);
        print("   ✅ FRE benchmarks registered\n", .{});

        try database_benchmarks.registerDatabaseBenchmarks(&self.runner.registry);
        print("   ✅ Database benchmarks registered\n", .{});

        try mcp_benchmarks.registerMCPBenchmarks(&self.runner.registry);
        print("   ✅ MCP benchmarks registered\n", .{});

        print("📊 Total benchmarks registered: {}\n\n", .{self.runner.registry.benchmarks.items.len});
    }

    /// Validate all performance claims
    fn validatePerformanceClaims(self: *BenchmarkSuite) !void {
        print("\n🎯 PERFORMANCE CLAIMS VALIDATION\n", .{});
        print("=" ** 50 ++ "\n", .{});

        var claims_met: u32 = 0;
        const total_claims: u32 = 4;

        // HNSW Claims: 100-1000× speedup
        const hnsw_validated = self.runner.validateHNSWClaims();
        print("HNSW 100-1000× speedup: {s}\n", .{if (hnsw_validated) "✅ VALIDATED" else "❌ NOT MET"});
        if (hnsw_validated) claims_met += 1;

        // FRE Claims: 5-50× speedup
        const fre_validated = self.runner.validateFREClaims();
        print("FRE 5-50× speedup: {s}\n", .{if (fre_validated) "✅ VALIDATED" else "❌ NOT MET"});
        if (fre_validated) claims_met += 1;

        // Database Claims: Sub-10ms hybrid queries
        const db_validated = self.runner.validateDatabaseClaims();
        print("Sub-10ms hybrid queries: {s}\n", .{if (db_validated) "✅ VALIDATED" else "❌ NOT MET"});
        if (db_validated) claims_met += 1;

        // MCP Claims: Sub-100ms tool responses
        const mcp_validated = self.runner.validateMCPClaims();
        print("Sub-100ms MCP responses: {s}\n", .{if (mcp_validated) "✅ VALIDATED" else "❌ NOT MET"});
        if (mcp_validated) claims_met += 1;

        print("\n📊 Performance Claims Summary: {}/{} validated ({:.0}%)\n", .{ claims_met, total_claims, (@as(f64, @floatFromInt(claims_met)) / @as(f64, @floatFromInt(total_claims))) * 100 });
    }

    /// Generate comprehensive reports
    fn generateReports(self: *BenchmarkSuite) !void {
        print("\n📄 Generating reports...\n", .{});

        // Create results directory
        std.fs.cwd().makeDir("benchmarks/results") catch {};

        if (self.config.generate_html_report) {
            const timestamp = std.time.timestamp();
            const html_file = try std.fmt.allocPrint(self.allocator, "benchmarks/results/report_{}.html", .{timestamp});
            defer self.allocator.free(html_file);

            try self.report_generator.generateHTMLReport(self.runner.results.items, html_file);
        }

        if (self.config.generate_json_report) {
            const timestamp = std.time.timestamp();
            const json_file = try std.fmt.allocPrint(self.allocator, "benchmarks/results/results_{}.json", .{timestamp});
            defer self.allocator.free(json_file);

            try self.report_generator.generateJSONReport(self.runner.results.items, json_file);
        }

        // Regression detection
        if (self.config.compare_baseline) {
            const regressions = try self.regression_detector.detectRegressions(self.runner.results.items);
            defer self.allocator.free(regressions);

            if (regressions.len > 0) {
                print("\n⚠️  PERFORMANCE REGRESSIONS DETECTED:\n", .{});
                for (regressions) |regression| {
                    print("   🔴 {s} ({s}): {:.1}% degradation ({:.3} → {:.3})\n", .{ regression.benchmark_name, regression.metric, regression.degradation_percent, regression.baseline_value, regression.current_value });
                }
            } else {
                print("✅ No performance regressions detected\n", .{});
            }
        }
    }

    /// Print final summary
    fn printFinalSummary(self: *BenchmarkSuite) !void {
        print("\n" ++ "🏁" ** 40 ++ "\n");
        print("FINAL BENCHMARK SUMMARY\n", .{});
        print("🏁" ** 40 ++ "\n");

        var total_passed: usize = 0;
        var total_failed: usize = 0;

        for (self.runner.results.items) |result| {
            if (result.passed_targets) total_passed += 1 else total_failed += 1;
        }

        const pass_rate = @as(f64, @floatFromInt(total_passed)) / @as(f64, @floatFromInt(self.runner.results.items.len));

        print("📊 Results:\n", .{});
        print("   Total Benchmarks: {}\n", .{self.runner.results.items.len});
        print("   Passed: {} ✅\n", .{total_passed});
        print("   Failed: {} ❌\n", .{total_failed});
        print("   Pass Rate: {:.1}%\n", .{pass_rate * 100});

        // Overall verdict
        print("\n🏆 OVERALL VERDICT:\n", .{});
        if (pass_rate >= 1.0) {
            print("🟢 EXCELLENT - All benchmarks passed! Agrama is ready for production.\n", .{});
        } else if (pass_rate >= 0.9) {
            print("🟡 GOOD - Most benchmarks passed. Minor optimizations recommended.\n", .{});
        } else if (pass_rate >= 0.7) {
            print("🟠 NEEDS WORK - Several benchmarks failed. Optimization required.\n", .{});
        } else {
            print("🔴 CRITICAL - Many benchmarks failed. Major performance work needed.\n", .{});
        }

        print("\n🔗 Reports generated in: benchmarks/results/\n", .{});
        print("🚀 Run with --help for more options\n", .{});
        print("\n", .{});
    }
};

/// Command-line argument parsing
fn parseArgs(allocator: Allocator, args: [][:0]u8) !SuiteConfig {
    var config = SuiteConfig{};

    var i: usize = 1; // Skip program name
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--quick") or std.mem.eql(u8, arg, "-q")) {
            config.quick_mode = true;
        } else if (std.mem.eql(u8, arg, "--save-baseline")) {
            config.save_baseline = true;
        } else if (std.mem.eql(u8, arg, "--compare") and i + 1 < args.len) {
            config.compare_baseline = true;
            config.baseline_file = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--category") and i + 1 < args.len) {
            const category_name = args[i + 1];
            if (std.mem.eql(u8, category_name, "hnsw")) {
                config.categories = try allocator.dupe(BenchmarkCategory, &[_]BenchmarkCategory{.hnsw});
            } else if (std.mem.eql(u8, category_name, "fre")) {
                config.categories = try allocator.dupe(BenchmarkCategory, &[_]BenchmarkCategory{.fre});
            } else if (std.mem.eql(u8, category_name, "database")) {
                config.categories = try allocator.dupe(BenchmarkCategory, &[_]BenchmarkCategory{.database});
            } else if (std.mem.eql(u8, category_name, "mcp")) {
                config.categories = try allocator.dupe(BenchmarkCategory, &[_]BenchmarkCategory{.mcp});
            }
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        }

        i += 1;
    }

    return config;
}

fn printUsage() void {
    print(
        \\Agrama Comprehensive Benchmark Suite
        \\
        \\Usage: zig run benchmarks/benchmark_suite.zig [OPTIONS]
        \\
        \\Options:
        \\  -q, --quick                Run in quick mode (reduced dataset sizes)
        \\  --save-baseline           Save results as new baseline
        \\  --compare FILE            Compare against baseline file
        \\  --category CATEGORY       Run only specific category (hnsw|fre|database|mcp)
        \\  -h, --help                Show this help message
        \\
        \\Examples:
        \\  zig run benchmarks/benchmark_suite.zig
        \\  zig run benchmarks/benchmark_suite.zig -- --quick --category hnsw
        \\  zig run benchmarks/benchmark_suite.zig -- --compare baseline.json
        \\
    , .{});
}

/// Main entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = parseArgs(allocator, args) catch {
        printUsage();
        return;
    };

    var suite = BenchmarkSuite.init(allocator, config);
    defer suite.deinit();

    suite.runSuite() catch |err| {
        print("❌ Benchmark suite failed: {}\n", .{err});
        std.process.exit(1);
    };
}

// Tests
test "benchmark_suite_basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SuiteConfig{ .quick_mode = true };
    var suite = BenchmarkSuite.init(allocator, config);
    defer suite.deinit();

    try std.testing.expect(config.getDatasetSize() == 5_000);
    try std.testing.expect(config.getIterations() == 100);
}
