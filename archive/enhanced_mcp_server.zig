//! Enhanced MCP Server with Full Database Integration
//! Integrates all Agrama database capabilities into the MCP interface

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const EnhancedDatabase = @import("enhanced_database.zig").EnhancedDatabase;
const EnhancedDatabaseConfig = @import("enhanced_database.zig").EnhancedDatabaseConfig;
const EnhancedMCPTools = @import("enhanced_mcp_tools.zig").EnhancedMCPTools;

/// Enhanced MCP Server with comprehensive database integration
pub const EnhancedMCPServer = struct {
    allocator: Allocator,
    enhanced_db: EnhancedDatabase,
    agents: ArrayList(AgentInfo),
    metrics: MCPMetrics,
    mutex: Mutex,
    event_callbacks: ArrayList(*const fn (event: []const u8) void),

    /// Agent information for tracking multiple concurrent agents
    const AgentInfo = struct {
        id: []const u8,
        name: []const u8,
        connected_at: i64,
        last_activity: i64,
        requests_handled: u64,
        capabilities: [][]const u8,

        pub fn init(allocator: Allocator, id: []const u8, name: []const u8, capabilities: []const []const u8) !AgentInfo {
            if (id.len == 0 or name.len == 0) {
                return error.InvalidInput;
            }

            const owned_id = try allocator.dupe(u8, id);
            errdefer allocator.free(owned_id);

            const owned_name = try allocator.dupe(u8, name);
            errdefer allocator.free(owned_name);

            const owned_capabilities = try allocator.alloc([]const u8, capabilities.len);
            errdefer allocator.free(owned_capabilities);

            for (capabilities, 0..) |cap, i| {
                owned_capabilities[i] = try allocator.dupe(u8, cap);
            }

            const timestamp = std.time.timestamp();

            return AgentInfo{
                .id = owned_id,
                .name = owned_name,
                .connected_at = timestamp,
                .last_activity = timestamp,
                .requests_handled = 0,
                .capabilities = owned_capabilities,
            };
        }

        pub fn deinit(self: *AgentInfo, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            for (self.capabilities) |cap| {
                allocator.free(cap);
            }
            allocator.free(self.capabilities);
        }
    };

    /// Performance metrics for MCP operations
    const MCPMetrics = struct {
        total_requests: u64 = 0,
        total_response_time_ms: u64 = 0,
        max_response_time_ms: u64 = 0,
        min_response_time_ms: u64 = std.math.maxInt(u64),
        error_count: u64 = 0,

        // Enhanced metrics
        semantic_searches: u64 = 0,
        dependency_analyses: u64 = 0,
        crdt_operations: u64 = 0,

        pub fn recordRequest(self: *MCPMetrics, response_time_ms: u64, success: bool, operation_type: OperationType) void {
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

            // Track operation types
            switch (operation_type) {
                .semantic_search => self.semantic_searches += 1,
                .dependency_analysis => self.dependency_analyses += 1,
                .crdt_operation => self.crdt_operations += 1,
                .standard => {},
            }
        }

        pub fn getAverageResponseTime(self: MCPMetrics) f64 {
            if (self.total_requests == 0) return 0.0;
            return @as(f64, @floatFromInt(self.total_response_time_ms)) / @as(f64, @floatFromInt(self.total_requests));
        }

        const OperationType = enum {
            standard,
            semantic_search,
            dependency_analysis,
            crdt_operation,
        };
    };

    /// JSON request structure for enhanced MCP tool calls
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

    /// JSON response structure for enhanced MCP tool calls
    pub const MCPResponse = struct {
        id: []const u8,
        result: ?std.json.Value = null,
        @"error": ?MCPError = null,

        pub const MCPError = struct {
            code: i32,
            message: []const u8,
        };

        pub fn deinit(self: *MCPResponse, allocator: Allocator) void {
            allocator.free(self.id);
            if (self.result) |*result| {
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
                else => {},
            }
        }
    };

    /// Initialize Enhanced MCP Server with full database integration
    pub fn init(allocator: Allocator, db_config: EnhancedDatabaseConfig) !EnhancedMCPServer {
        const enhanced_db = try EnhancedDatabase.init(allocator, db_config);

        return EnhancedMCPServer{
            .allocator = allocator,
            .enhanced_db = enhanced_db,
            .agents = ArrayList(AgentInfo).init(allocator),
            .metrics = MCPMetrics{},
            .mutex = Mutex{},
            .event_callbacks = ArrayList(*const fn (event: []const u8) void).init(allocator),
        };
    }

    /// Clean up Enhanced MCP Server resources
    pub fn deinit(self: *EnhancedMCPServer) void {
        for (self.agents.items) |*agent| {
            agent.deinit(self.allocator);
        }
        self.agents.deinit();
        self.event_callbacks.deinit();
        self.enhanced_db.deinit();
    }

    /// Register an agent with enhanced capabilities
    pub fn registerAgent(self: *EnhancedMCPServer, agent_id: []const u8, agent_name: []const u8, capabilities: []const []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const new_agent = try AgentInfo.init(self.allocator, agent_id, agent_name, capabilities);
        try self.agents.append(new_agent);

        std.log.info("Enhanced Agent registered: {s} ({s}) with {d} capabilities - Total agents: {d}", .{ agent_name, agent_id, capabilities.len, self.agents.items.len });
    }

    /// Unregister an agent
    pub fn unregisterAgent(self: *EnhancedMCPServer, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.agents.items.len) {
            if (std.mem.eql(u8, self.agents.items[i].id, agent_id)) {
                var removed_agent = self.agents.swapRemove(i);
                removed_agent.deinit(self.allocator);
                std.log.info("Enhanced Agent unregistered: {s} - Remaining agents: {d}", .{ agent_id, self.agents.items.len });
                return;
            }
            i += 1;
        }
        std.log.warn("Attempted to unregister unknown enhanced agent: {s}", .{agent_id});
    }

    /// Handle enhanced MCP tool request and return response
    pub fn handleRequest(self: *EnhancedMCPServer, request: MCPRequest, agent_id: []const u8) !MCPResponse {
        const start_time = std.time.milliTimestamp();

        // Update agent activity
        self.updateAgentActivity(agent_id);

        var response = MCPResponse{
            .id = try self.allocator.dupe(u8, request.id),
        };

        const result = self.processEnhancedToolCall(request.params.name, request.params.arguments, agent_id);
        const end_time = std.time.milliTimestamp();
        const response_time_ms = @as(u64, @intCast(end_time - start_time));

        // Determine operation type for metrics
        const op_type = self.getOperationType(request.params.name);

        if (result) |tool_result| {
            response.result = tool_result;
            self.metrics.recordRequest(response_time_ms, true, op_type);
        } else |err| {
            response.@"error" = MCPResponse.MCPError{
                .code = -32000,
                .message = try self.allocator.dupe(u8, @errorName(err)),
            };
            self.metrics.recordRequest(response_time_ms, false, op_type);
        }

        return response;
    }

    /// Process enhanced tool calls with full database integration
    fn processEnhancedToolCall(self: *EnhancedMCPServer, tool_name: []const u8, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        // Enhanced read_code tool
        if (std.mem.eql(u8, tool_name, EnhancedMCPTools.ReadCodeEnhanced.name)) {
            return self.handleReadCodeEnhanced(arguments, agent_id);
        }
        // Enhanced write_code tool
        else if (std.mem.eql(u8, tool_name, EnhancedMCPTools.WriteCodeEnhanced.name)) {
            return self.handleWriteCodeEnhanced(arguments, agent_id);
        }
        // Semantic search tool
        else if (std.mem.eql(u8, tool_name, EnhancedMCPTools.SemanticSearchTool.name)) {
            return self.handleSemanticSearch(arguments, agent_id);
        }
        // Dependency analysis tool
        else if (std.mem.eql(u8, tool_name, EnhancedMCPTools.AnalyzeDependenciesTool.name)) {
            return self.handleAnalyzeDependencies(arguments, agent_id);
        }
        // Database statistics tool
        else if (std.mem.eql(u8, tool_name, EnhancedMCPTools.DatabaseStatsTool.name)) {
            return self.handleDatabaseStats(arguments, agent_id);
        }
        // Legacy tools for backward compatibility
        else if (std.mem.eql(u8, tool_name, "read_code")) {
            return self.handleLegacyReadCode(arguments, agent_id);
        } else if (std.mem.eql(u8, tool_name, "write_code")) {
            return self.handleLegacyWriteCode(arguments, agent_id);
        } else if (std.mem.eql(u8, tool_name, "get_context")) {
            return self.handleLegacyGetContext(arguments, agent_id);
        } else {
            return error.UnknownTool;
        }
    }

    /// Handle enhanced read_code tool
    fn handleReadCodeEnhanced(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const params = try self.parseReadCodeEnhancedParams(arguments);
        return EnhancedMCPTools.ReadCodeEnhanced.execute(&self.enhanced_db, params, agent_id);
    }

    /// Handle enhanced write_code tool
    fn handleWriteCodeEnhanced(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const params = try self.parseWriteCodeEnhancedParams(arguments);
        return EnhancedMCPTools.WriteCodeEnhanced.execute(&self.enhanced_db, params, agent_id);
    }

    /// Handle semantic search tool
    fn handleSemanticSearch(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const params = try self.parseSemanticSearchParams(arguments);
        return EnhancedMCPTools.SemanticSearchTool.execute(&self.enhanced_db, params, agent_id);
    }

    /// Handle dependency analysis tool
    fn handleAnalyzeDependencies(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const params = try self.parseAnalyzeDependenciesParams(arguments);
        return EnhancedMCPTools.AnalyzeDependenciesTool.execute(&self.enhanced_db, params, agent_id);
    }

    /// Handle database statistics tool
    fn handleDatabaseStats(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const params = try self.parseDatabaseStatsParams(arguments);
        return EnhancedMCPTools.DatabaseStatsTool.execute(&self.enhanced_db, params, agent_id);
    }

    /// Legacy read_code tool for backward compatibility
    fn handleLegacyReadCode(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const include_history_value = arguments.object.get("include_history");
        const include_history = if (include_history_value) |v| v.bool else false;

        const history_limit_value = arguments.object.get("history_limit");
        const history_limit = if (history_limit_value) |v| @as(u32, @intCast(v.integer)) else 5;

        // Use enhanced version with basic parameters
        const enhanced_params = EnhancedMCPTools.ReadCodeEnhanced.InputSchema{
            .path = path,
            .include_history = include_history,
            .history_limit = history_limit,
            .include_semantic_context = false, // Disable for legacy compatibility
            .include_dependencies = false,
            .include_collaborative_context = false,
        };

        return EnhancedMCPTools.ReadCodeEnhanced.execute(&self.enhanced_db, enhanced_params, agent_id);
    }

    /// Legacy write_code tool for backward compatibility
    fn handleLegacyWriteCode(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const content_value = arguments.object.get("content") orelse return error.MissingContent;
        const content = content_value.string;

        const enhanced_params = EnhancedMCPTools.WriteCodeEnhanced.InputSchema{
            .path = path,
            .content = content,
            .enable_crdt_sync = false, // Disable for legacy compatibility
            .enable_semantic_indexing = true,
            .enable_dependency_tracking = true,
        };

        return EnhancedMCPTools.WriteCodeEnhanced.execute(&self.enhanced_db, enhanced_params, agent_id);
    }

    /// Legacy get_context tool for backward compatibility
    fn handleLegacyGetContext(self: *EnhancedMCPServer, arguments: std.json.Value, agent_id: []const u8) !std.json.Value {
        _ = arguments;
        const stats_params = EnhancedMCPTools.DatabaseStatsTool.InputSchema{
            .include_performance_metrics = true,
            .include_component_details = true,
        };

        return EnhancedMCPTools.DatabaseStatsTool.execute(&self.enhanced_db, stats_params, agent_id);
    }

    // Parameter parsing functions

    fn parseReadCodeEnhancedParams(self: *EnhancedMCPServer, arguments: std.json.Value) !EnhancedMCPTools.ReadCodeEnhanced.InputSchema {
        _ = self;
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        return EnhancedMCPTools.ReadCodeEnhanced.InputSchema{
            .path = path,
            .include_history = if (arguments.object.get("include_history")) |v| v.bool else null,
            .history_limit = if (arguments.object.get("history_limit")) |v| @as(u32, @intCast(v.integer)) else null,
            .include_semantic_context = if (arguments.object.get("include_semantic_context")) |v| v.bool else null,
            .include_dependencies = if (arguments.object.get("include_dependencies")) |v| v.bool else null,
            .include_collaborative_context = if (arguments.object.get("include_collaborative_context")) |v| v.bool else null,
            .dependency_depth = if (arguments.object.get("dependency_depth")) |v| @as(u32, @intCast(v.integer)) else null,
            .semantic_similarity_threshold = if (arguments.object.get("semantic_similarity_threshold")) |v| @as(f32, @floatCast(v.float)) else null,
        };
    }

    fn parseWriteCodeEnhancedParams(self: *EnhancedMCPServer, arguments: std.json.Value) !EnhancedMCPTools.WriteCodeEnhanced.InputSchema {
        _ = self;
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const content_value = arguments.object.get("content") orelse return error.MissingContent;
        const content = content_value.string;

        return EnhancedMCPTools.WriteCodeEnhanced.InputSchema{
            .path = path,
            .content = content,
            .enable_crdt_sync = if (arguments.object.get("enable_crdt_sync")) |v| v.bool else null,
            .enable_semantic_indexing = if (arguments.object.get("enable_semantic_indexing")) |v| v.bool else null,
            .enable_dependency_tracking = if (arguments.object.get("enable_dependency_tracking")) |v| v.bool else null,
            .conflict_resolution_strategy = if (arguments.object.get("conflict_resolution_strategy")) |v| v.string else null,
        };
    }

    fn parseSemanticSearchParams(self: *EnhancedMCPServer, arguments: std.json.Value) !EnhancedMCPTools.SemanticSearchTool.InputSchema {
        _ = self;
        const query_value = arguments.object.get("query") orelse return error.MissingQuery;
        const query = query_value.string;

        return EnhancedMCPTools.SemanticSearchTool.InputSchema{
            .query = query,
            .context_files = null, // TODO: Parse array if provided
            .max_results = if (arguments.object.get("max_results")) |v| @as(u32, @intCast(v.integer)) else null,
            .include_semantic = if (arguments.object.get("include_semantic")) |v| v.bool else null,
            .include_lexical = if (arguments.object.get("include_lexical")) |v| v.bool else null,
            .include_graph = if (arguments.object.get("include_graph")) |v| v.bool else null,
            .semantic_weight = if (arguments.object.get("semantic_weight")) |v| @as(f32, @floatCast(v.float)) else null,
            .lexical_weight = if (arguments.object.get("lexical_weight")) |v| @as(f32, @floatCast(v.float)) else null,
            .graph_weight = if (arguments.object.get("graph_weight")) |v| @as(f32, @floatCast(v.float)) else null,
        };
    }

    fn parseAnalyzeDependenciesParams(self: *EnhancedMCPServer, arguments: std.json.Value) !EnhancedMCPTools.AnalyzeDependenciesTool.InputSchema {
        _ = self;
        const file_path_value = arguments.object.get("file_path") orelse return error.MissingFilePath;
        const file_path = file_path_value.string;

        return EnhancedMCPTools.AnalyzeDependenciesTool.InputSchema{
            .file_path = file_path,
            .max_depth = if (arguments.object.get("max_depth")) |v| @as(u32, @intCast(v.integer)) else null,
            .direction = if (arguments.object.get("direction")) |v| v.string else null,
            .include_impact_analysis = if (arguments.object.get("include_impact_analysis")) |v| v.bool else null,
        };
    }

    fn parseDatabaseStatsParams(self: *EnhancedMCPServer, arguments: std.json.Value) !EnhancedMCPTools.DatabaseStatsTool.InputSchema {
        _ = self;
        return EnhancedMCPTools.DatabaseStatsTool.InputSchema{
            .include_performance_metrics = if (arguments.object.get("include_performance_metrics")) |v| v.bool else null,
            .include_component_details = if (arguments.object.get("include_component_details")) |v| v.bool else null,
        };
    }

    /// Determine operation type for metrics tracking
    fn getOperationType(self: *EnhancedMCPServer, tool_name: []const u8) MCPMetrics.OperationType {
        _ = self;
        if (std.mem.eql(u8, tool_name, EnhancedMCPTools.SemanticSearchTool.name)) {
            return .semantic_search;
        } else if (std.mem.eql(u8, tool_name, EnhancedMCPTools.AnalyzeDependenciesTool.name)) {
            return .dependency_analysis;
        } else if (std.mem.indexOf(u8, tool_name, "crdt") != null) {
            return .crdt_operation;
        } else {
            return .standard;
        }
    }

    /// Update agent activity timestamp and increment request count
    fn updateAgentActivity(self: *EnhancedMCPServer, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.agents.items) |*agent| {
            if (std.mem.eql(u8, agent.id, agent_id)) {
                agent.last_activity = std.time.timestamp();
                agent.requests_handled += 1;
                return;
            }
        }

        std.log.warn("Activity update for unknown enhanced agent: {s}", .{agent_id});
    }

    /// Add event callback for WebSocket broadcasting
    pub fn addEventCallback(self: *EnhancedMCPServer, callback: *const fn (event: []const u8) void) !void {
        try self.event_callbacks.append(callback);
    }

    /// Broadcast event to all registered callbacks
    fn broadcastEvent(self: *EnhancedMCPServer, event: []const u8) void {
        for (self.event_callbacks.items) |callback| {
            callback(event);
        }
    }

    /// Get enhanced server statistics
    pub fn getStats(self: *EnhancedMCPServer) struct {
        agents: u32,
        requests: u64,
        avg_response_ms: f64,
        semantic_searches: u64,
        dependency_analyses: u64,
        database: @import("enhanced_database.zig").DatabaseStats,
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        const db_stats = self.enhanced_db.getStats();

        return .{
            .agents = @as(u32, @intCast(self.agents.items.len)),
            .requests = self.metrics.total_requests,
            .avg_response_ms = self.metrics.getAverageResponseTime(),
            .semantic_searches = self.metrics.semantic_searches,
            .dependency_analyses = self.metrics.dependency_analyses,
            .database = db_stats,
        };
    }

    /// Get available tools list for MCP discovery
    pub fn getAvailableTools(self: *EnhancedMCPServer) []const ToolDefinition {
        _ = self;
        return &[_]ToolDefinition{
            .{
                .name = EnhancedMCPTools.ReadCodeEnhanced.name,
                .description = EnhancedMCPTools.ReadCodeEnhanced.description,
                .category = .enhanced,
            },
            .{
                .name = EnhancedMCPTools.WriteCodeEnhanced.name,
                .description = EnhancedMCPTools.WriteCodeEnhanced.description,
                .category = .enhanced,
            },
            .{
                .name = EnhancedMCPTools.SemanticSearchTool.name,
                .description = EnhancedMCPTools.SemanticSearchTool.description,
                .category = .advanced,
            },
            .{
                .name = EnhancedMCPTools.AnalyzeDependenciesTool.name,
                .description = EnhancedMCPTools.AnalyzeDependenciesTool.description,
                .category = .advanced,
            },
            .{
                .name = EnhancedMCPTools.DatabaseStatsTool.name,
                .description = EnhancedMCPTools.DatabaseStatsTool.description,
                .category = .system,
            },
            // Legacy tools for backward compatibility
            .{
                .name = "read_code",
                .description = "Read code files (legacy compatibility)",
                .category = .legacy,
            },
            .{
                .name = "write_code",
                .description = "Write code files (legacy compatibility)",
                .category = .legacy,
            },
            .{
                .name = "get_context",
                .description = "Get system context (legacy compatibility)",
                .category = .legacy,
            },
        };
    }

    const ToolDefinition = struct {
        name: []const u8,
        description: []const u8,
        category: ToolCategory,

        const ToolCategory = enum {
            enhanced,
            advanced,
            system,
            legacy,
        };
    };
};

// Unit Tests
test "EnhancedMCPServer initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in EnhancedMCPServer initialization test", .{});
        }
    }
    const allocator = gpa.allocator();

    const config = EnhancedDatabaseConfig{};
    var server = try EnhancedMCPServer.init(allocator, config);
    defer server.deinit();

    const stats = server.getStats();
    try testing.expect(stats.agents == 0);
    try testing.expect(stats.requests == 0);
    try testing.expect(stats.database.temporal_files == 0);
}

test "enhanced agent registration and management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in enhanced agent registration test", .{});
        }
    }
    const allocator = gpa.allocator();

    var test_arena = std.heap.ArenaAllocator.init(allocator);
    defer test_arena.deinit();
    const test_allocator = test_arena.allocator();

    const config = EnhancedDatabaseConfig{};
    var server = try EnhancedMCPServer.init(allocator, config);
    defer server.deinit();

    const agent_id = try test_allocator.dupe(u8, "enhanced-agent-1");
    const agent_name = try test_allocator.dupe(u8, "Enhanced Test Agent");
    const capabilities = [_][]const u8{ "read_code_enhanced", "semantic_search", "analyze_dependencies" };

    try server.registerAgent(agent_id, agent_name, &capabilities);

    var stats = server.getStats();
    try testing.expect(stats.agents == 1);

    server.unregisterAgent(agent_id);

    stats = server.getStats();
    try testing.expect(stats.agents == 0);
}

test "enhanced tool availability" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = EnhancedDatabaseConfig{};
    var server = try EnhancedMCPServer.init(allocator, config);
    defer server.deinit();

    const tools = server.getAvailableTools();

    // Should have enhanced tools plus legacy compatibility
    try testing.expect(tools.len >= 5);

    // Check that enhanced tools are available
    var found_enhanced = false;
    var found_semantic = false;
    var found_dependencies = false;

    for (tools) |tool| {
        if (std.mem.eql(u8, tool.name, EnhancedMCPTools.ReadCodeEnhanced.name)) {
            found_enhanced = true;
        } else if (std.mem.eql(u8, tool.name, EnhancedMCPTools.SemanticSearchTool.name)) {
            found_semantic = true;
        } else if (std.mem.eql(u8, tool.name, EnhancedMCPTools.AnalyzeDependenciesTool.name)) {
            found_dependencies = true;
        }
    }

    try testing.expect(found_enhanced);
    try testing.expect(found_semantic);
    try testing.expect(found_dependencies);
}
