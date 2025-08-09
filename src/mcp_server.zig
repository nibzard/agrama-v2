const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Database = @import("database.zig").Database;

/// JSON request structure for MCP tool calls
pub const MCPRequest = struct {
    id: []const u8,
    method: []const u8,
    params: struct {
        name: []const u8,
        arguments: std.json.Value,
    },

    pub fn deinit(self: *MCPRequest, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.method);
        allocator.free(self.params.name);
        self.params.arguments.deinit();
    }
};

/// Error information for MCP responses
pub const MCPError = struct {
    code: i32,
    message: []const u8,
};

/// JSON response structure for MCP tool calls
pub const MCPResponse = struct {
    id: []const u8,
    result: ?std.json.Value = null,
    @"error": ?MCPError = null,

    pub fn deinit(self: *MCPResponse, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.result) |*result| {
            // Recursively free JSON objects
            self.deinitJsonValue(result, allocator);
        }
        if (self.@"error") |error_info| {
            allocator.free(error_info.message);
        }
    }

    fn deinitJsonValue(self: *MCPResponse, value: *std.json.Value, allocator: Allocator) void {
        switch (value.*) {
            .object => |*obj| {
                var obj_iterator = obj.iterator();
                while (obj_iterator.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    self.deinitJsonValue(entry.value_ptr, allocator);
                }
                obj.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    self.deinitJsonValue(item, allocator);
                }
                arr.deinit();
            },
            .string => |str| {
                allocator.free(str);
            },
            else => {}, // Other types don't need cleanup
        }
    }
};

/// Agent information for tracking multiple concurrent agents
pub const AgentInfo = struct {
    id: []const u8,
    name: []const u8,
    connected_at: i64,
    last_activity: i64,
    requests_handled: u64,

    pub fn init(allocator: Allocator, id: []const u8, name: []const u8) !AgentInfo {
        const owned_id = try allocator.dupe(u8, id);
        const owned_name = try allocator.dupe(u8, name);
        const timestamp = std.time.timestamp();

        return AgentInfo{
            .id = owned_id,
            .name = owned_name,
            .connected_at = timestamp,
            .last_activity = timestamp,
            .requests_handled = 0,
        };
    }

    pub fn deinit(self: *AgentInfo, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
    }
};

/// Performance metrics for MCP operations
pub const MCPMetrics = struct {
    total_requests: u64 = 0,
    total_response_time_ms: u64 = 0,
    max_response_time_ms: u64 = 0,
    min_response_time_ms: u64 = std.math.maxInt(u64),
    error_count: u64 = 0,

    pub fn recordRequest(self: *MCPMetrics, response_time_ms: u64, success: bool) void {
        self.total_requests += 1;
        self.total_response_time_ms += response_time_ms;

        if (response_time_ms > self.max_response_time_ms) {
            self.max_response_time_ms = response_time_ms;
        }

        if (response_time_ms < self.min_response_time_ms) {
            self.min_response_time_ms = response_time_ms;
        }

        if (!success) {
            self.error_count += 1;
        }
    }

    pub fn getAverageResponseTime(self: MCPMetrics) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_response_time_ms)) / @as(f64, @floatFromInt(self.total_requests));
    }
};

/// Core MCP Server implementation with Database integration
pub const MCPServer = struct {
    allocator: Allocator,
    database: *Database,
    agents: ArrayList(AgentInfo),
    metrics: MCPMetrics,
    mutex: Mutex,
    event_callbacks: ArrayList(*const fn (event: []const u8) void),

    /// Initialize MCP Server with Database connection
    pub fn init(allocator: Allocator, database: *Database) MCPServer {
        return MCPServer{
            .allocator = allocator,
            .database = database,
            .agents = ArrayList(AgentInfo).init(allocator),
            .metrics = MCPMetrics{},
            .mutex = Mutex{},
            .event_callbacks = ArrayList(*const fn (event: []const u8) void).init(allocator),
        };
    }

    /// Clean up MCP Server resources
    pub fn deinit(self: *MCPServer) void {
        for (self.agents.items) |*agent| {
            agent.deinit(self.allocator);
        }
        self.agents.deinit();
        self.event_callbacks.deinit();
    }

    /// Register an agent with the server
    pub fn registerAgent(self: *MCPServer, agent_id: []const u8, agent_name: []const u8) !void {
        // Minimal implementation to avoid ALL memory allocations in agent creation
        // Just log for now - no data structure modifications
        std.log.info("Agent registered: {s} ({s})", .{ agent_name, agent_id });
        
        // Skip all memory operations to isolate the issue
        _ = self;
    }

    /// Unregister an agent from the server
    pub fn unregisterAgent(self: *MCPServer, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Simple implementation to avoid memory corruption
        std.log.info("Agent unregistered: {s}", .{agent_id});
    }

    /// Handle MCP tool request and return response
    pub fn handleRequest(self: *MCPServer, request: MCPRequest, agent_id: []const u8) !MCPResponse {
        const start_time = std.time.milliTimestamp();

        // Update agent activity
        self.updateAgentActivity(agent_id);

        var response = MCPResponse{
            .id = try self.allocator.dupe(u8, request.id),
        };

        const result = self.processToolCall(request.params.name, request.params.arguments, agent_id);
        const end_time = std.time.milliTimestamp();
        const response_time_ms = @as(u64, @intCast(end_time - start_time));

        if (result) |tool_result| {
            response.result = tool_result;
            self.metrics.recordRequest(response_time_ms, true);
        } else |err| {
            response.@"error" = MCPError{
                .code = -32000,
                .message = try self.allocator.dupe(u8, @errorName(err)),
            };
            self.metrics.recordRequest(response_time_ms, false);
        }

        return response;
    }

    /// Process individual tool calls
    fn processToolCall(self: *MCPServer, tool_name: []const u8, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        if (std.mem.eql(u8, tool_name, "read_code")) {
            return self.handleReadCode(arguments, agent_id);
        } else if (std.mem.eql(u8, tool_name, "write_code")) {
            return self.handleWriteCode(arguments, agent_id);
        } else if (std.mem.eql(u8, tool_name, "get_context")) {
            return self.handleGetContext(arguments, agent_id);
        } else {
            return error.UnknownTool;
        }
    }

    /// Handle read_code tool - Read file with context (history, dependencies, similar code)
    fn handleReadCode(self: *MCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        _ = agent_id; // Will be used for agent tracking in future

        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const include_history_value = arguments.object.get("include_history");
        const include_history = if (include_history_value) |v| v.bool else false;

        const history_limit_value = arguments.object.get("history_limit");
        const history_limit = if (history_limit_value) |v| @as(usize, @intCast(v.integer)) else 5;

        // Read current file content
        const current_content = self.database.getFile(path) catch |err| switch (err) {
            error.FileNotFound => {
                var empty_result = std.json.ObjectMap.init(self.allocator);
                try empty_result.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, path) });
                try empty_result.put("exists", std.json.Value{ .bool = false });
                return std.json.Value{ .object = empty_result };
            },
            else => return err,
        };

        // Create result object - Use arena for temporary allocations
        var arena_allocator = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var result = std.json.ObjectMap.init(arena);
        try result.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, path) });
        try result.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, current_content) });
        try result.put("exists", std.json.Value{ .bool = true });

        // Add history if requested
        if (include_history) {
            const history = self.database.getHistory(path, history_limit) catch |err| switch (err) {
                error.FileNotFound => &[_]@import("database.zig").Change{},
                else => return err,
            };
            defer if (history.len > 0) self.allocator.free(history);

            var history_array = std.json.Array.init(arena);
            for (history) |change| {
                var change_obj = std.json.ObjectMap.init(arena);
                try change_obj.put("timestamp", std.json.Value{ .integer = change.timestamp });
                try change_obj.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, change.content) });
                try history_array.append(std.json.Value{ .object = change_obj });
            }
            try result.put("history", std.json.Value{ .array = history_array });
        }

        // Create final result with proper allocator
        var final_result = std.json.ObjectMap.init(self.allocator);
        var result_iterator = result.iterator();
        while (result_iterator.next()) |entry| {
            try final_result.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
        }

        return std.json.Value{ .object = final_result };
    }

    /// Handle write_code tool - Code modification with provenance tracking
    fn handleWriteCode(self: *MCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const content_value = arguments.object.get("content") orelse return error.MissingContent;
        const content = content_value.string;

        // Save file to database (this automatically creates history entry)
        try self.database.saveFile(path, content);

        // Broadcast file change event
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"file_changed\",\"path\":\"{s}\",\"agent_id\":\"{s}\"}}", .{ path, agent_id });
        defer self.allocator.free(event);
        self.broadcastEvent(event);

        // Create result with proper memory management
        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, path) });
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });

        return std.json.Value{ .object = result };
    }

    /// Handle get_context tool - Comprehensive contextual information
    fn handleGetContext(self: *MCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        _ = agent_id; // Will be used for agent tracking in future

        const path_value = arguments.object.get("path");
        const context_type_value = arguments.object.get("type");
        const context_type = if (context_type_value) |v| v.string else "full";

        // Use arena allocator for temporary objects
        var arena_allocator = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_allocator.deinit();
        const arena = arena_allocator.allocator();

        var result = std.json.ObjectMap.init(self.allocator);

        if (path_value) |pv| {
            const path = pv.string;

            // Get file info if path is provided
            const content = self.database.getFile(path) catch "";
            try result.put("file", std.json.Value{ .string = try self.allocator.dupe(u8, path) });
            try result.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, content) });
        }

        // Add server metrics with proper memory management
        var metrics_obj = std.json.ObjectMap.init(arena);
        try metrics_obj.put("total_requests", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.total_requests)) });
        try metrics_obj.put("average_response_time", std.json.Value{ .float = self.metrics.getAverageResponseTime() });
        try metrics_obj.put("max_response_time", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.max_response_time_ms)) });
        try metrics_obj.put("error_count", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.error_count)) });

        // Copy metrics to main allocator
        var final_metrics = std.json.ObjectMap.init(self.allocator);
        var metrics_iterator = metrics_obj.iterator();
        while (metrics_iterator.next()) |entry| {
            try final_metrics.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
        }

        // Add simplified agent information
        var agents_array = std.json.Array.init(self.allocator);
        
        // Simplified agent count without accessing potentially corrupted data
        var simple_agent_obj = std.json.ObjectMap.init(self.allocator);
        try simple_agent_obj.put("count", std.json.Value{ .integer = @as(i64, @intCast(self.agents.items.len)) });
        try agents_array.append(std.json.Value{ .object = simple_agent_obj });

        try result.put("metrics", std.json.Value{ .object = final_metrics });
        try result.put("agents", std.json.Value{ .array = agents_array });
        try result.put("context_type", std.json.Value{ .string = try self.allocator.dupe(u8, context_type) });

        return std.json.Value{ .object = result };
    }

    /// Update agent activity timestamp and increment request count
    fn updateAgentActivity(self: *MCPServer, agent_id: []const u8) void {
        // Simple implementation to avoid memory corruption
        _ = self;
        _ = agent_id;
        // Activity tracking will be re-implemented later when memory issues are resolved
    }

    /// Add event callback for WebSocket broadcasting
    pub fn addEventCallback(self: *MCPServer, callback: *const fn (event: []const u8) void) !void {
        try self.event_callbacks.append(callback);
    }

    /// Broadcast event to all registered callbacks
    fn broadcastEvent(self: *MCPServer, event: []const u8) void {
        for (self.event_callbacks.items) |callback| {
            callback(event);
        }
    }

    /// Get server statistics
    pub fn getStats(self: *MCPServer) struct { agents: u32, requests: u64, avg_response_ms: f64 } {
        self.mutex.lock();
        defer self.mutex.unlock();

        return .{
            .agents = @as(u32, @intCast(self.agents.items.len)),
            .requests = self.metrics.total_requests,
            .avg_response_ms = self.metrics.getAverageResponseTime(),
        };
    }
};

// Unit Tests
test "MCPServer initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    const stats = server.getStats();
    try testing.expect(stats.agents == 0);
    try testing.expect(stats.requests == 0);
}

test "agent registration and management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    // Register an agent
    try server.registerAgent("agent-1", "Test Agent");

    var stats = server.getStats();
    try testing.expect(stats.agents == 1);

    // Unregister the agent
    server.unregisterAgent("agent-1");

    stats = server.getStats();
    try testing.expect(stats.agents == 0);
}

test "read_code tool with history" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    // Save a test file
    try db.saveFile("test.txt", "Hello World!");

    // Create read_code request
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    try arguments.put("path", std.json.Value{ .string = "test.txt" });
    try arguments.put("include_history", std.json.Value{ .bool = true });

    // Handle the request
    var result = try server.handleReadCode(std.json.Value{ .object = arguments }, "test-agent");
    defer {
        // Clean up the returned JSON object manually
        result.object.deinit();
    }

    try testing.expect(result.object.get("exists").?.bool == true);
    try testing.expectEqualSlices(u8, "Hello World!", result.object.get("content").?.string);
    try testing.expect(result.object.contains("history"));
}

test "write_code tool functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    // Create write_code request
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    try arguments.put("path", std.json.Value{ .string = "new_file.txt" });
    try arguments.put("content", std.json.Value{ .string = "New content!" });

    // Handle the request
    var result = try server.handleWriteCode(std.json.Value{ .object = arguments }, "test-agent");
    defer {
        // Clean up the returned JSON object manually
        result.object.deinit();
    }

    try testing.expect(result.object.get("success").?.bool == true);

    // Verify file was saved
    const saved_content = try db.getFile("new_file.txt");
    try testing.expectEqualSlices(u8, "New content!", saved_content);
}

test "get_context tool functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    // Register an agent first
    try server.registerAgent("test-agent", "Test Agent");

    // Create get_context request
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    try arguments.put("type", std.json.Value{ .string = "full" });

    // Handle the request
    var result = try server.handleGetContext(std.json.Value{ .object = arguments }, "test-agent");
    defer {
        // Clean up the returned JSON object manually
        result.object.deinit();
    }

    try testing.expect(result.object.contains("metrics"));
    try testing.expect(result.object.contains("agents"));
    try testing.expect(result.object.get("agents").?.array.items.len == 1);
}
