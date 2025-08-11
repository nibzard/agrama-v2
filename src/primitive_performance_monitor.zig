//! Primitive Performance Monitor - Real-time performance analysis and optimization
//!
//! This module provides:
//! - Real-time performance metrics collection and analysis
//! - Hot path identification and optimization suggestions
//! - Memory usage tracking and leak detection
//! - Latency distribution analysis with percentile tracking
//! - Throughput analysis and bottleneck detection
//! - Agent behavior analysis and anomaly detection
//! - Performance regression detection
//!
//! Integrates with the optimized primitive engine to provide continuous performance visibility

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const testing = std.testing;
const Atomic = std.atomic.Value;

/// Real-time latency tracker with percentile calculation
const LatencyTracker = struct {
    samples: ArrayList(f64),
    allocator: Allocator,
    max_samples: usize,
    total_samples: Atomic(u64),
    
    // Pre-computed percentiles for efficiency
    cached_p50: Atomic(f64),
    cached_p95: Atomic(f64),
    cached_p99: Atomic(f64),
    last_update: Atomic(i64),
    
    pub fn init(allocator: Allocator, max_samples: usize) LatencyTracker {
        return LatencyTracker{
            .samples = ArrayList(f64).init(allocator),
            .allocator = allocator,
            .max_samples = max_samples,
            .total_samples = Atomic(u64).init(0),
            .cached_p50 = Atomic(f64).init(0.0),
            .cached_p95 = Atomic(f64).init(0.0),
            .cached_p99 = Atomic(f64).init(0.0),
            .last_update = Atomic(i64).init(0),
        };
    }
    
    pub fn deinit(self: *LatencyTracker) void {
        self.samples.deinit();
    }
    
    pub fn addSample(self: *LatencyTracker, latency_ms: f64) !void {
        // Add to circular buffer
        if (self.samples.items.len >= self.max_samples) {
            _ = self.samples.orderedRemove(0);
        }
        try self.samples.append(latency_ms);
        
        _ = self.total_samples.fetchAdd(1, .monotonic);
        
        // Update cached percentiles every 100 samples for efficiency
        if (self.total_samples.load(.monotonic) % 100 == 0) {
            self.updateCachedPercentiles();
        }
    }
    
    fn updateCachedPercentiles(self: *LatencyTracker) void {
        if (self.samples.items.len == 0) return;
        
        // Sort samples for percentile calculation
        var sorted_samples = self.allocator.alloc(f64, self.samples.items.len) catch return;
        defer self.allocator.free(sorted_samples);
        
        @memcpy(sorted_samples, self.samples.items);
        std.mem.sort(f64, sorted_samples, {}, std.sort.asc(f64));
        
        const p50 = percentile(sorted_samples, 50.0);
        const p95 = percentile(sorted_samples, 95.0);
        const p99 = percentile(sorted_samples, 99.0);
        
        self.cached_p50.store(@bitCast(p50), .monotonic);
        self.cached_p95.store(@bitCast(p95), .monotonic);
        self.cached_p99.store(@bitCast(p99), .monotonic);
        self.last_update.store(std.time.timestamp(), .monotonic);
    }
    
    pub fn getP50(self: *LatencyTracker) f64 {
        return @bitCast(self.cached_p50.load(.monotonic));
    }
    
    pub fn getP95(self: *LatencyTracker) f64 {
        return @bitCast(self.cached_p95.load(.monotonic));
    }
    
    pub fn getP99(self: *LatencyTracker) f64 {
        return @bitCast(self.cached_p99.load(.monotonic));
    }
    
    fn percentile(sorted_values: []f64, p: f64) f64 {
        if (sorted_values.len == 0) return 0;
        
        const index = (p / 100.0) * @as(f64, @floatFromInt(sorted_values.len - 1));
        const lower = @as(usize, @intFromFloat(@floor(index)));
        const upper = @as(usize, @intFromFloat(@ceil(index)));
        
        if (lower == upper) {
            return sorted_values[lower];
        }
        
        const weight = index - @floor(index);
        return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight;
    }
};

/// Throughput analyzer with sliding window
const ThroughputAnalyzer = struct {
    timestamps: ArrayList(i64),
    allocator: Allocator,
    window_size_seconds: i64,
    
    pub fn init(allocator: Allocator, window_size_seconds: i64) ThroughputAnalyzer {
        return ThroughputAnalyzer{
            .timestamps = ArrayList(i64).init(allocator),
            .allocator = allocator,
            .window_size_seconds = window_size_seconds,
        };
    }
    
    pub fn deinit(self: *ThroughputAnalyzer) void {
        self.timestamps.deinit();
    }
    
    pub fn recordOperation(self: *ThroughputAnalyzer) !void {
        const now = std.time.timestamp();
        try self.timestamps.append(now);
        
        // Clean up old timestamps outside the window
        self.cleanupOldTimestamps(now);
    }
    
    fn cleanupOldTimestamps(self: *ThroughputAnalyzer, current_time: i64) void {
        const cutoff = current_time - self.window_size_seconds;
        
        while (self.timestamps.items.len > 0 and self.timestamps.items[0] < cutoff) {
            _ = self.timestamps.orderedRemove(0);
        }
    }
    
    pub fn getCurrentThroughput(self: *ThroughputAnalyzer) f64 {
        if (self.timestamps.items.len == 0) return 0.0;
        
        self.cleanupOldTimestamps(std.time.timestamp());
        return @as(f64, @floatFromInt(self.timestamps.items.len)) / @as(f64, @floatFromInt(self.window_size_seconds));
    }
};

/// Memory usage tracker with leak detection
const MemoryTracker = struct {
    allocations: HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage),
    total_allocated: Atomic(usize),
    total_freed: Atomic(usize),
    peak_usage: Atomic(usize),
    allocator: Allocator,
    
    const AllocationInfo = struct {
        size: usize,
        timestamp: i64,
        stack_trace: ?[]const u8 = null,
    };
    
    pub fn init(allocator: Allocator) MemoryTracker {
        return MemoryTracker{
            .allocations = HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage).init(allocator),
            .total_allocated = Atomic(usize).init(0),
            .total_freed = Atomic(usize).init(0),
            .peak_usage = Atomic(usize).init(0),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *MemoryTracker) void {
        self.allocations.deinit();
    }
    
    pub fn recordAllocation(self: *MemoryTracker, ptr: usize, size: usize) !void {
        const info = AllocationInfo{
            .size = size,
            .timestamp = std.time.timestamp(),
        };
        
        try self.allocations.put(ptr, info);
        const new_total = self.total_allocated.fetchAdd(size, .monotonic) + size;
        
        // Update peak usage
        var current_peak = self.peak_usage.load(.monotonic);
        while (new_total > current_peak) {
            const result = self.peak_usage.compareAndSwap(current_peak, new_total, .monotonic, .monotonic);
            if (result == null) break;
            current_peak = result.?;
        }
    }
    
    pub fn recordDeallocation(self: *MemoryTracker, ptr: usize) void {
        if (self.allocations.fetchRemove(ptr)) |removed| {
            _ = self.total_freed.fetchAdd(removed.value.size, .monotonic);
        }
    }
    
    pub fn getCurrentUsage(self: *MemoryTracker) usize {
        return self.total_allocated.load(.monotonic) - self.total_freed.load(.monotonic);
    }
    
    pub fn getPeakUsage(self: *MemoryTracker) usize {
        return self.peak_usage.load(.monotonic);
    }
    
    pub fn detectLeaks(self: *MemoryTracker, max_age_seconds: i64) []usize {
        const cutoff_time = std.time.timestamp() - max_age_seconds;
        var leaks = ArrayList(usize).init(self.allocator);
        
        var iter = self.allocations.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.timestamp < cutoff_time) {
                leaks.append(entry.key_ptr.*) catch continue;
            }
        }
        
        return leaks.toOwnedSlice() catch &[_]usize{};
    }
};

/// Agent behavior analyzer for anomaly detection
const AgentBehaviorAnalyzer = struct {
    agent_patterns: HashMap([]const u8, AgentPattern, StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,
    
    const StringContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }
        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };
    
    const AgentPattern = struct {
        operations_per_minute: ArrayList(f64),
        common_operations: HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage),
        last_activity: i64,
        anomaly_score: f64,
        
        pub fn init(allocator: Allocator) AgentPattern {
            return AgentPattern{
                .operations_per_minute = ArrayList(f64).init(allocator),
                .common_operations = HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
                .last_activity = std.time.timestamp(),
                .anomaly_score = 0.0,
            };
        }
        
        pub fn deinit(self: *AgentPattern, allocator: Allocator) void {
            self.operations_per_minute.deinit();
            
            var iter = self.common_operations.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            self.common_operations.deinit();
        }
    };
    
    pub fn init(allocator: Allocator) AgentBehaviorAnalyzer {
        return AgentBehaviorAnalyzer{
            .agent_patterns = HashMap([]const u8, AgentPattern, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AgentBehaviorAnalyzer) void {
        var iter = self.agent_patterns.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_pattern = entry.value_ptr.*;
            mut_pattern.deinit(self.allocator);
        }
        self.agent_patterns.deinit();
    }
    
    pub fn recordOperation(self: *AgentBehaviorAnalyzer, agent_id: []const u8, operation: []const u8) !void {
        const pattern = try self.getOrCreatePattern(agent_id);
        pattern.last_activity = std.time.timestamp();
        
        // Record operation frequency
        if (pattern.common_operations.getPtr(operation)) |count_ptr| {
            count_ptr.* += 1;
        } else {
            const owned_operation = try self.allocator.dupe(u8, operation);
            try pattern.common_operations.put(owned_operation, 1);
        }
    }
    
    fn getOrCreatePattern(self: *AgentBehaviorAnalyzer, agent_id: []const u8) !*AgentPattern {
        if (self.agent_patterns.getPtr(agent_id)) |pattern| {
            return pattern;
        }
        
        const owned_id = try self.allocator.dupe(u8, agent_id);
        const new_pattern = AgentPattern.init(self.allocator);
        
        try self.agent_patterns.put(owned_id, new_pattern);
        return self.agent_patterns.getPtr(agent_id).?;
    }
    
    pub fn detectAnomalies(self: *AgentBehaviorAnalyzer, threshold: f64) [][]const u8 {
        var anomalous_agents = ArrayList([]const u8).init(self.allocator);
        
        var iter = self.agent_patterns.iterator();
        while (iter.next()) |entry| {
            const pattern = entry.value_ptr;
            
            // Simple anomaly detection based on operation frequency deviation
            const avg_ops = self.calculateAverageOperations(pattern);
            var deviation_score: f64 = 0.0;
            
            var op_iter = pattern.common_operations.iterator();
            while (op_iter.next()) |op_entry| {
                const freq = @as(f64, @floatFromInt(op_entry.value_ptr.*));
                deviation_score += std.math.pow(f64, freq - avg_ops, 2.0);
            }
            
            if (deviation_score > threshold) {
                anomalous_agents.append(entry.key_ptr.*) catch continue;
            }
        }
        
        return anomalous_agents.toOwnedSlice() catch &[_][]const u8{};
    }
    
    fn calculateAverageOperations(self: *AgentBehaviorAnalyzer, pattern: *AgentPattern) f64 {
        _ = self;
        
        if (pattern.common_operations.count() == 0) return 0.0;
        
        var total: u32 = 0;
        var iter = pattern.common_operations.iterator();
        while (iter.next()) |entry| {
            total += entry.value_ptr.*;
        }
        
        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(pattern.common_operations.count()));
    }
};

/// Comprehensive performance monitor
pub const PrimitivePerformanceMonitor = struct {
    allocator: Allocator,
    
    // Component analyzers
    latency_trackers: HashMap([]const u8, LatencyTracker, StringContext, std.hash_map.default_max_load_percentage),
    throughput_analyzer: ThroughputAnalyzer,
    memory_tracker: MemoryTracker,
    behavior_analyzer: AgentBehaviorAnalyzer,
    
    // Configuration
    monitoring_enabled: bool = true,
    detailed_logging: bool = false,
    alert_thresholds: AlertThresholds,
    
    // Alert system
    alerts: ArrayList(PerformanceAlert),
    
    const StringContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }
        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };
    
    const AlertThresholds = struct {
        max_latency_p99_ms: f64 = 100.0,
        min_throughput_qps: f64 = 100.0,
        max_memory_mb: f64 = 1000.0,
        anomaly_threshold: f64 = 10.0,
    };
    
    const PerformanceAlert = struct {
        alert_type: AlertType,
        message: []const u8,
        timestamp: i64,
        severity: AlertSeverity,
        
        const AlertType = enum {
            high_latency,
            low_throughput,
            memory_leak,
            agent_anomaly,
            system_overload,
        };
        
        const AlertSeverity = enum {
            info,
            warning,
            critical,
        };
    };
    
    pub fn init(allocator: Allocator) PrimitivePerformanceMonitor {
        return PrimitivePerformanceMonitor{
            .allocator = allocator,
            .latency_trackers = HashMap([]const u8, LatencyTracker, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .throughput_analyzer = ThroughputAnalyzer.init(allocator, 60), // 1 minute window
            .memory_tracker = MemoryTracker.init(allocator),
            .behavior_analyzer = AgentBehaviorAnalyzer.init(allocator),
            .alert_thresholds = AlertThresholds{},
            .alerts = ArrayList(PerformanceAlert).init(allocator),
        };
    }
    
    pub fn deinit(self: *PrimitivePerformanceMonitor) void {
        var tracker_iter = self.latency_trackers.iterator();
        while (tracker_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_tracker = entry.value_ptr.*;
            mut_tracker.deinit();
        }
        self.latency_trackers.deinit();
        
        self.throughput_analyzer.deinit();
        self.memory_tracker.deinit();
        self.behavior_analyzer.deinit();
        
        for (self.alerts.items) |alert| {
            self.allocator.free(alert.message);
        }
        self.alerts.deinit();
    }
    
    /// Record primitive execution for performance analysis
    pub fn recordPrimitiveExecution(self: *PrimitivePerformanceMonitor, primitive_name: []const u8, agent_id: []const u8, latency_ms: f64, memory_delta: isize) !void {
        if (!self.monitoring_enabled) return;
        
        // Record latency
        const tracker = try self.getOrCreateLatencyTracker(primitive_name);
        try tracker.addSample(latency_ms);
        
        // Record throughput
        try self.throughput_analyzer.recordOperation();
        
        // Record memory usage
        if (memory_delta > 0) {
            try self.memory_tracker.recordAllocation(@intFromPtr(tracker), @intCast(memory_delta));
        } else if (memory_delta < 0) {
            self.memory_tracker.recordDeallocation(@intFromPtr(tracker));
        }
        
        // Record agent behavior
        try self.behavior_analyzer.recordOperation(agent_id, primitive_name);
        
        // Check for alerts
        try self.checkAlerts();
    }
    
    fn getOrCreateLatencyTracker(self: *PrimitivePerformanceMonitor, primitive_name: []const u8) !*LatencyTracker {
        if (self.latency_trackers.getPtr(primitive_name)) |tracker| {
            return tracker;
        }
        
        const owned_name = try self.allocator.dupe(u8, primitive_name);
        const new_tracker = LatencyTracker.init(self.allocator, 10000); // Keep 10K samples
        
        try self.latency_trackers.put(owned_name, new_tracker);
        return self.latency_trackers.getPtr(primitive_name).?;
    }
    
    fn checkAlerts(self: *PrimitivePerformanceMonitor) !void {
        // Check latency alerts
        var tracker_iter = self.latency_trackers.iterator();
        while (tracker_iter.next()) |entry| {
            const p99_latency = entry.value_ptr.getP99();
            if (p99_latency > self.alert_thresholds.max_latency_p99_ms) {
                const message = try std.fmt.allocPrint(self.allocator, 
                    "High P99 latency detected for {s}: {d:.2}ms (threshold: {d:.2}ms)",
                    .{ entry.key_ptr.*, p99_latency, self.alert_thresholds.max_latency_p99_ms }
                );
                
                try self.alerts.append(PerformanceAlert{
                    .alert_type = .high_latency,
                    .message = message,
                    .timestamp = std.time.timestamp(),
                    .severity = .critical,
                });
            }
        }
        
        // Check throughput alerts
        const current_throughput = self.throughput_analyzer.getCurrentThroughput();
        if (current_throughput < self.alert_thresholds.min_throughput_qps) {
            const message = try std.fmt.allocPrint(self.allocator, 
                "Low throughput detected: {d:.2} QPS (threshold: {d:.2} QPS)",
                .{ current_throughput, self.alert_thresholds.min_throughput_qps }
            );
            
            try self.alerts.append(PerformanceAlert{
                .alert_type = .low_throughput,
                .message = message,
                .timestamp = std.time.timestamp(),
                .severity = .warning,
            });
        }
        
        // Check memory alerts
        const current_memory_mb = @as(f64, @floatFromInt(self.memory_tracker.getCurrentUsage())) / 1024.0 / 1024.0;
        if (current_memory_mb > self.alert_thresholds.max_memory_mb) {
            const message = try std.fmt.allocPrint(self.allocator, 
                "High memory usage detected: {d:.2}MB (threshold: {d:.2}MB)",
                .{ current_memory_mb, self.alert_thresholds.max_memory_mb }
            );
            
            try self.alerts.append(PerformanceAlert{
                .alert_type = .memory_leak,
                .message = message,
                .timestamp = std.time.timestamp(),
                .severity = .critical,
            });
        }
    }
    
    /// Generate comprehensive performance report
    pub fn generatePerformanceReport(self: *PrimitivePerformanceMonitor) !std.json.Value {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();
        
        var report = std.json.ObjectMap.init(json_allocator);
        
        // Overall metrics
        try report.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });
        try report.put("monitoring_enabled", std.json.Value{ .bool = self.monitoring_enabled });
        
        // Latency metrics by primitive
        var latency_report = std.json.ObjectMap.init(json_allocator);
        var tracker_iter = self.latency_trackers.iterator();
        while (tracker_iter.next()) |entry| {
            const tracker = entry.value_ptr;
            
            var primitive_stats = std.json.ObjectMap.init(json_allocator);
            try primitive_stats.put("p50_ms", std.json.Value{ .float = tracker.getP50() });
            try primitive_stats.put("p95_ms", std.json.Value{ .float = tracker.getP95() });
            try primitive_stats.put("p99_ms", std.json.Value{ .float = tracker.getP99() });
            try primitive_stats.put("total_samples", std.json.Value{ .integer = @as(i64, @intCast(tracker.total_samples.load(.monotonic))) });
            
            try latency_report.put(try json_allocator.dupe(u8, entry.key_ptr.*), std.json.Value{ .object = primitive_stats });
        }
        try report.put("latency_metrics", std.json.Value{ .object = latency_report });
        
        // Throughput metrics
        var throughput_report = std.json.ObjectMap.init(json_allocator);
        try throughput_report.put("current_qps", std.json.Value{ .float = self.throughput_analyzer.getCurrentThroughput() });
        try report.put("throughput_metrics", std.json.Value{ .object = throughput_report });
        
        // Memory metrics
        var memory_report = std.json.ObjectMap.init(json_allocator);
        try memory_report.put("current_mb", std.json.Value{ .float = @as(f64, @floatFromInt(self.memory_tracker.getCurrentUsage())) / 1024.0 / 1024.0 });
        try memory_report.put("peak_mb", std.json.Value{ .float = @as(f64, @floatFromInt(self.memory_tracker.getPeakUsage())) / 1024.0 / 1024.0 });
        try report.put("memory_metrics", std.json.Value{ .object = memory_report });
        
        // Alerts
        var alerts_array = std.json.Array.init(json_allocator);
        for (self.alerts.items) |alert| {
            var alert_obj = std.json.ObjectMap.init(json_allocator);
            try alert_obj.put("type", std.json.Value{ .string = @tagName(alert.alert_type) });
            try alert_obj.put("message", std.json.Value{ .string = try json_allocator.dupe(u8, alert.message) });
            try alert_obj.put("timestamp", std.json.Value{ .integer = alert.timestamp });
            try alert_obj.put("severity", std.json.Value{ .string = @tagName(alert.severity) });
            
            try alerts_array.append(std.json.Value{ .object = alert_obj });
        }
        try report.put("alerts", std.json.Value{ .array = alerts_array });
        
        return std.json.Value{ .object = report };
    }
    
    /// Clear old alerts and data
    pub fn cleanup(self: *PrimitivePerformanceMonitor, max_age_seconds: i64) void {
        const cutoff_time = std.time.timestamp() - max_age_seconds;
        
        // Clear old alerts
        var i: usize = 0;
        while (i < self.alerts.items.len) {
            if (self.alerts.items[i].timestamp < cutoff_time) {
                const removed = self.alerts.swapRemove(i);
                self.allocator.free(removed.message);
            } else {
                i += 1;
            }
        }
        
        // Detect memory leaks
        const leaks = self.memory_tracker.detectLeaks(3600); // 1 hour threshold
        defer self.allocator.free(leaks);
        
        if (leaks.len > 0 and self.detailed_logging) {
            std.log.warn("Detected {} potential memory leaks", .{leaks.len});
        }
    }
};

// Unit Tests
test "LatencyTracker basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var tracker = LatencyTracker.init(allocator, 1000);
    defer tracker.deinit();
    
    // Add some samples
    try tracker.addSample(1.0);
    try tracker.addSample(2.0);
    try tracker.addSample(3.0);
    try tracker.addSample(100.0); // Outlier
    
    try testing.expect(tracker.samples.items.len == 4);
    try testing.expect(tracker.total_samples.load(.monotonic) == 4);
}

test "ThroughputAnalyzer basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var analyzer = ThroughputAnalyzer.init(allocator, 60); // 1 minute window
    defer analyzer.deinit();
    
    // Record some operations
    try analyzer.recordOperation();
    try analyzer.recordOperation();
    
    const throughput = analyzer.getCurrentThroughput();
    try testing.expect(throughput >= 0.0);
}

test "MemoryTracker basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var tracker = MemoryTracker.init(allocator);
    defer tracker.deinit();
    
    // Record allocation and deallocation
    try tracker.recordAllocation(12345, 1024);
    try testing.expect(tracker.getCurrentUsage() == 1024);
    try testing.expect(tracker.getPeakUsage() == 1024);
    
    tracker.recordDeallocation(12345);
    try testing.expect(tracker.getCurrentUsage() == 0);
    try testing.expect(tracker.getPeakUsage() == 1024); // Peak should remain
}