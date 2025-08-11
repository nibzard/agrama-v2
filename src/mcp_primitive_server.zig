//! Primitive MCP Server - Revolutionary primitive-based AI memory interface
//!
//! This server exposes 5 core primitives instead of complex tools, enabling LLMs to
//! compose their own memory architectures and analysis pipelines on Agrama's
//! temporal knowledge graph database.
//!
//! Core Primitives:
//! 1. STORE: Universal storage with rich metadata and provenance tracking
//! 2. RETRIEVE: Data access with history and context
//! 3. SEARCH: Unified search across semantic/lexical/graph/temporal/hybrid modes
//! 4. LINK: Knowledge graph relationships with metadata
//! 5. TRANSFORM: Extensible operation registry for data transformation
//!
//! Target Performance: <1ms P50 latency for primitive operations
//! Protocol Compliance: Full MCP 2024-11-05 specification support
//! Agent Management: Session tracking, identity management, and observability

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const print = std.debug.print;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;

const PrimitiveEngine = @import("primitive_engine.zig").PrimitiveEngine;

/// MCP Protocol Version
pub const MCP_PROTOCOL_VERSION = "2024-11-05";

/// JSON-RPC 2.0 compliant request structure
pub const MCPRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,

    pub fn deinit(self: *MCPRequest, allocator: Allocator) void {
        allocator.free(self.method);
        // Note: id and params are owned by the parsed JSON
    }
};

/// JSON-RPC 2.0 compliant response structure
pub const MCPResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    result: ?std.json.Value = null,
    @"error": ?MCPError = null,

    pub fn deinit(self: *MCPResponse, allocator: Allocator) void {
        if (self.@"error") |*err| {
            err.deinit(allocator);
        }
    }
};

/// MCP Primitive Tool Definition (compliant with specification)
pub const MCPPrimitiveDefinition = struct {
    name: []const u8,
    title: []const u8,
    description: []const u8,
    inputSchema: std.json.Value,
    outputSchema: ?std.json.Value = null,
    performanceCharacteristics: []const u8,
    compositionExamples: []const []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *MCPPrimitiveDefinition, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.description);
        allocator.free(self.performanceCharacteristics);
        for (self.compositionExamples) |example| {
            allocator.free(example);
        }
        allocator.free(self.compositionExamples);
        self.arena.deinit();
    }
};

/// MCP Tool Response Content
pub const MCPContent = struct {
    type: []const u8, // "text", "image", "resource"
    text: ?[]const u8 = null,
    data: ?[]const u8 = null,
    mimeType: ?[]const u8 = null,

    pub fn deinit(self: *MCPContent, allocator: Allocator) void {
        allocator.free(self.type);
        if (self.text) |text| allocator.free(text);
        if (self.data) |data| allocator.free(data);
        if (self.mimeType) |mime| allocator.free(mime);
    }
};

/// MCP Tool Call Response
pub const MCPToolResponse = struct {
    content: []MCPContent,
    isError: bool = false,

    pub fn deinit(self: *MCPToolResponse, allocator: Allocator) void {
        for (self.content) |*content| {
            content.deinit(allocator);
        }
        allocator.free(self.content);
    }
};

/// JSON-RPC Error structure
pub const MCPError = struct {
    code: i32,
    message: []const u8,
    data: ?std.json.Value = null,

    pub fn deinit(self: *MCPError, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

/// Server Capabilities
pub const ServerCapabilities = struct {
    tools: ?struct {
        listChanged: bool = false,
    } = null,
    resources: ?struct {
        subscribe: bool = false,
        listChanged: bool = false,
    } = null,
    prompts: ?struct {
        listChanged: bool = false,
    } = null,
    logging: ?struct {} = null,
};

/// Agent Session Information
const AgentSession = struct {
    agent_id: []const u8,
    session_start: i64,
    operations_count: u32,
    last_activity: i64,
    primitives_used: HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage),

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

    pub fn init(allocator: Allocator, agent_id: []const u8) !AgentSession {
        return AgentSession{
            .agent_id = try allocator.dupe(u8, agent_id),
            .session_start = std.time.timestamp(),
            .operations_count = 0,
            .last_activity = std.time.timestamp(),
            .primitives_used = HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *AgentSession, allocator: Allocator) void {
        allocator.free(self.agent_id);
        var iter = self.primitives_used.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.primitives_used.deinit();
    }
};

/// Revolutionary Primitive MCP Server
pub const PrimitiveMCPServer = struct {
    allocator: Allocator,

    // Core primitive engine
    primitive_engine: PrimitiveEngine,

    // MCP protocol
    primitives: ArrayList(MCPPrimitiveDefinition),
    capabilities: ServerCapabilities,
    initialized: bool = false,
    protocol_version: []const u8,
    stdin_reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    stdout_writer: std.fs.File.Writer,

    // Agent session management
    agent_sessions: HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage),

    // Performance monitoring
    total_primitive_calls: u64 = 0,
    total_response_time_ns: u64 = 0,

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

    /// Initialize Primitive MCP Server with database connections
    pub fn init(allocator: Allocator, database: *Database, semantic_db: *SemanticDatabase, graph_engine: *TripleHybridSearchEngine) !PrimitiveMCPServer {
        // Initialize primitive engine with all components
        const primitive_engine = try PrimitiveEngine.init(allocator, database, semantic_db, graph_engine);

        var primitives = ArrayList(MCPPrimitiveDefinition).init(allocator);

        // Register the 5 core primitives
        try primitives.append(try createStorePrimitiveDefinition(allocator));
        try primitives.append(try createRetrievePrimitiveDefinition(allocator));
        try primitives.append(try createSearchPrimitiveDefinition(allocator));
        try primitives.append(try createLinkPrimitiveDefinition(allocator));
        try primitives.append(try createTransformPrimitiveDefinition(allocator));

        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut();

        return PrimitiveMCPServer{
            .allocator = allocator,
            .primitive_engine = primitive_engine,
            .primitives = primitives,
            .capabilities = ServerCapabilities{
                .tools = .{ .listChanged = false },
                .logging = .{},
            },
            .protocol_version = MCP_PROTOCOL_VERSION,
            .stdin_reader = std.io.bufferedReader(stdin.reader()),
            .stdout_writer = stdout.writer(),
            .agent_sessions = HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    /// Clean up server resources
    pub fn deinit(self: *PrimitiveMCPServer) void {
        // Clean up agent sessions
        var session_iterator = self.agent_sessions.iterator();
        while (session_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_session = entry.value_ptr.*;
            mut_session.deinit(self.allocator);
        }
        self.agent_sessions.deinit();

        // Clean up primitives
        for (self.primitives.items) |*primitive| {
            primitive.deinit(self.allocator);
        }
        self.primitives.deinit();

        // Clean up primitive engine
        self.primitive_engine.deinit();
    }

    /// Main server loop - processes stdin messages with <1ms response time
    pub fn run(self: *PrimitiveMCPServer) !void {
        const stderr = std.io.getStdErr().writer();
        const debug_mode = std.posix.getenv("AGRAMA_DEBUG") != null;

        if (debug_mode) {
            try stderr.print("[Primitive MCP Server] Starting primitive-based server (PID: {d})\n", .{std.os.linux.getpid()});
        }

        var line_buf: [8192]u8 = undefined;
        var message_count: u32 = 0;

        while (true) {
            if (self.stdin_reader.reader().readUntilDelimiterOrEof(line_buf[0..], '\n')) |line_result| {
                if (line_result) |line| {
                    if (line.len == 0) continue;

                    message_count += 1;

                    // High-performance message processing with error recovery
                    self.processMessage(line) catch |err| {
                        if (debug_mode) {
                            try stderr.print("[Primitive MCP Server] Error processing message #{d}: {any} - {s}\n", .{ message_count, err, line[0..@min(line.len, 100)] });
                        }
                    };

                    if (debug_mode and message_count % 100 == 0) {
                        const avg_response_ns = if (self.total_primitive_calls > 0)
                            self.total_response_time_ns / self.total_primitive_calls
                        else
                            0;

                        try stderr.print("[Primitive MCP Server] Processed {d} messages, avg response: {d:.2}ms\n", .{ message_count, @as(f64, @floatFromInt(avg_response_ns)) / 1_000_000.0 });
                    }
                } else {
                    if (debug_mode) {
                        try stderr.print("[Primitive MCP Server] Client disconnected gracefully after {d} messages\n", .{message_count});
                    }
                    break;
                }
            } else |err| {
                if (err == error.EndOfStream) {
                    if (debug_mode) {
                        try stderr.print("[Primitive MCP Server] Input stream closed after {d} messages\n", .{message_count});
                    }
                    break;
                }
                try stderr.print("[Primitive MCP Server] Critical stdin read error: {any} after {d} messages\n", .{ err, message_count });
                return err;
            }
        }

        if (debug_mode) {
            try stderr.print("[Primitive MCP Server] Server shutting down cleanly\n", .{});
        }
    }

    /// Process incoming JSON-RPC message with <1ms target latency
    fn processMessage(self: *PrimitiveMCPServer, message: []const u8) !void {
        var parse_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message, .{}) catch {
            try self.sendError(null, -32700, "Parse error", null);
            return;
        };
        defer parsed.deinit();

        const request = self.parseRequest(parsed.value) catch {
            try self.sendError(null, -32600, "Invalid Request", null);
            return;
        };

        const parse_time_ns = parse_timer.read();

        try self.handleRequest(request, parse_time_ns);
    }

    /// Parse JSON-RPC request efficiently
    fn parseRequest(self: *PrimitiveMCPServer, value: std.json.Value) !MCPRequest {
        const obj = value.object;

        const jsonrpc = obj.get("jsonrpc") orelse return error.MissingJsonRpc;
        if (!std.mem.eql(u8, jsonrpc.string, "2.0")) return error.InvalidJsonRpc;

        const method = obj.get("method") orelse return error.MissingMethod;

        return MCPRequest{
            .jsonrpc = "2.0",
            .id = obj.get("id"),
            .method = try self.allocator.dupe(u8, method.string),
            .params = obj.get("params"),
        };
    }

    /// Handle MCP request with performance tracking
    fn handleRequest(self: *PrimitiveMCPServer, request: MCPRequest, parse_time_ns: u64) !void {
        defer {
            var mut_request = request;
            mut_request.deinit(self.allocator);
        }

        var handle_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        if (std.mem.eql(u8, request.method, "initialize")) {
            try self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "initialized")) {
            try self.handleInitialized(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            try self.handleToolsList(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            const handle_time_ns = handle_timer.read();
            try self.handlePrimitiveCall(request, parse_time_ns + handle_time_ns);
        } else {
            try self.sendError(request.id, -32601, "Method not found", null);
        }
    }

    /// Handle initialize request
    fn handleInitialize(self: *PrimitiveMCPServer, request: MCPRequest) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        // Build capabilities response
        var capabilities = std.json.ObjectMap.init(json_allocator);
        var tools_capability = std.json.ObjectMap.init(json_allocator);
        try tools_capability.put("listChanged", std.json.Value{ .bool = false });
        try capabilities.put("tools", std.json.Value{ .object = tools_capability });

        // Build server info - emphasize primitive architecture
        var server_info = std.json.ObjectMap.init(json_allocator);
        try server_info.put("name", std.json.Value{ .string = "agrama-primitive-mcp" });
        try server_info.put("version", std.json.Value{ .string = "1.0.0-primitive" });
        try server_info.put("architecture", std.json.Value{ .string = "primitive-based" });
        try server_info.put("primitives_count", std.json.Value{ .integer = @as(i64, @intCast(self.primitives.items.len)) });

        // Build result
        var result = std.json.ObjectMap.init(json_allocator);
        try result.put("protocolVersion", std.json.Value{ .string = self.protocol_version });
        try result.put("capabilities", std.json.Value{ .object = capabilities });
        try result.put("serverInfo", std.json.Value{ .object = server_info });

        try self.sendResponse(request.id, std.json.Value{ .object = result });
    }

    /// Handle initialized notification
    fn handleInitialized(self: *PrimitiveMCPServer, request: MCPRequest) !void {
        _ = request;
        self.initialized = true;
    }

    /// Handle tools/list request - return primitive definitions
    fn handleToolsList(self: *PrimitiveMCPServer, request: MCPRequest) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        // Generate primitive tools list
        var tools_array = std.json.Array.init(json_allocator);

        for (self.primitives.items) |primitive| {
            var tool_obj = std.json.ObjectMap.init(json_allocator);

            try tool_obj.put("name", std.json.Value{ .string = try json_allocator.dupe(u8, primitive.name) });
            try tool_obj.put("title", std.json.Value{ .string = try json_allocator.dupe(u8, primitive.title) });
            try tool_obj.put("description", std.json.Value{ .string = try json_allocator.dupe(u8, primitive.description) });
            try tool_obj.put("inputSchema", primitive.inputSchema);

            if (primitive.outputSchema) |output_schema| {
                try tool_obj.put("outputSchema", output_schema);
            }

            // Add primitive-specific metadata
            try tool_obj.put("performance", std.json.Value{ .string = try json_allocator.dupe(u8, primitive.performanceCharacteristics) });

            var examples_array = std.json.Array.init(json_allocator);
            for (primitive.compositionExamples) |example| {
                try examples_array.append(std.json.Value{ .string = try json_allocator.dupe(u8, example) });
            }
            try tool_obj.put("compositionExamples", std.json.Value{ .array = examples_array });

            try tools_array.append(std.json.Value{ .object = tool_obj });
        }

        var result = std.json.ObjectMap.init(json_allocator);
        try result.put("tools", std.json.Value{ .array = tools_array });

        try self.sendResponse(request.id, std.json.Value{ .object = result });
    }

    /// Handle primitive call with <1ms target execution time
    fn handlePrimitiveCall(self: *PrimitiveMCPServer, request: MCPRequest, overhead_time_ns: u64) !void {
        var execution_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        const params = request.params orelse {
            try self.sendError(request.id, -32602, "Invalid params", null);
            return;
        };

        const params_obj = params.object;
        const tool_name = params_obj.get("name") orelse {
            try self.sendError(request.id, -32602, "Missing primitive name", null);
            return;
        };

        var default_args = std.json.ObjectMap.init(self.allocator);
        defer if (params_obj.get("arguments") == null) default_args.deinit();
        const arguments = params_obj.get("arguments") orelse std.json.Value{ .object = default_args };

        // Extract agent context if provided
        const agent_id = if (arguments.object.get("agent_id")) |val| val.string else "unknown-agent";

        // Execute primitive with performance tracking
        const primitive_result = self.primitive_engine.executePrimitive(tool_name.string, arguments, agent_id) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Primitive execution failed: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(request.id, -32000, error_msg, null);
            return;
        };

        const execution_time_ns = execution_timer.read();
        const total_time_ns = overhead_time_ns + execution_time_ns;

        // Update performance metrics
        self.total_primitive_calls += 1;
        self.total_response_time_ns += total_time_ns;

        // Update agent session
        try self.updateAgentSession(agent_id, tool_name.string);

        // Log slow operations (>1ms)
        if (total_time_ns > 1_000_000) {
            const stderr = std.io.getStdErr().writer();
            stderr.print("[Primitive MCP Server] Slow primitive: {s} took {d:.2}ms\n", .{ tool_name.string, @as(f64, @floatFromInt(total_time_ns)) / 1_000_000.0 }) catch {};
        }

        // Convert primitive result to MCP tool response
        const tool_response = try self.convertPrimitiveResult(primitive_result);
        defer {
            var mut_response = tool_response;
            mut_response.deinit(self.allocator);
        }

        // Send response with performance metadata
        try self.sendPrimitiveResponse(request.id, tool_response, total_time_ns);
    }

    /// Convert primitive result to MCP tool response format
    fn convertPrimitiveResult(self: *PrimitiveMCPServer, primitive_result: std.json.Value) !MCPToolResponse {
        // Serialize primitive result to string
        const result_text = try std.json.stringifyAlloc(self.allocator, primitive_result, .{ .whitespace = .indent_2 });

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = result_text,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Update agent session tracking
    pub fn updateAgentSession(self: *PrimitiveMCPServer, agent_id: []const u8, primitive_name: []const u8) !void {
        const now = std.time.timestamp();

        if (self.agent_sessions.getPtr(agent_id)) |session| {
            session.last_activity = now;
            session.operations_count += 1;

            // Update primitive usage count
            if (session.primitives_used.getPtr(primitive_name)) |count_ptr| {
                count_ptr.* += 1;
            } else {
                const owned_name = try self.allocator.dupe(u8, primitive_name);
                try session.primitives_used.put(owned_name, 1);
            }
        } else {
            var new_session = try AgentSession.init(self.allocator, agent_id);
            const owned_primitive_name = try self.allocator.dupe(u8, primitive_name);
            try new_session.primitives_used.put(owned_primitive_name, 1);
            new_session.operations_count = 1;
            new_session.last_activity = now;

            const owned_id = try self.allocator.dupe(u8, agent_id);
            try self.agent_sessions.put(owned_id, new_session);
        }
    }

    /// Send primitive response with performance metadata
    fn sendPrimitiveResponse(self: *PrimitiveMCPServer, id: ?std.json.Value, tool_response: MCPToolResponse, execution_time_ns: u64) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        const first_content = if (tool_response.content.len > 0) tool_response.content[0] else null;
        const text_content = if (first_content) |content| content.text orelse "No content" else "No content";

        // Build response with performance metadata
        var content_obj = std.json.ObjectMap.init(json_allocator);
        try content_obj.put("type", std.json.Value{ .string = "text" });
        try content_obj.put("text", std.json.Value{ .string = text_content });

        var content_array = std.json.Array.init(json_allocator);
        try content_array.append(std.json.Value{ .object = content_obj });

        // Add performance metadata
        var metadata_obj = std.json.ObjectMap.init(json_allocator);
        try metadata_obj.put("execution_time_ns", std.json.Value{ .integer = @as(i64, @intCast(execution_time_ns)) });
        try metadata_obj.put("execution_time_ms", std.json.Value{ .float = @as(f64, @floatFromInt(execution_time_ns)) / 1_000_000.0 });
        try metadata_obj.put("total_primitive_calls", std.json.Value{ .integer = @as(i64, @intCast(self.total_primitive_calls)) });
        try metadata_obj.put("avg_response_time_ms", std.json.Value{ .float = if (self.total_primitive_calls > 0) @as(f64, @floatFromInt(self.total_response_time_ns)) / @as(f64, @floatFromInt(self.total_primitive_calls)) / 1_000_000.0 else 0.0 });

        var result_obj = std.json.ObjectMap.init(json_allocator);
        try result_obj.put("content", std.json.Value{ .array = content_array });
        try result_obj.put("isError", std.json.Value{ .bool = tool_response.isError });
        try result_obj.put("metadata", std.json.Value{ .object = metadata_obj });

        const result_value = std.json.Value{ .object = result_obj };
        try self.sendResponse(id, result_value);
    }

    /// Send JSON-RPC response
    fn sendResponse(self: *PrimitiveMCPServer, id: ?std.json.Value, result: std.json.Value) !void {
        const response = MCPResponse{
            .id = id,
            .result = result,
        };

        try self.sendMessage(response);
    }

    /// Send JSON-RPC error
    fn sendError(self: *PrimitiveMCPServer, id: ?std.json.Value, code: i32, message: []const u8, data: ?std.json.Value) !void {
        const error_obj = MCPError{
            .code = code,
            .message = try self.allocator.dupe(u8, message),
            .data = data,
        };

        var response = MCPResponse{
            .id = id,
            .@"error" = error_obj,
        };

        try self.sendMessage(response);

        response.deinit(self.allocator);
    }

    /// Send message to stdout (stdio transport)
    fn sendMessage(self: *PrimitiveMCPServer, response: MCPResponse) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        var string = std.ArrayList(u8).init(json_allocator);

        // Manually construct JSON-RPC response for spec compliance
        try string.appendSlice("{\"jsonrpc\":\"2.0\"");

        // Add id if present
        if (response.id) |id| {
            try string.appendSlice(",\"id\":");
            try std.json.stringify(id, .{}, string.writer());
        }

        // Add EITHER result OR error (not both)
        if (response.@"error") |err| {
            try string.appendSlice(",\"error\":{\"code\":");
            try std.json.stringify(err.code, .{}, string.writer());
            try string.appendSlice(",\"message\":");
            try std.json.stringify(err.message, .{}, string.writer());
            if (err.data) |data| {
                try string.appendSlice(",\"data\":");
                try std.json.stringify(data, .{}, string.writer());
            }
            try string.appendSlice("}");
        } else if (response.result) |result| {
            try string.appendSlice(",\"result\":");
            try std.json.stringify(result, .{}, string.writer());
        }

        try string.appendSlice("}\n");

        try self.stdout_writer.writeAll(string.items);
    }

    /// Get comprehensive performance statistics
    pub fn getPerformanceStats(self: *PrimitiveMCPServer) !std.json.Value {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        var stats = std.json.ObjectMap.init(json_allocator);

        // Overall performance
        try stats.put("total_primitive_calls", std.json.Value{ .integer = @as(i64, @intCast(self.total_primitive_calls)) });

        const avg_response_time_ms = if (self.total_primitive_calls > 0)
            @as(f64, @floatFromInt(self.total_response_time_ns)) / @as(f64, @floatFromInt(self.total_primitive_calls)) / 1_000_000.0
        else
            0.0;
        try stats.put("avg_response_time_ms", std.json.Value{ .float = avg_response_time_ms });

        // Primitive engine stats
        const engine_stats = try self.primitive_engine.getPerformanceStats();
        try stats.put("primitive_engine", engine_stats);

        // Agent session stats
        var agent_stats = std.json.ObjectMap.init(json_allocator);
        try agent_stats.put("total_sessions", std.json.Value{ .integer = @as(i64, @intCast(self.agent_sessions.count())) });

        var active_sessions: i32 = 0;
        const now = std.time.timestamp();
        var session_iter = self.agent_sessions.iterator();
        while (session_iter.next()) |entry| {
            if (now - entry.value_ptr.last_activity < 300) { // Active within 5 minutes
                active_sessions += 1;
            }
        }
        try agent_stats.put("active_sessions", std.json.Value{ .integer = active_sessions });
        try stats.put("agent_sessions", std.json.Value{ .object = agent_stats });

        return std.json.Value{ .object = stats };
    }
};

// Primitive Definition Creators

/// Create STORE primitive definition with JSON schema
fn createStorePrimitiveDefinition(allocator: Allocator) !MCPPrimitiveDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    // Key property
    var key_schema = std.json.ObjectMap.init(json_allocator);
    try key_schema.put("type", std.json.Value{ .string = "string" });
    try key_schema.put("description", std.json.Value{ .string = "Unique identifier for stored data" });
    try key_schema.put("minLength", std.json.Value{ .integer = 1 });

    // Value property
    var value_schema = std.json.ObjectMap.init(json_allocator);
    try value_schema.put("type", std.json.Value{ .string = "string" });
    try value_schema.put("description", std.json.Value{ .string = "Data content to store" });

    // Metadata property
    var metadata_schema = std.json.ObjectMap.init(json_allocator);
    try metadata_schema.put("type", std.json.Value{ .string = "object" });
    try metadata_schema.put("description", std.json.Value{ .string = "Optional metadata for the stored data" });

    // Agent ID property
    var agent_id_schema = std.json.ObjectMap.init(json_allocator);
    try agent_id_schema.put("type", std.json.Value{ .string = "string" });
    try agent_id_schema.put("description", std.json.Value{ .string = "Agent identifier for provenance tracking" });
    try agent_id_schema.put("default", std.json.Value{ .string = "unknown" });

    try properties.put("key", std.json.Value{ .object = key_schema });
    try properties.put("value", std.json.Value{ .object = value_schema });
    try properties.put("metadata", std.json.Value{ .object = metadata_schema });
    try properties.put("agent_id", std.json.Value{ .object = agent_id_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "key" });
    try required.append(std.json.Value{ .string = "value" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    // Composition examples
    var examples = try allocator.alloc([]const u8, 3);
    examples[0] = try allocator.dupe(u8, "store('concept_v1', idea_text, {'confidence': 0.7, 'source': 'brainstorm'})");
    examples[1] = try allocator.dupe(u8, "store('function:calculateDistance', code, {'language': 'zig', 'complexity': 'O(1)'})");
    examples[2] = try allocator.dupe(u8, "store('decision:2024-01-01:arch', decision_doc, {'impact': 'high', 'stakeholders': ['team-a', 'team-b']})");

    return MCPPrimitiveDefinition{
        .name = try allocator.dupe(u8, "store"),
        .title = try allocator.dupe(u8, "Store Data"),
        .description = try allocator.dupe(u8, "Store data with rich metadata and provenance tracking. Automatically indexes content >50 chars for semantic search."),
        .inputSchema = std.json.Value{ .object = input_schema },
        .performanceCharacteristics = try allocator.dupe(u8, "Target <1ms P50 latency, automatic semantic indexing for content >50 chars"),
        .compositionExamples = examples,
        .arena = arena,
    };
}

/// Create RETRIEVE primitive definition with JSON schema
fn createRetrievePrimitiveDefinition(allocator: Allocator) !MCPPrimitiveDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    // Key property
    var key_schema = std.json.ObjectMap.init(json_allocator);
    try key_schema.put("type", std.json.Value{ .string = "string" });
    try key_schema.put("description", std.json.Value{ .string = "Unique identifier of data to retrieve" });

    // Include history property
    var history_schema = std.json.ObjectMap.init(json_allocator);
    try history_schema.put("type", std.json.Value{ .string = "boolean" });
    try history_schema.put("description", std.json.Value{ .string = "Include modification history" });
    try history_schema.put("default", std.json.Value{ .bool = false });

    try properties.put("key", std.json.Value{ .object = key_schema });
    try properties.put("include_history", std.json.Value{ .object = history_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "key" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    // Composition examples
    var examples = try allocator.alloc([]const u8, 2);
    examples[0] = try allocator.dupe(u8, "retrieve('concept_v1', {'include_history': true})");
    examples[1] = try allocator.dupe(u8, "retrieve('function:calculateDistance')");

    return MCPPrimitiveDefinition{
        .name = try allocator.dupe(u8, "retrieve"),
        .title = try allocator.dupe(u8, "Retrieve Data"),
        .description = try allocator.dupe(u8, "Retrieve data with full context and optional history. Returns existence, content, metadata, and temporal information."),
        .inputSchema = std.json.Value{ .object = input_schema },
        .performanceCharacteristics = try allocator.dupe(u8, "Target <1ms P50 latency, optional history adds ~2ms"),
        .compositionExamples = examples,
        .arena = arena,
    };
}

/// Create SEARCH primitive definition with JSON schema
fn createSearchPrimitiveDefinition(allocator: Allocator) !MCPPrimitiveDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    // Query property
    var query_schema = std.json.ObjectMap.init(json_allocator);
    try query_schema.put("type", std.json.Value{ .string = "string" });
    try query_schema.put("description", std.json.Value{ .string = "Search query text" });
    try query_schema.put("minLength", std.json.Value{ .integer = 1 });

    // Type property with enum
    var type_schema = std.json.ObjectMap.init(json_allocator);
    try type_schema.put("type", std.json.Value{ .string = "string" });
    try type_schema.put("description", std.json.Value{ .string = "Search type: semantic, lexical, graph, temporal, or hybrid" });
    var type_enum = std.json.Array.init(json_allocator);
    try type_enum.append(std.json.Value{ .string = "semantic" });
    try type_enum.append(std.json.Value{ .string = "lexical" });
    try type_enum.append(std.json.Value{ .string = "graph" });
    try type_enum.append(std.json.Value{ .string = "temporal" });
    try type_enum.append(std.json.Value{ .string = "hybrid" });
    try type_schema.put("enum", std.json.Value{ .array = type_enum });

    // Options property
    var options_schema = std.json.ObjectMap.init(json_allocator);
    try options_schema.put("type", std.json.Value{ .string = "object" });
    try options_schema.put("description", std.json.Value{ .string = "Search options (max_results, threshold, weights, etc.)" });

    try properties.put("query", std.json.Value{ .object = query_schema });
    try properties.put("type", std.json.Value{ .object = type_schema });
    try properties.put("options", std.json.Value{ .object = options_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "query" });
    try required.append(std.json.Value{ .string = "type" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    // Composition examples
    var examples = try allocator.alloc([]const u8, 3);
    examples[0] = try allocator.dupe(u8, "search('authentication code', 'hybrid', {'weights': {'semantic': 0.6, 'lexical': 0.4}})");
    examples[1] = try allocator.dupe(u8, "search('error handling', 'semantic', {'threshold': 0.8})");
    examples[2] = try allocator.dupe(u8, "search('memory leak', 'lexical', {'max_results': 15})");

    return MCPPrimitiveDefinition{
        .name = try allocator.dupe(u8, "search"),
        .title = try allocator.dupe(u8, "Unified Search"),
        .description = try allocator.dupe(u8, "Unified search across semantic, lexical, graph, temporal, and hybrid indices. Combines multiple search modalities for comprehensive results."),
        .inputSchema = std.json.Value{ .object = input_schema },
        .performanceCharacteristics = try allocator.dupe(u8, "Target <5ms P50 latency, hybrid search combines all modalities"),
        .compositionExamples = examples,
        .arena = arena,
    };
}

/// Create LINK primitive definition with JSON schema
fn createLinkPrimitiveDefinition(allocator: Allocator) !MCPPrimitiveDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    // From property
    var from_schema = std.json.ObjectMap.init(json_allocator);
    try from_schema.put("type", std.json.Value{ .string = "string" });
    try from_schema.put("description", std.json.Value{ .string = "Source entity identifier" });

    // To property
    var to_schema = std.json.ObjectMap.init(json_allocator);
    try to_schema.put("type", std.json.Value{ .string = "string" });
    try to_schema.put("description", std.json.Value{ .string = "Target entity identifier" });

    // Relation property
    var relation_schema = std.json.ObjectMap.init(json_allocator);
    try relation_schema.put("type", std.json.Value{ .string = "string" });
    try relation_schema.put("description", std.json.Value{ .string = "Relationship type (depends_on, evolved_into, similar_to, etc.)" });

    // Metadata property
    var metadata_schema = std.json.ObjectMap.init(json_allocator);
    try metadata_schema.put("type", std.json.Value{ .string = "object" });
    try metadata_schema.put("description", std.json.Value{ .string = "Optional relationship metadata" });

    try properties.put("from", std.json.Value{ .object = from_schema });
    try properties.put("to", std.json.Value{ .object = to_schema });
    try properties.put("relation", std.json.Value{ .object = relation_schema });
    try properties.put("metadata", std.json.Value{ .object = metadata_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "from" });
    try required.append(std.json.Value{ .string = "to" });
    try required.append(std.json.Value{ .string = "relation" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    // Composition examples
    var examples = try allocator.alloc([]const u8, 2);
    examples[0] = try allocator.dupe(u8, "link('module_a', 'module_b', 'depends_on', {'strength': 0.8})");
    examples[1] = try allocator.dupe(u8, "link('concept_v1', 'concept_v2', 'evolved_into')");

    return MCPPrimitiveDefinition{
        .name = try allocator.dupe(u8, "link"),
        .title = try allocator.dupe(u8, "Create Link"),
        .description = try allocator.dupe(u8, "Create relationships in knowledge graph with rich metadata. Enables graph traversal and dependency analysis."),
        .inputSchema = std.json.Value{ .object = input_schema },
        .performanceCharacteristics = try allocator.dupe(u8, "Target <1ms P50 latency, creates bidirectional graph relationships"),
        .compositionExamples = examples,
        .arena = arena,
    };
}

/// Create TRANSFORM primitive definition with JSON schema
fn createTransformPrimitiveDefinition(allocator: Allocator) !MCPPrimitiveDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    // Operation property with enum
    var operation_schema = std.json.ObjectMap.init(json_allocator);
    try operation_schema.put("type", std.json.Value{ .string = "string" });
    try operation_schema.put("description", std.json.Value{ .string = "Transform operation to apply" });
    var operation_enum = std.json.Array.init(json_allocator);
    try operation_enum.append(std.json.Value{ .string = "parse_functions" });
    try operation_enum.append(std.json.Value{ .string = "extract_imports" });
    try operation_enum.append(std.json.Value{ .string = "generate_summary" });
    try operation_enum.append(std.json.Value{ .string = "compress_text" });
    try operation_enum.append(std.json.Value{ .string = "diff_content" });
    try operation_enum.append(std.json.Value{ .string = "merge_content" });
    try operation_enum.append(std.json.Value{ .string = "analyze_complexity" });
    try operation_enum.append(std.json.Value{ .string = "extract_dependencies" });
    try operation_enum.append(std.json.Value{ .string = "validate_syntax" });
    try operation_schema.put("enum", std.json.Value{ .array = operation_enum });

    // Data property
    var data_schema = std.json.ObjectMap.init(json_allocator);
    try data_schema.put("type", std.json.Value{ .string = "string" });
    try data_schema.put("description", std.json.Value{ .string = "Input data to transform" });

    // Options property
    var options_schema = std.json.ObjectMap.init(json_allocator);
    try options_schema.put("type", std.json.Value{ .string = "object" });
    try options_schema.put("description", std.json.Value{ .string = "Transform-specific options" });

    try properties.put("operation", std.json.Value{ .object = operation_schema });
    try properties.put("data", std.json.Value{ .object = data_schema });
    try properties.put("options", std.json.Value{ .object = options_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "operation" });
    try required.append(std.json.Value{ .string = "data" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    // Composition examples
    var examples = try allocator.alloc([]const u8, 2);
    examples[0] = try allocator.dupe(u8, "transform('parse_functions', code_content, {'language': 'zig'})");
    examples[1] = try allocator.dupe(u8, "transform('extract_dependencies', module_content)");

    return MCPPrimitiveDefinition{
        .name = try allocator.dupe(u8, "transform"),
        .title = try allocator.dupe(u8, "Transform Data"),
        .description = try allocator.dupe(u8, "Apply extensible operations to transform data. Operations are composable and can be chained for complex analysis pipelines."),
        .inputSchema = std.json.Value{ .object = input_schema },
        .performanceCharacteristics = try allocator.dupe(u8, "Varies by operation, most <5ms, some may take longer for complex parsing"),
        .compositionExamples = examples,
        .arena = arena,
    };
}

// Unit Tests
test "PrimitiveMCPServer initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in PrimitiveMCPServer init test", .{});
        }
    }
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var server = try PrimitiveMCPServer.init(allocator, &database, &semantic_db, &graph_engine);
    defer server.deinit();

    // Should have registered 5 core primitives
    try testing.expect(server.primitives.items.len == 5);
    try testing.expect(server.total_primitive_calls == 0);
    try testing.expectEqualSlices(u8, server.protocol_version, MCP_PROTOCOL_VERSION);

    // Check primitive names
    var found_store = false;
    var found_retrieve = false;
    var found_search = false;
    var found_link = false;
    var found_transform = false;

    for (server.primitives.items) |primitive| {
        if (std.mem.eql(u8, primitive.name, "store")) found_store = true;
        if (std.mem.eql(u8, primitive.name, "retrieve")) found_retrieve = true;
        if (std.mem.eql(u8, primitive.name, "search")) found_search = true;
        if (std.mem.eql(u8, primitive.name, "link")) found_link = true;
        if (std.mem.eql(u8, primitive.name, "transform")) found_transform = true;
    }

    try testing.expect(found_store and found_retrieve and found_search and found_link and found_transform);
}

test "PrimitiveMCPServer agent session management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in agent session test", .{});
        }
    }
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var server = try PrimitiveMCPServer.init(allocator, &database, &semantic_db, &graph_engine);
    defer server.deinit();

    // Test agent session tracking
    try server.updateAgentSession("test-agent-1", "store");
    try server.updateAgentSession("test-agent-1", "retrieve");
    try server.updateAgentSession("test-agent-2", "search");

    try testing.expect(server.agent_sessions.count() == 2);

    if (server.agent_sessions.get("test-agent-1")) |session| {
        try testing.expect(session.operations_count == 2);
        try testing.expect(session.primitives_used.count() == 2);
    }

    if (server.agent_sessions.get("test-agent-2")) |session| {
        try testing.expect(session.operations_count == 1);
        try testing.expect(session.primitives_used.count() == 1);
    }
}

test "primitive definition creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in primitive definition test", .{});
        }
    }
    const allocator = gpa.allocator();

    var store_def = try createStorePrimitiveDefinition(allocator);
    defer store_def.deinit(allocator);

    try testing.expectEqualSlices(u8, store_def.name, "store");
    try testing.expectEqualSlices(u8, store_def.title, "Store Data");
    try testing.expect(store_def.inputSchema.object.get("type") != null);
    try testing.expect(store_def.compositionExamples.len == 3);
}
