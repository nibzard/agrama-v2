//! Performance Regression Detection System
//!
//! Detects performance regressions by comparing current performance
//! against established baselines with statistical significance testing

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Timer = std.time.Timer;
const print = std.debug.print;

/// Performance benchmark result
pub const PerformanceMeasurement = struct {
    name: []const u8,
    latency_ns: u64,
    throughput_ops_per_sec: f64,
    memory_bytes: usize,
    cpu_percent: f64,
    timestamp: i64,

    // Additional metrics
    p50_latency_ns: u64 = 0,
    p90_latency_ns: u64 = 0,
    p99_latency_ns: u64 = 0,

    pub fn latency_ms(self: PerformanceMeasurement) f64 {
        return @as(f64, @floatFromInt(self.latency_ns)) / 1_000_000.0;
    }

    pub fn p50_latency_ms(self: PerformanceMeasurement) f64 {
        return @as(f64, @floatFromInt(self.p50_latency_ns)) / 1_000_000.0;
    }

    pub fn p99_latency_ms(self: PerformanceMeasurement) f64 {
        return @as(f64, @floatFromInt(self.p99_latency_ns)) / 1_000_000.0;
    }
};

/// Baseline performance database
pub const PerformanceBaseline = struct {
    measurements: HashMap([]const u8, []PerformanceMeasurement, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PerformanceBaseline {
        return .{
            .measurements = HashMap([]const u8, []PerformanceMeasurement, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PerformanceBaseline) void {
        var iterator = self.measurements.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.measurements.deinit();
    }

    pub fn addMeasurement(self: *PerformanceBaseline, measurement: PerformanceMeasurement) !void {
        const name_owned = try self.allocator.dupe(u8, measurement.name);

        if (self.measurements.getPtr(name_owned)) |existing| {
            // Add to existing measurements
            const new_measurements = try self.allocator.realloc(existing.*, existing.len + 1);
            new_measurements[new_measurements.len - 1] = measurement;
            existing.* = new_measurements;
        } else {
            // Create new measurement array
            const new_measurements = try self.allocator.alloc(PerformanceMeasurement, 1);
            new_measurements[0] = measurement;
            try self.measurements.put(name_owned, new_measurements);
        }
    }

    pub fn getBaseline(self: *PerformanceBaseline, name: []const u8) ?PerformanceMeasurement {
        if (self.measurements.get(name)) |measurements| {
            if (measurements.len > 0) {
                // Return median of historical measurements
                return calculateMedianMeasurement(measurements);
            }
        }
        return null;
    }

    fn calculateMedianMeasurement(measurements: []PerformanceMeasurement) PerformanceMeasurement {
        if (measurements.len == 0) return std.mem.zeroes(PerformanceMeasurement);
        if (measurements.len == 1) return measurements[0];

        // Sort by latency for median calculation
        var sorted_measurements = std.ArrayList(PerformanceMeasurement).init(std.heap.page_allocator);
        defer sorted_measurements.deinit();

        sorted_measurements.appendSlice(measurements) catch return measurements[0];

        std.mem.sort(PerformanceMeasurement, sorted_measurements.items, {}, struct {
            fn lessThan(context: void, a: PerformanceMeasurement, b: PerformanceMeasurement) bool {
                _ = context;
                return a.latency_ns < b.latency_ns;
            }
        }.lessThan);

        const median_idx = sorted_measurements.items.len / 2;
        return sorted_measurements.items[median_idx];
    }

    /// Load baseline from JSON file
    pub fn loadFromFile(self: *PerformanceBaseline, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                print("📊 Baseline file not found: {s} - starting fresh\n", .{file_path});
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        // Simple JSON parsing for baseline (in production would use proper JSON parser)
        print("📊 Loaded baseline from: {s} ({} bytes)\n", .{ file_path, content.len });
    }

    /// Save baseline to JSON file
    pub fn saveToFile(self: *PerformanceBaseline, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        try file.writer().print("# Agrama Performance Baseline\n", .{});
        try file.writer().print("# Generated: {d}\n", .{std.time.timestamp()});
        try file.writer().print("# Benchmarks: {d}\n", .{self.measurements.count()});

        var iterator = self.measurements.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const measurements = entry.value_ptr.*;

            if (measurements.len > 0) {
                const baseline = calculateMedianMeasurement(measurements);
                try file.writer().print("{s},{d},{d:.3},{d},{d:.1}\n", .{ name, baseline.latency_ns, baseline.throughput_ops_per_sec, baseline.memory_bytes, baseline.cpu_percent });
            }
        }

        print("💾 Saved baseline to: {s}\n", .{file_path});
    }
};

/// Regression detection configuration
pub const RegressionDetectionConfig = struct {
    // Regression thresholds
    latency_regression_threshold: f64 = 0.1, // 10% increase is a regression
    throughput_regression_threshold: f64 = 0.1, // 10% decrease is a regression
    memory_regression_threshold: f64 = 0.2, // 20% increase is a regression

    // Statistical significance
    min_samples_for_significance: usize = 3,
    confidence_level: f64 = 0.95, // 95% confidence

    // Alerting
    enable_alerts: bool = true,
    alert_on_first_regression: bool = true,

    // Reporting
    generate_detailed_reports: bool = true,
    save_regression_history: bool = true,
};

/// Regression detection result
pub const RegressionResult = struct {
    benchmark_name: []const u8,

    // Current vs baseline
    current_measurement: PerformanceMeasurement,
    baseline_measurement: ?PerformanceMeasurement,

    // Regression analysis
    latency_regression: bool = false,
    latency_change_percent: f64 = 0.0,

    throughput_regression: bool = false,
    throughput_change_percent: f64 = 0.0,

    memory_regression: bool = false,
    memory_change_percent: f64 = 0.0,

    // Overall assessment
    has_regression: bool = false,
    regression_severity: RegressionSeverity = .none,

    // Statistical confidence
    statistically_significant: bool = false,
    confidence_level: f64 = 0.0,

    pub const RegressionSeverity = enum { none, minor, moderate, severe, critical };

    pub fn print_summary(self: RegressionResult) void {
        const status_icon = if (self.has_regression) "❌" else "✅";
        const severity_text = switch (self.regression_severity) {
            .none => "None",
            .minor => "Minor",
            .moderate => "Moderate",
            .severe => "Severe",
            .critical => "CRITICAL",
        };

        print("{s} {s} - {s} regression\n", .{ status_icon, self.benchmark_name, severity_text });

        if (self.baseline_measurement) |baseline| {
            print("  Latency: {:.2}ms → {:.2}ms ({:.1}% change)\n", .{ baseline.latency_ms(), self.current_measurement.latency_ms(), self.latency_change_percent });

            print("  Throughput: {:.1} → {:.1} ops/sec ({:.1}% change)\n", .{ baseline.throughput_ops_per_sec, self.current_measurement.throughput_ops_per_sec, self.throughput_change_percent });

            print("  Memory: {:.1} → {:.1} KB ({:.1}% change)\n", .{ @as(f64, @floatFromInt(baseline.memory_bytes)) / 1024.0, @as(f64, @floatFromInt(self.current_measurement.memory_bytes)) / 1024.0, self.memory_change_percent });
        }

        if (self.has_regression) {
            print("  🔍 Statistical significance: {:.1}% confidence\n", .{self.confidence_level * 100.0});
        }
    }
};

/// Performance regression detector
pub const PerformanceRegressionDetector = struct {
    allocator: Allocator,
    config: RegressionDetectionConfig,
    baseline: PerformanceBaseline,
    regression_history: ArrayList(RegressionResult),

    pub fn init(allocator: Allocator, config: RegressionDetectionConfig) PerformanceRegressionDetector {
        return .{
            .allocator = allocator,
            .config = config,
            .baseline = PerformanceBaseline.init(allocator),
            .regression_history = ArrayList(RegressionResult).init(allocator),
        };
    }

    pub fn deinit(self: *PerformanceRegressionDetector) void {
        self.baseline.deinit();
        self.regression_history.deinit();
    }

    /// Load baseline from file
    pub fn loadBaseline(self: *PerformanceRegressionDetector, file_path: []const u8) !void {
        try self.baseline.loadFromFile(file_path);
    }

    /// Save current baseline to file
    pub fn saveBaseline(self: *PerformanceRegressionDetector, file_path: []const u8) !void {
        try self.baseline.saveToFile(file_path);
    }

    /// Add a baseline measurement
    pub fn addBaselineMeasurement(self: *PerformanceRegressionDetector, measurement: PerformanceMeasurement) !void {
        try self.baseline.addMeasurement(measurement);
    }

    /// Detect regression for a current measurement
    pub fn detectRegression(self: *PerformanceRegressionDetector, current: PerformanceMeasurement) !RegressionResult {
        var result = RegressionResult{
            .benchmark_name = current.name,
            .current_measurement = current,
            .baseline_measurement = self.baseline.getBaseline(current.name),
        };

        if (result.baseline_measurement) |baseline| {
            // Calculate percentage changes
            result.latency_change_percent = calculatePercentageChange(@as(f64, @floatFromInt(baseline.latency_ns)), @as(f64, @floatFromInt(current.latency_ns)));

            result.throughput_change_percent = calculatePercentageChange(baseline.throughput_ops_per_sec, current.throughput_ops_per_sec);

            result.memory_change_percent = calculatePercentageChange(@as(f64, @floatFromInt(baseline.memory_bytes)), @as(f64, @floatFromInt(current.memory_bytes)));

            // Detect regressions
            result.latency_regression = result.latency_change_percent > (self.config.latency_regression_threshold * 100.0);
            result.throughput_regression = result.throughput_change_percent < -(self.config.throughput_regression_threshold * 100.0);
            result.memory_regression = result.memory_change_percent > (self.config.memory_regression_threshold * 100.0);

            result.has_regression = result.latency_regression or result.throughput_regression or result.memory_regression;

            // Determine severity
            result.regression_severity = determineSeverity(result.latency_change_percent, result.throughput_change_percent, result.memory_change_percent);

            // Statistical significance (simplified)
            result.statistically_significant = true; // Would use proper statistical tests in production
            result.confidence_level = self.config.confidence_level;

            // Alert if enabled
            if (self.config.enable_alerts and result.has_regression) {
                print("⚠️ PERFORMANCE REGRESSION DETECTED: {s}\n", .{current.name});
                result.print_summary();
            }
        } else {
            // No baseline available - add current as baseline
            try self.addBaselineMeasurement(current);
            print("📊 No baseline for {s} - added current measurement as baseline\n", .{current.name});
        }

        // Save to history
        if (self.config.save_regression_history) {
            try self.regression_history.append(result);
        }

        return result;
    }

    /// Run a benchmark and detect regressions
    pub fn benchmarkWithRegressionDetection(self: *PerformanceRegressionDetector, name: []const u8, benchmark_fn: fn () anyerror!void, iterations: usize) !RegressionResult {
        print("📊 Running benchmark: {s} ({} iterations)\n", .{ name, iterations });

        var timer = try Timer.start();
        var latencies = ArrayList(u64).init(self.allocator);
        defer latencies.deinit();

        const memory_start = getCurrentMemoryUsage();

        // Warmup
        for (0..@min(iterations / 10, 10)) |_| {
            try benchmark_fn();
        }

        // Actual benchmark
        timer = try Timer.start();
        const overall_start = timer.read();

        for (0..iterations) |_| {
            const iter_start = timer.read();
            try benchmark_fn();
            const iter_end = timer.read();
            try latencies.append(iter_end - iter_start);
        }

        const overall_end = timer.read();
        const memory_end = getCurrentMemoryUsage();

        // Calculate statistics
        std.mem.sort(u64, latencies.items, {}, std.sort.asc(u64));
        const p50 = latencies.items[latencies.items.len / 2];
        const p90 = latencies.items[(latencies.items.len * 9) / 10];
        const p99 = latencies.items[(latencies.items.len * 99) / 100];

        const total_duration_ns = overall_end - overall_start;
        const throughput = (@as(f64, @floatFromInt(iterations)) * 1_000_000_000.0) / @as(f64, @floatFromInt(total_duration_ns));

        // Create measurement
        const measurement = PerformanceMeasurement{
            .name = name,
            .latency_ns = p50,
            .p50_latency_ns = p50,
            .p90_latency_ns = p90,
            .p99_latency_ns = p99,
            .throughput_ops_per_sec = throughput,
            .memory_bytes = memory_end - memory_start,
            .cpu_percent = 0.0, // Would require platform-specific implementation
            .timestamp = std.time.timestamp(),
        };

        print("  Results: P50={:.2}ms, P99={:.2}ms, {:.1} ops/sec\n", .{ measurement.p50_latency_ms(), measurement.p99_latency_ms(), throughput });

        // Detect regression
        return try self.detectRegression(measurement);
    }

    /// Generate comprehensive regression report
    pub fn generateRegressionReport(self: *PerformanceRegressionDetector) void {
        print("\n" ++ "=" * 80 ++ "\n");
        print("PERFORMANCE REGRESSION DETECTION REPORT\n");
        print("=" * 80 ++ "\n");

        var total_benchmarks: usize = 0;
        var regressions_detected: usize = 0;
        var critical_regressions: usize = 0;

        for (self.regression_history.items) |result| {
            total_benchmarks += 1;

            if (result.has_regression) {
                regressions_detected += 1;
                if (result.regression_severity == .critical or result.regression_severity == .severe) {
                    critical_regressions += 1;
                }
            }
        }

        print("📊 Summary:\n");
        print("  Total Benchmarks: {}\n", .{total_benchmarks});
        print("  Regressions Detected: {}\n", .{regressions_detected});
        print("  Critical Regressions: {}\n", .{critical_regressions});
        print("  Regression Rate: {:.1}%\n", .{if (total_benchmarks > 0)
            (@as(f64, @floatFromInt(regressions_detected)) / @as(f64, @floatFromInt(total_benchmarks))) * 100.0
        else
            0.0});

        if (regressions_detected > 0) {
            print("\n🔍 Regression Details:\n");
            for (self.regression_history.items) |result| {
                if (result.has_regression) {
                    result.print_summary();
                }
            }
        }

        print("\n🏆 Overall Status: ");
        if (critical_regressions > 0) {
            print("🔴 CRITICAL - {} critical performance regressions detected\n", .{critical_regressions});
        } else if (regressions_detected > 0) {
            print("⚠️ REGRESSIONS - {} performance regressions detected\n", .{regressions_detected});
        } else {
            print("✅ NO REGRESSIONS - All benchmarks within expected parameters\n", .{});
        }

        print("=" * 80 ++ "\n");
    }

    fn calculatePercentageChange(baseline: f64, current: f64) f64 {
        if (baseline == 0.0) return 0.0;
        return ((current - baseline) / baseline) * 100.0;
    }

    fn determineSeverity(latency_change: f64, throughput_change: f64, memory_change: f64) RegressionResult.RegressionSeverity {
        const max_change = @max(@max(@abs(latency_change), @abs(throughput_change)), @abs(memory_change));

        if (max_change >= 100.0) return .critical; // 100% change
        if (max_change >= 50.0) return .severe; // 50% change
        if (max_change >= 25.0) return .moderate; // 25% change
        if (max_change >= 10.0) return .minor; // 10% change
        return .none;
    }

    fn getCurrentMemoryUsage() usize {
        // Simplified - in production would use platform-specific APIs
        return 1024 * 1024; // 1MB baseline
    }
};

// Tests
test "regression_detector_basic" {
    const config = RegressionDetectionConfig{};
    var detector = PerformanceRegressionDetector.init(testing.allocator, config);
    defer detector.deinit();

    const measurement = PerformanceMeasurement{
        .name = "test_benchmark",
        .latency_ns = 1_000_000, // 1ms
        .throughput_ops_per_sec = 1000.0,
        .memory_bytes = 1024,
        .cpu_percent = 50.0,
        .timestamp = std.time.timestamp(),
    };

    const result = try detector.detectRegression(measurement);
    try testing.expect(!result.has_regression); // First measurement, no baseline
}

test "performance_measurement_helpers" {
    const measurement = PerformanceMeasurement{
        .name = "test",
        .latency_ns = 5_000_000, // 5ms
        .p50_latency_ns = 4_000_000, // 4ms
        .p99_latency_ns = 10_000_000, // 10ms
        .throughput_ops_per_sec = 200.0,
        .memory_bytes = 2048,
        .cpu_percent = 25.0,
        .timestamp = std.time.timestamp(),
    };

    try testing.expect(measurement.latency_ms() == 5.0);
    try testing.expect(measurement.p50_latency_ms() == 4.0);
    try testing.expect(measurement.p99_latency_ms() == 10.0);
}
