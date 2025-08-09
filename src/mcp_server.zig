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
            result.deinit();
        }
        if (self.@"error") |error_info| {
            allocator.free(error_info.message);
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
    agents: HashMap([]const u8, AgentInfo, HashContext, std.hash_map.default_max_load_percentage),
    metrics: MCPMetrics,
    mutex: Mutex,
    event_callbacks: ArrayList(*const fn (event: []const u8) void),

    const HashContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    /// Initialize MCP Server with Database connection
    pub fn init(allocator: Allocator, database: *Database) MCPServer {
        return MCPServer{
            .allocator = allocator,
            .database = database,
            .agents = HashMap([]const u8, AgentInfo, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .metrics = MCPMetrics{},
            .mutex = Mutex{},
            .event_callbacks = ArrayList(*const fn (event: []const u8) void).init(allocator),
        };
    }

    /// Clean up MCP Server resources
    pub fn deinit(self: *MCPServer) void {
        var agent_iterator = self.agents.iterator();
        while (agent_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.agents.deinit();
        self.event_callbacks.deinit();
    }

    /// Register an agent with the server
    pub fn registerAgent(self: *MCPServer, agent_id: []const u8, agent_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const agent_info = try AgentInfo.init(self.allocator, agent_id, agent_name);
        try self.agents.put(agent_info.id, agent_info);

        // Broadcast agent connection event
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_connected\",\"agent_id\":\"{s}\",\"agent_name\":\"{s}\"}}", .{ agent_id, agent_name });
        defer self.allocator.free(event);
        self.broadcastEvent(event);
    }

    /// Unregister an agent from the server
    pub fn unregisterAgent(self: *MCPServer, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.agents.fetchRemove(agent_id)) |kv| {
            var agent_info = kv.value;
            agent_info.deinit(self.allocator);

            // Broadcast agent disconnection event
            const event = std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_disconnected\",\"agent_id\":\"{s}\"}}", .{agent_id}) catch return;
            defer self.allocator.free(event);
            self.broadcastEvent(event);
        }
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
            error.FileNotFound => return std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) },
            else => return err,
        };

        // Create result object
        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("path", std.json.Value{ .string = path });
        try result.put("content", std.json.Value{ .string = current_content });
        try result.put("exists", std.json.Value{ .bool = true });

        // Add history if requested
        if (include_history) {
            const history = self.database.getHistory(path, history_limit) catch |err| switch (err) {
                error.FileNotFound => &[_]@import("database.zig").Change{},
                else => return err,
            };
            defer if (history.len > 0) self.allocator.free(history);

            var history_array = std.json.Array.init(self.allocator);
            for (history) |change| {
                var change_obj = std.json.ObjectMap.init(self.allocator);
                try change_obj.put("timestamp", std.json.Value{ .integer = change.timestamp });
                try change_obj.put("content", std.json.Value{ .string = change.content });
                try history_array.append(std.json.Value{ .object = change_obj });
            }
            try result.put("history", std.json.Value{ .array = history_array });
        }

        return std.json.Value{ .object = result };
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

        // Create result
        var result = std.json.ObjectMap.init(self.allocator);
        try result.put("path", std.json.Value{ .string = path });
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

        var result = std.json.ObjectMap.init(self.allocator);

        if (path_value) |pv| {
            const path = pv.string;

            // Get file info if path is provided
            const content = self.database.getFile(path) catch "";
            try result.put("file", std.json.Value{ .string = path });
            try result.put("content", std.json.Value{ .string = content });
        }

        // Add server metrics
        var metrics_obj = std.json.ObjectMap.init(self.allocator);
        try metrics_obj.put("total_requests", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.total_requests)) });
        try metrics_obj.put("average_response_time", std.json.Value{ .float = self.metrics.getAverageResponseTime() });
        try metrics_obj.put("max_response_time", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.max_response_time_ms)) });
        try metrics_obj.put("error_count", std.json.Value{ .integer = @as(i64, @intCast(self.metrics.error_count)) });

        // Add agent information
        var agents_array = std.json.Array.init(self.allocator);
        var agent_iterator = self.agents.iterator();
        while (agent_iterator.next()) |entry| {
            var agent_obj = std.json.ObjectMap.init(self.allocator);
            const agent = entry.value_ptr;
            try agent_obj.put("id", std.json.Value{ .string = agent.id });
            try agent_obj.put("name", std.json.Value{ .string = agent.name });
            try agent_obj.put("requests_handled", std.json.Value{ .integer = @as(i64, @intCast(agent.requests_handled)) });
            try agents_array.append(std.json.Value{ .object = agent_obj });
        }

        try result.put("metrics", std.json.Value{ .object = metrics_obj });
        try result.put("agents", std.json.Value{ .array = agents_array });
        try result.put("context_type", std.json.Value{ .string = context_type });

        return std.json.Value{ .object = result };
    }

    /// Update agent activity timestamp and increment request count
    fn updateAgentActivity(self: *MCPServer, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.agents.getPtr(agent_id)) |agent| {
            agent.last_activity = std.time.timestamp();
            agent.requests_handled += 1;
        }
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
            .agents = @as(u32, @intCast(self.agents.count())),
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
