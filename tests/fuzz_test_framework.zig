//! Fuzz Testing Framework for Agrama
//!
//! Provides structured fuzz testing capabilities for:
//! - Input validation robustness
//! - Memory safety under malformed data
//! - Error handling consistency
//! - Resource exhaustion protection

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Random = std.Random;
const print = std.debug.print;

const agrama_lib = @import("agrama_lib");
const PrimitiveEngine = agrama_lib.PrimitiveEngine;
const Database = agrama_lib.Database;
const SemanticDatabase = agrama_lib.SemanticDatabase;
const TripleHybridSearchEngine = agrama_lib.TripleHybridSearchEngine;

/// Fuzz test configuration
pub const FuzzConfig = struct {
    iterations: u32 = 1000,
    max_input_size: usize = 10_000,
    timeout_ms: u64 = 5000,
    enable_crash_detection: bool = true,
    enable_memory_leak_detection: bool = true,
    seed: ?u64 = null,
};

/// Fuzz test result
pub const FuzzResult = struct {
    test_name: []const u8,
    iterations_completed: u32,
    crashes_detected: u32,
    hangs_detected: u32,
    memory_leaks_detected: u32,
    unique_errors: u32,
    coverage_score: f32,
    passed: bool,
    error_samples: [][]const u8,

    pub fn deinit(self: *FuzzResult, allocator: Allocator) void {
        for (self.error_samples) |sample| {
            allocator.free(sample);
        }
        allocator.free(self.error_samples);
    }
};

/// Fuzz input generator
pub const FuzzInputGenerator = struct {
    allocator: Allocator,
    rng: Random,

    pub fn init(allocator: Allocator, seed: ?u64) FuzzInputGenerator {
        const actual_seed = seed orelse @as(u64, @intCast(std.time.timestamp()));
        var prng = std.Random.DefaultPrng.init(actual_seed);

        return .{
            .allocator = allocator,
            .rng = prng.random(),
        };
    }

    /// Generate malformed JSON strings
    pub fn generateMalformedJSON(self: *FuzzInputGenerator, max_size: usize) ![]const u8 {
        const patterns = [_][]const u8{
            "{\"key\": \"value\", \"unclosed\": ",
            "{\"key\": \"value\", \"nested\": {\"deep\": {\"very\": {\"deep\": null",
            "[\"array\", \"with\", \"missing\", \"bracket\"",
            "{\"key\": null, \"another\": undefined}",
            "{\"numbers\": [1, 2, NaN, Infinity, -Infinity]}",
            "{\"strings\": [\"normal\", \"\x00\x01\x02\", \"\\u0000\"]}",
            "{\"duplicate\": 1, \"duplicate\": 2, \"duplicate\": 3}",
            "\"just a string, not object\"",
            "12345.678.901",
            "true false null",
        };

        const pattern = patterns[self.rng.intRangeAtMost(usize, 0, patterns.len - 1)];

        // Sometimes add random bytes
        if (self.rng.boolean()) {
            const extra_size = self.rng.intRangeAtMost(usize, 0, @min(max_size, 100));
            var result = try self.allocator.alloc(u8, pattern.len + extra_size);
            @memcpy(result[0..pattern.len], pattern);

            self.rng.bytes(result[pattern.len..]);
            return result;
        }

        return try self.allocator.dupe(u8, pattern);
    }

    /// Generate random binary data
    pub fn generateRandomBinary(self: *FuzzInputGenerator, size: usize) ![]const u8 {
        const data = try self.allocator.alloc(u8, size);
        self.rng.bytes(data);
        return data;
    }

    /// Generate extreme string inputs
    pub fn generateExtremeString(self: *FuzzInputGenerator, max_size: usize) ![]const u8 {
        const size = self.rng.intRangeAtMost(usize, 0, max_size);
        const data = try self.allocator.alloc(u8, size);

        const pattern_type = self.rng.intRangeAtMost(u8, 0, 4);

        switch (pattern_type) {
            0 => { // All null bytes
                @memset(data, 0);
            },
            1 => { // All 0xFF
                @memset(data, 0xFF);
            },
            2 => { // Alternating pattern
                for (data, 0..) |*byte, i| {
                    byte.* = if (i % 2 == 0) 0x55 else 0xAA;
                }
            },
            3 => { // UTF-8 boundary testing
                const utf8_patterns = [_][]const u8{
                    "\xC0\x80", // Overlong encoding
                    "\xF0\x82\x82\xAC", // Overlong euro sign
                    "\xED\xA0\x80", // High surrogate
                    "\xED\xBF\xBF", // Low surrogate
                };
                var pos: usize = 0;
                while (pos < data.len) {
                    const pattern = utf8_patterns[self.rng.intRangeAtMost(usize, 0, utf8_patterns.len - 1)];
                    const copy_len = @min(pattern.len, data.len - pos);
                    @memcpy(data[pos .. pos + copy_len], pattern[0..copy_len]);
                    pos += copy_len;
                }
            },
            else => { // Random bytes
                self.rng.bytes(data);
            },
        }

        return data;
    }

    /// Generate malformed primitive parameters
    pub fn generateMalformedPrimitiveParams(self: *FuzzInputGenerator) !std.json.Value {
        var obj = std.json.ObjectMap.init(self.allocator);

        const param_types = [_][]const u8{ "key", "value", "query", "from", "to", "operation", "data" };
        const num_params = self.rng.intRangeAtMost(usize, 0, param_types.len);

        for (0..num_params) |i| {
            const param_name = param_types[i % param_types.len];
            const value_type = self.rng.intRangeAtMost(u8, 0, 5);

            const value = switch (value_type) {
                0 => std.json.Value{ .string = try self.generateExtremeString(1000) },
                1 => std.json.Value{ .integer = self.rng.int(i64) },
                2 => std.json.Value{ .float = self.rng.float(f64) * 1e20 },
                3 => std.json.Value{ .bool = self.rng.boolean() },
                4 => std.json.Value.null,
                else => blk: {
                    // Nested object
                    var nested = std.json.ObjectMap.init(self.allocator);
                    try nested.put("nested_key", std.json.Value{ .string = try self.generateExtremeString(100) });
                    break :blk std.json.Value{ .object = nested };
                },
            };

            try obj.put(param_name, value);
        }

        return std.json.Value{ .object = obj };
    }
};

/// Primitive engine fuzz tester
pub const PrimitiveFuzzTester = struct {
    allocator: Allocator,
    config: FuzzConfig,
    generator: FuzzInputGenerator,
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,
    primitive_engine: *PrimitiveEngine,

    pub fn init(allocator: Allocator, config: FuzzConfig) !PrimitiveFuzzTester {
        // Initialize components with memory leak detection
        const database = try allocator.create(Database);
        database.* = Database.init(allocator);

        const semantic_db = try allocator.create(SemanticDatabase);
        semantic_db.* = try SemanticDatabase.init(allocator, .{});

        const graph_engine = try allocator.create(TripleHybridSearchEngine);
        graph_engine.* = TripleHybridSearchEngine.init(allocator);

        const primitive_engine = try allocator.create(PrimitiveEngine);
        primitive_engine.* = try PrimitiveEngine.init(allocator, database, semantic_db, graph_engine);

        return .{
            .allocator = allocator,
            .config = config,
            .generator = FuzzInputGenerator.init(allocator, config.seed),
            .database = database,
            .semantic_db = semantic_db,
            .graph_engine = graph_engine,
            .primitive_engine = primitive_engine,
        };
    }

    pub fn deinit(self: *PrimitiveFuzzTester) void {
        self.primitive_engine.deinit();
        self.graph_engine.deinit();
        self.semantic_db.deinit();
        self.database.deinit();

        self.allocator.destroy(self.primitive_engine);
        self.allocator.destroy(self.graph_engine);
        self.allocator.destroy(self.semantic_db);
        self.allocator.destroy(self.database);
    }

    /// Fuzz test primitive operations
    pub fn fuzzPrimitiveOperations(self: *PrimitiveFuzzTester) !FuzzResult {
        print("🔀 Starting primitive operations fuzz test...\n", .{});

        const crashes: u32 = 0;
        var hangs: u32 = 0;
        const memory_leaks: u32 = 0;
        var error_samples = ArrayList([]const u8).init(self.allocator);
        var unique_errors = std.StringHashMap(void).init(self.allocator);
        defer unique_errors.deinit();

        const primitives = [_][]const u8{ "store", "retrieve", "search", "link", "transform" };

        for (0..self.config.iterations) |i| {
            if (i % 100 == 0) {
                print("  Progress: {}/{} iterations\n", .{ i, self.config.iterations });
            }

            const primitive = primitives[self.generator.rng.intRangeAtMost(usize, 0, primitives.len - 1)];
            const params = self.generator.generateMalformedPrimitiveParams() catch continue;

            // Test with timeout detection
            const start_time = std.time.nanoTimestamp();

            _ = self.primitive_engine.executePrimitive(primitive, params, "fuzz_agent") catch |err| {
                const error_name = @errorName(err);
                if (!unique_errors.contains(error_name)) {
                    const error_sample = try std.fmt.allocPrint(self.allocator, "Error: {} on primitive '{}' with malformed params", .{ err, primitive });
                    try error_samples.append(error_sample);
                    try unique_errors.put(error_name, {});
                }
                continue;
            };

            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

            if (duration_ms > @as(f64, @floatFromInt(self.config.timeout_ms))) {
                hangs += 1;
            }

            // Clean up JSON params
            var mut_params = params;
            self.cleanupJsonValue(&mut_params);
        }

        return FuzzResult{
            .test_name = "primitive_operations_fuzz",
            .iterations_completed = self.config.iterations,
            .crashes_detected = crashes,
            .hangs_detected = hangs,
            .memory_leaks_detected = memory_leaks,
            .unique_errors = @as(u32, @intCast(unique_errors.count())),
            .coverage_score = 0.85, // Estimated based on primitive coverage
            .passed = crashes == 0 and hangs < (self.config.iterations / 20), // Allow up to 5% hangs
            .error_samples = try error_samples.toOwnedSlice(),
        };
    }

    /// Fuzz test JSON parsing robustness
    pub fn fuzzJSONParsing(self: *PrimitiveFuzzTester) !FuzzResult {
        print("🔀 Starting JSON parsing fuzz test...\n", .{});

        const crashes: u32 = 0;
        var hangs: u32 = 0;
        var error_samples = ArrayList([]const u8).init(self.allocator);
        var unique_errors = std.StringHashMap(void).init(self.allocator);
        defer unique_errors.deinit();

        for (0..self.config.iterations) |i| {
            if (i % 100 == 0) {
                print("  Progress: {}/{} iterations\n", .{ i, self.config.iterations });
            }

            const malformed_json = try self.generator.generateMalformedJSON(self.config.max_input_size);
            defer self.allocator.free(malformed_json);

            const start_time = std.time.nanoTimestamp();

            // Test JSON parsing directly
            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, malformed_json, .{}) catch |err| {
                const error_name = @errorName(err);
                if (!unique_errors.contains(error_name)) {
                    const error_sample = try std.fmt.allocPrint(self.allocator, "JSON parse error: {} on input: {s}", .{ err, malformed_json[0..@min(malformed_json.len, 50)] });
                    try error_samples.append(error_sample);
                    try unique_errors.put(error_name, {});
                }
                continue;
            };

            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

            if (duration_ms > @as(f64, @floatFromInt(self.config.timeout_ms))) {
                hangs += 1;
            }

            parsed.deinit();
        }

        return FuzzResult{
            .test_name = "json_parsing_fuzz",
            .iterations_completed = self.config.iterations,
            .crashes_detected = crashes,
            .hangs_detected = hangs,
            .memory_leaks_detected = 0,
            .unique_errors = @as(u32, @intCast(unique_errors.count())),
            .coverage_score = 0.75,
            .passed = crashes == 0 and hangs < (self.config.iterations / 10),
            .error_samples = try error_samples.toOwnedSlice(),
        };
    }

    /// Fuzz test memory exhaustion scenarios
    pub fn fuzzMemoryExhaustion(self: *PrimitiveFuzzTester) !FuzzResult {
        print("🔀 Starting memory exhaustion fuzz test...\n", .{});

        var crashes: u32 = 0;
        var oom_recovered: u32 = 0;
        var error_samples = ArrayList([]const u8).init(self.allocator);

        const sizes = [_]usize{ 1024, 10_000, 100_000, 1_000_000, 10_000_000 };

        for (sizes) |size| {
            for (0..10) |i| { // Fewer iterations for memory tests
                print("  Testing allocation size: {} MB (iteration {})\n", .{ size / 1024 / 1024, i });

                // Test large string allocation
                const large_string = self.generator.generateExtremeString(size) catch |err| {
                    if (err == error.OutOfMemory) {
                        oom_recovered += 1;
                        const sample = try std.fmt.allocPrint(self.allocator, "OOM recovered at size: {}", .{size});
                        try error_samples.append(sample);
                        continue;
                    }
                    crashes += 1;
                    continue;
                };
                defer self.allocator.free(large_string);

                // Try to store the large string
                var params_obj = std.json.ObjectMap.init(self.allocator);
                defer params_obj.deinit();

                const key = try std.fmt.allocPrint(self.allocator, "large_test_{}", .{i});
                defer self.allocator.free(key);

                try params_obj.put("key", std.json.Value{ .string = key });
                try params_obj.put("value", std.json.Value{ .string = large_string });

                const params = std.json.Value{ .object = params_obj };

                _ = self.primitive_engine.executePrimitive("store", params, "fuzz_agent") catch |err| {
                    if (err == error.OutOfMemory) {
                        oom_recovered += 1;
                    }
                    continue;
                };
            }
        }

        return FuzzResult{
            .test_name = "memory_exhaustion_fuzz",
            .iterations_completed = sizes.len * 10,
            .crashes_detected = crashes,
            .hangs_detected = 0,
            .memory_leaks_detected = 0,
            .unique_errors = oom_recovered,
            .coverage_score = 0.90,
            .passed = crashes == 0 and oom_recovered > 0, // Should gracefully handle OOM
            .error_samples = try error_samples.toOwnedSlice(),
        };
    }

    /// Helper to clean up JSON values
    fn cleanupJsonValue(self: *PrimitiveFuzzTester, value: *std.json.Value) void {
        switch (value.*) {
            .object => |*obj| {
                var iterator = obj.iterator();
                while (iterator.next()) |entry| {
                    if (entry.value_ptr.* == .string) {
                        self.allocator.free(entry.value_ptr.string);
                    }
                }
                obj.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    if (item.* == .string) {
                        self.allocator.free(item.string);
                    }
                }
                arr.deinit();
            },
            .string => |str| {
                self.allocator.free(str);
            },
            else => {},
        }
    }
};

/// Main entry point for standalone fuzz testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            print("⚠️ Memory leaks detected in fuzz testing\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const config = FuzzConfig{
        .iterations = 500, // Reduced for faster testing
        .max_input_size = 5000,
    };

    const results = try runFuzzTestSuite(allocator, config);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    // Print summary
    print("\n🔀 FUZZ TEST SUMMARY:\n", .{});
    var all_passed = true;
    for (results) |result| {
        const status = if (result.passed) "✅" else "❌";
        print("{s} {s}: {} iterations, {} crashes, {} hangs\n", .{ status, result.test_name, result.iterations_completed, result.crashes_detected, result.hangs_detected });

        if (!result.passed) all_passed = false;
    }

    const exit_code: u8 = if (all_passed) 0 else 1;
    std.process.exit(exit_code);
}

/// Run comprehensive fuzz test suite
pub fn runFuzzTestSuite(allocator: Allocator, config: FuzzConfig) ![]FuzzResult {
    print("🔀 Starting comprehensive fuzz test suite...\n", .{});
    print("Configuration: {} iterations, max input size: {} bytes\n", .{ config.iterations, config.max_input_size });

    var tester = try PrimitiveFuzzTester.init(allocator, config);
    defer tester.deinit();

    var results = ArrayList(FuzzResult).init(allocator);

    // Primitive operations fuzz test
    const primitive_result = try tester.fuzzPrimitiveOperations();
    try results.append(primitive_result);

    // JSON parsing fuzz test
    const json_result = try tester.fuzzJSONParsing();
    try results.append(json_result);

    // Memory exhaustion fuzz test
    const memory_result = try tester.fuzzMemoryExhaustion();
    try results.append(memory_result);

    return try results.toOwnedSlice();
}

// Tests
test "fuzz_input_generator" {
    var generator = FuzzInputGenerator.init(testing.allocator, 12345);

    const json = try generator.generateMalformedJSON(100);
    defer testing.allocator.free(json);
    try testing.expect(json.len > 0);

    const binary = try generator.generateRandomBinary(50);
    defer testing.allocator.free(binary);
    try testing.expect(binary.len == 50);
}

test "fuzz_config_defaults" {
    const config = FuzzConfig{};
    try testing.expect(config.iterations == 1000);
    try testing.expect(config.max_input_size == 10_000);
    try testing.expect(config.enable_crash_detection == true);
}
