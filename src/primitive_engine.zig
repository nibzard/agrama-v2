//! Primitive Execution Engine - Core orchestration for AI Memory Substrate
//!
//! This module implements the execution engine that:
//! - Registers and manages the 5 core primitives
//! - Provides context management for agent identity and sessions
//! - Logs all operations for complete observability
//! - Monitors performance and provides metrics
//! - Enables extensible primitive registration
//!
//! Target performance: <1ms P50 latency for primitive execution

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const testing = std.testing;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;

const primitives = @import("primitives.zig");
const Primitive = primitives.Primitive;
const PrimitiveContext = primitives.PrimitiveContext;
const PrimitiveMetadata = primitives.PrimitiveMetadata;

const StorePrimitive = primitives.StorePrimitive;
const RetrievePrimitive = primitives.RetrievePrimitive;
const SearchPrimitive = primitives.SearchPrimitive;
const LinkPrimitive = primitives.LinkPrimitive;
const TransformPrimitive = primitives.TransformPrimitive;

/// Core primitive execution engine with full observability
pub const PrimitiveEngine = struct {
    allocator: Allocator,
    primitives_map: HashMap([]const u8, Primitive, StringContext, std.hash_map.default_max_load_percentage),
    context: PrimitiveContext,

    // Performance monitoring
    total_executions: u64 = 0,
    total_execution_time_ns: u64 = 0,
    operation_counts: HashMap([]const u8, u64, StringContext, std.hash_map.default_max_load_percentage),

    // Agent session management
    current_session_id: []const u8,
    session_start_time: i64,

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

    /// Initialize primitive engine with database connections
    pub fn init(allocator: Allocator, database: *Database, semantic_db: *SemanticDatabase, graph_engine: *TripleHybridSearchEngine) !PrimitiveEngine {
        var engine = PrimitiveEngine{
            .allocator = allocator,
            .primitives_map = HashMap([]const u8, Primitive, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .context = PrimitiveContext{
                .allocator = allocator,
                .database = database,
                .semantic_db = semantic_db,
                .graph_engine = graph_engine,
                .agent_id = "unknown",
                .timestamp = std.time.timestamp(),
                .session_id = "default",
            },
            .operation_counts = HashMap([]const u8, u64, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .current_session_id = try allocator.dupe(u8, "default"),
            .session_start_time = std.time.timestamp(),
        };

        // Register core primitives
        try engine.registerCorePrimitives();

        return engine;
    }

    /// Clean up engine resources
    pub fn deinit(self: *PrimitiveEngine) void {
        // Clean up registered primitive names (only once since both maps share the same keys)
        var primitive_iterator = self.primitives_map.iterator();
        while (primitive_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.primitives_map.deinit();

        // Clean up operation counts (don't free keys - they were already freed above)
        self.operation_counts.deinit();

        self.allocator.free(self.current_session_id);
    }

    /// Register all core primitives
    fn registerCorePrimitives(self: *PrimitiveEngine) !void {
        try self.registerPrimitive("store", StorePrimitive.execute, StorePrimitive.validate, StorePrimitive.metadata);
        try self.registerPrimitive("retrieve", RetrievePrimitive.execute, RetrievePrimitive.validate, RetrievePrimitive.metadata);
        try self.registerPrimitive("search", SearchPrimitive.execute, SearchPrimitive.validate, SearchPrimitive.metadata);
        try self.registerPrimitive("link", LinkPrimitive.execute, LinkPrimitive.validate, LinkPrimitive.metadata);
        try self.registerPrimitive("transform", TransformPrimitive.execute, TransformPrimitive.validate, TransformPrimitive.metadata);
    }

    /// Register a new primitive
    pub fn registerPrimitive(self: *PrimitiveEngine, name: []const u8, execute_fn: *const fn (context: *PrimitiveContext, params: std.json.Value) anyerror!std.json.Value, validate_fn: *const fn (params: std.json.Value) anyerror!void, metadata: PrimitiveMetadata) !void {
        // Create one owned string for both maps - they will share the same key
        const owned_name = try self.allocator.dupe(u8, name);

        // Use the same string for both maps to avoid double allocation/deallocation
        errdefer self.allocator.free(owned_name);

        const primitive = Primitive{
            .name = owned_name,
            .execute = execute_fn,
            .validate = validate_fn,
            .metadata = metadata,
        };

        try self.primitives_map.put(owned_name, primitive);

        // Use the same string for operation counts - no need to duplicate again
        try self.operation_counts.put(owned_name, 0);
    }

    /// Execute a primitive operation with full context and monitoring
    pub fn executePrimitive(self: *PrimitiveEngine, name: []const u8, params: std.json.Value, agent_id: []const u8) !std.json.Value {
        var execution_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Update context for this execution
        self.context.agent_id = agent_id;
        self.context.timestamp = std.time.timestamp();

        // Find primitive
        const primitive = self.primitives_map.get(name) orelse return error.UnknownPrimitive;

        // Validate input parameters
        try primitive.validate(params);

        // Execute the primitive
        const result = try primitive.execute(&self.context, params);

        // Update performance metrics
        const execution_time_ns = execution_timer.read();
        self.total_executions += 1;
        self.total_execution_time_ns += execution_time_ns;

        // Update operation count
        if (self.operation_counts.getPtr(name)) |count_ptr| {
            count_ptr.* += 1;
        }

        // Log the operation for observability
        try self.logOperation(name, params, result, agent_id, execution_time_ns);

        return result;
    }

    /// Start a new agent session
    pub fn startSession(self: *PrimitiveEngine, session_id: []const u8) !void {
        self.allocator.free(self.current_session_id);
        self.current_session_id = try self.allocator.dupe(u8, session_id);
        self.context.session_id = self.current_session_id;
        self.session_start_time = std.time.timestamp();
    }

    /// Get list of all registered primitives
    pub fn listPrimitives(self: *PrimitiveEngine) !std.json.Value {
        var primitives_array = std.json.Array.init(self.allocator);

        var iterator = self.primitives_map.iterator();
        while (iterator.next()) |entry| {
            const primitive = entry.value_ptr.*;
            var primitive_obj = std.json.ObjectMap.init(self.allocator);

            try primitive_obj.put("name", std.json.Value{ .string = try self.allocator.dupe(u8, entry.key_ptr.*) });
            try primitive_obj.put("description", std.json.Value{ .string = try self.allocator.dupe(u8, primitive.metadata.description) });
            try primitive_obj.put("performance", std.json.Value{ .string = try self.allocator.dupe(u8, primitive.metadata.performance_characteristics) });

            // Add usage count
            const usage_count = self.operation_counts.get(entry.key_ptr.*) orelse 0;
            try primitive_obj.put("usage_count", std.json.Value{ .integer = @as(i64, @intCast(usage_count)) });

            try primitives_array.append(std.json.Value{ .object = primitive_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("primitives", std.json.Value{ .array = primitives_array });
        try result.put("count", std.json.Value{ .integer = @as(i64, @intCast(primitives_array.items.len)) });
        try result.put("total_executions", std.json.Value{ .integer = @as(i64, @intCast(self.total_executions)) });

        return std.json.Value{ .object = result };
    }

    /// Get comprehensive performance statistics
    pub fn getPerformanceStats(self: *PrimitiveEngine) !std.json.Value {
        var stats = std.json.ObjectMap.init(self.allocator);

        // Overall performance metrics
        try stats.put("total_executions", std.json.Value{ .integer = @as(i64, @intCast(self.total_executions)) });

        const avg_execution_time_ms = if (self.total_executions > 0)
            @as(f64, @floatFromInt(self.total_execution_time_ns)) / @as(f64, @floatFromInt(self.total_executions)) / 1_000_000.0
        else
            0.0;
        try stats.put("avg_execution_time_ms", std.json.Value{ .float = avg_execution_time_ms });

        // Per-operation statistics
        var operation_stats = std.json.ObjectMap.init(self.allocator);
        var count_iterator = self.operation_counts.iterator();
        while (count_iterator.next()) |entry| {
            const count = entry.value_ptr.*;
            try operation_stats.put(try self.allocator.dupe(u8, entry.key_ptr.*), std.json.Value{ .integer = @as(i64, @intCast(count)) });
        }
        try stats.put("operation_counts", std.json.Value{ .object = operation_stats });

        // Session information
        try stats.put("current_session", std.json.Value{ .string = try self.allocator.dupe(u8, self.current_session_id) });
        try stats.put("session_duration_seconds", std.json.Value{ .integer = std.time.timestamp() - self.session_start_time });

        return std.json.Value{ .object = stats };
    }

    /// Log operation for observability and debugging
    fn logOperation(self: *PrimitiveEngine, operation: []const u8, params: std.json.Value, result: std.json.Value, agent_id: []const u8, execution_time_ns: u64) !void {
        // Create simplified log entry as string to avoid complex memory management
        const execution_time_ms = @as(f64, @floatFromInt(execution_time_ns)) / 1_000_000.0;

        // Extract success status safely
        const success = if (result == .object) blk: {
            if (result.object.get("success")) |s| {
                if (s == .bool) break :blk s.bool;
            }
            break :blk true;
        } else true;

        // Create simple log entry
        const log_entry = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "timestamp": {d},
            \\  "operation": "{s}",
            \\  "agent_id": "{s}",
            \\  "session_id": "{s}",
            \\  "execution_time_ns": {d},
            \\  "execution_time_ms": {d:.3},
            \\  "success": {s},
            \\  "params_size": {d}
            \\}}
        , .{
            self.context.timestamp,
            operation,
            agent_id,
            self.current_session_id,
            execution_time_ns,
            execution_time_ms,
            if (success) "true" else "false",
            if (params == .object) params.object.count() else 0,
        });
        defer self.allocator.free(log_entry);

        // Create unique log key
        const log_key = try std.fmt.allocPrint(self.allocator, "_ops:{d}:{s}:{s}", .{ self.context.timestamp, operation, agent_id });
        defer self.allocator.free(log_key);

        // Store in database for later analysis
        try self.context.database.saveFile(log_key, log_entry);
    }

    /// Get operation logs for debugging and analysis
    pub fn getOperationLogs(self: *PrimitiveEngine, agent_id: ?[]const u8, limit: u32) ![]std.json.Value {
        var logs = ArrayList(std.json.Value).init(self.allocator);

        // Iterate through database to find operation logs
        var file_iterator = self.context.database.current_files.iterator();
        var count: u32 = 0;

        while (file_iterator.next()) |entry| {
            if (count >= limit) break;

            const key = entry.key_ptr.*;
            if (std.mem.startsWith(u8, key, "_ops:")) {
                // Parse agent filter
                if (agent_id) |filter_agent| {
                    if (std.mem.indexOf(u8, key, filter_agent) == null) {
                        continue;
                    }
                }

                const log_json = entry.value_ptr.*;
                const parsed_log = std.json.parseFromSlice(std.json.Value, self.allocator, log_json, .{}) catch continue;

                try logs.append(parsed_log.value);
                count += 1;
            }
        }

        return logs.toOwnedSlice();
    }

    /// Clear old operation logs (maintenance)
    pub fn cleanupOldLogs(self: *PrimitiveEngine, older_than_seconds: i64) !u32 {
        const cutoff_timestamp = std.time.timestamp() - older_than_seconds;
        var deleted_count: u32 = 0;

        var keys_to_delete = ArrayList([]const u8).init(self.allocator);
        defer keys_to_delete.deinit();

        // Find logs older than cutoff
        var file_iterator = self.context.database.current_files.iterator();
        while (file_iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.startsWith(u8, key, "_ops:")) {
                // Extract timestamp from key format "_ops:{timestamp}:{operation}:{agent}"
                const timestamp_str = key[5..]; // Skip "_ops:"
                if (std.mem.indexOf(u8, timestamp_str, ":")) |colon_pos| {
                    const timestamp = std.fmt.parseInt(i64, timestamp_str[0..colon_pos], 10) catch continue;
                    if (timestamp < cutoff_timestamp) {
                        try keys_to_delete.append(try self.allocator.dupe(u8, key));
                    }
                }
            }
        }

        // Delete old logs
        for (keys_to_delete.items) |key| {
            // Note: Database doesn't have deleteFile method, so we simulate by storing empty content
            // In a real implementation, this would properly delete the file
            try self.context.database.saveFile(key, "");
            deleted_count += 1;
            self.allocator.free(key);
        }

        return deleted_count;
    }
};

/// Helper functions for JSON manipulation
fn copyJsonValue(allocator: Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => std.json.Value.null,
        .bool => |b| std.json.Value{ .bool = b },
        .integer => |i| std.json.Value{ .integer = i },
        .float => |f| std.json.Value{ .float = f },
        .number_string => |s| std.json.Value{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| std.json.Value{ .string = try allocator.dupe(u8, s) },
        .array => |arr| blk: {
            var new_array = std.json.Array.init(allocator);
            for (arr.items) |item| {
                try new_array.append(try copyJsonValue(allocator, item));
            }
            break :blk std.json.Value{ .array = new_array };
        },
        .object => |obj| blk: {
            var new_object = std.json.ObjectMap.init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                const value_copy = try copyJsonValue(allocator, entry.value_ptr.*);
                try new_object.put(key_copy, value_copy);
            }
            break :blk std.json.Value{ .object = new_object };
        },
    };
}

fn estimateJsonSize(value: std.json.Value) !usize {
    return switch (value) {
        .null => 4, // "null"
        .bool => 5, // "false" is longer than "true"
        .integer => 20, // Rough estimate for i64
        .float => 24, // Rough estimate for f64
        .number_string => |s| s.len,
        .string => |s| s.len + 2, // Content + quotes
        .array => |arr| blk: {
            var size: usize = 2; // []
            for (arr.items) |item| {
                size += try estimateJsonSize(item) + 1; // item + comma
            }
            break :blk size;
        },
        .object => |obj| blk: {
            var size: usize = 2; // {}
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                size += entry.key_ptr.len + 3; // key + quotes + colon
                size += try estimateJsonSize(entry.value_ptr.*) + 1; // value + comma
            }
            break :blk size;
        },
    };
}

// Removed problematic freeJsonObject and freeJsonValue functions
// These were causing segmentation faults due to improper memory ownership tracking
// Now using simplified logging approach that avoids complex JSON memory management

// Performance and monitoring structures
pub const PrimitiveEngineStats = struct {
    total_executions: u64,
    avg_execution_time_ms: f64,
    operation_counts: HashMap([]const u8, u64, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    current_session: []const u8,
    session_duration_seconds: i64,

    pub fn deinit(self: *PrimitiveEngineStats, allocator: Allocator) void {
        var iter = self.operation_counts.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.operation_counts.deinit();
        allocator.free(self.current_session);
    }
};

// Unit Tests
test "PrimitiveEngine initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in PrimitiveEngine init test", .{});
        }
    }
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Should have registered core primitives
    try testing.expect(engine.primitives_map.count() == 5);
    try testing.expect(engine.total_executions == 0);
}

test "PrimitiveEngine primitive execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in PrimitiveEngine execution test", .{});
        }
    }
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Create test parameters for store operation
    var params_obj = std.json.ObjectMap.init(allocator);
    defer params_obj.deinit();

    try params_obj.put("key", std.json.Value{ .string = "test_key" });
    try params_obj.put("value", std.json.Value{ .string = "test_value" });

    const params = std.json.Value{ .object = params_obj };

    // Execute store primitive
    const result = try engine.executePrimitive("store", params, "test_agent");
    defer primitives.cleanupPrimitiveResult(allocator, result);

    try testing.expect(result.object.get("success").?.bool == true);
    try testing.expect(engine.total_executions == 1);

    // Verify operation was logged
    try testing.expect(engine.operation_counts.get("store").? == 1);
}

test "PrimitiveEngine session management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Test session management
    try engine.startSession("test_session_123");
    try testing.expect(std.mem.eql(u8, engine.current_session_id, "test_session_123"));
    try testing.expect(std.mem.eql(u8, engine.context.session_id, "test_session_123"));
}

test "PrimitiveEngine performance statistics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Get performance stats
    const stats = try engine.getPerformanceStats();
    defer primitives.cleanupPrimitiveResult(allocator, stats);

    try testing.expect(stats.object.get("total_executions").?.integer == 0);
    try testing.expect(stats.object.get("avg_execution_time_ms").?.float == 0.0);
    try testing.expect(std.mem.eql(u8, stats.object.get("current_session").?.string, "default"));
}

test "PrimitiveEngine list primitives" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    const primitives_list = try engine.listPrimitives();
    defer primitives.cleanupPrimitiveResult(allocator, primitives_list);

    try testing.expect(primitives_list.object.get("count").?.integer == 5);
    try testing.expect(primitives_list.object.get("total_executions").?.integer == 0);

    const primitives_array = primitives_list.object.get("primitives").?.array;
    try testing.expect(primitives_array.items.len == 5);

    // Check that we have the expected primitives
    var found_store = false;
    var found_retrieve = false;
    var found_search = false;
    var found_link = false;
    var found_transform = false;

    for (primitives_array.items) |primitive| {
        const name = primitive.object.get("name").?.string;
        if (std.mem.eql(u8, name, "store")) found_store = true;
        if (std.mem.eql(u8, name, "retrieve")) found_retrieve = true;
        if (std.mem.eql(u8, name, "search")) found_search = true;
        if (std.mem.eql(u8, name, "link")) found_link = true;
        if (std.mem.eql(u8, name, "transform")) found_transform = true;
    }

    try testing.expect(found_store and found_retrieve and found_search and found_link and found_transform);
}
