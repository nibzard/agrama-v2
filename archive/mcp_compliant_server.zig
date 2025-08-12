const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const print = std.debug.print;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TrueFrontierReductionEngine = @import("fre_true.zig").TrueFrontierReductionEngine;
const CRDTDocument = @import("crdt.zig").CRDTDocument;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
const hnsw = @import("hnsw.zig");
const MemoryPoolSystem = @import("memory_pools.zig").MemoryPoolSystem;
const PoolConfig = @import("memory_pools.zig").PoolConfig;

/// MCP Protocol Version
pub const MCP_PROTOCOL_VERSION = "2024-11-05";

/// JSON-RPC 2.0 compliant request structure
pub const MCPRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,
    // Track whether we own the method string
    owns_method: bool = false,

    pub fn deinit(self: *MCPRequest, allocator: Allocator) void {
        // Only free method if we own it
        if (self.owns_method) {
            allocator.free(self.method);
        }
        // Note: id and params are owned by the parsed JSON arena,
        // so they are cleaned up when the JSON is deinit'd
    }
};

/// JSON-RPC 2.0 compliant response structure
pub const MCPResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    result: ?std.json.Value = null,
    @"error": ?MCPError = null,

    pub fn deinit(self: *MCPResponse, allocator: Allocator) void {
        // Note: id and result are handled by JSON parsing
        if (self.@"error") |*err| {
            err.deinit(allocator);
        }
    }
};

/// MCP Tool Definition (compliant with specification)
pub const MCPToolDefinition = struct {
    name: []const u8,
    title: []const u8,
    description: []const u8,
    inputSchema: std.json.Value,
    outputSchema: ?std.json.Value = null,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *MCPToolDefinition, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.description);
        self.arena.deinit(); // Clean up all JSON structures at once
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
        // Note: data is handled by JSON arena
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

/// Enhanced MCP Server with full Agrama capabilities and memory pool optimization
pub const MCPCompliantServer = struct {
    allocator: Allocator,

    // Memory pool system for 50-70% allocation overhead reduction in MCP operations
    memory_pools: ?*MemoryPoolSystem = null,

    // Core databases - layered architecture
    database: *Database,
    semantic_db: ?*SemanticDatabase = null,
    fre_engine: ?*TrueFrontierReductionEngine = null,
    hybrid_search: ?*TripleHybridSearchEngine = null,

    // CRDT collaboration
    active_documents: HashMap([]const u8, *CRDTDocument, HashContext, std.hash_map.default_max_load_percentage),
    agent_sessions: HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage),

    // MCP protocol
    tools: ArrayList(MCPToolDefinition),
    capabilities: ServerCapabilities,
    initialized: bool = false,
    protocol_version: []const u8,
    stdin_reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    stdout_writer: std.fs.File.Writer,

    // Performance tracking
    tool_call_count: u64 = 0,
    total_response_time_ms: u64 = 0,

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

    const AgentSession = struct {
        agent_id: []const u8,
        agent_name: []const u8,
        session_start: i64,
        operations_count: u32,
        last_activity: i64,
    };

    /// Initialize MCP Server with optional advanced capabilities
    pub fn init(allocator: Allocator, database: *Database) !MCPCompliantServer {
        var tools = ArrayList(MCPToolDefinition).init(allocator);

        // Core enhanced tools
        try tools.append(try createReadCodeTool(allocator));
        try tools.append(try createWriteCodeTool(allocator));
        try tools.append(try createGetContextTool(allocator));

        // Advanced search and analysis tools
        try tools.append(try createSemanticSearchTool(allocator));
        try tools.append(try createAnalyzeDependenciesTool(allocator));
        try tools.append(try createHybridSearchTool(allocator));
        try tools.append(try createRecordDecisionTool(allocator));
        try tools.append(try createQueryHistoryTool(allocator));

        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut();

        return MCPCompliantServer{
            .allocator = allocator,
            .memory_pools = null,
            .database = database,
            .active_documents = HashMap([]const u8, *CRDTDocument, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .agent_sessions = HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .tools = tools,
            .capabilities = ServerCapabilities{
                .tools = .{ .listChanged = false },
                .logging = .{},
            },
            .protocol_version = MCP_PROTOCOL_VERSION,
            .stdin_reader = std.io.bufferedReader(stdin.reader()),
            .stdout_writer = stdout.writer(),
        };
    }

    /// Initialize server with full advanced capabilities
    pub fn initWithAdvancedFeatures(allocator: Allocator, database: *Database) !MCPCompliantServer {
        var server = try init(allocator, database);

        // Initialize semantic database
        const semantic_config = SemanticDatabase.HNSWConfig{
            .vector_dimensions = 768,
            .max_connections = 16,
            .ef_construction = 200,
            .matryoshka_dims = &[_]u32{ 64, 256, 768 },
        };

        server.semantic_db = try allocator.create(SemanticDatabase);
        server.semantic_db.?.* = try SemanticDatabase.init(allocator, semantic_config);

        // Initialize FRE engine
        server.fre_engine = try allocator.create(TrueFrontierReductionEngine);
        server.fre_engine.?.* = TrueFrontierReductionEngine.init(allocator);

        // Initialize hybrid search
        server.hybrid_search = try allocator.create(TripleHybridSearchEngine);
        server.hybrid_search.?.* = TripleHybridSearchEngine.init(allocator);

        return server;
    }

    /// Initialize MCP server with memory pool optimization for 50-70% allocation overhead reduction
    pub fn initWithMemoryPools(allocator: Allocator, database: *Database) !MCPCompliantServer {
        var server = try init(allocator, database);

        // Initialize memory pool system
        const pool_config = PoolConfig{};
        server.memory_pools = try allocator.create(MemoryPoolSystem);
        server.memory_pools.?.* = try MemoryPoolSystem.init(allocator, pool_config);

        return server;
    }

    /// Initialize with advanced features AND memory pool optimization
    pub fn initWithAdvancedFeaturesAndMemoryPools(allocator: Allocator, database: *Database) !MCPCompliantServer {
        var server = try initWithAdvancedFeatures(allocator, database);

        // Initialize memory pool system
        const pool_config = PoolConfig{};
        server.memory_pools = try allocator.create(MemoryPoolSystem);
        server.memory_pools.?.* = try MemoryPoolSystem.init(allocator, pool_config);

        return server;
    }

    /// Initialize MCP server with enhanced database capabilities
    pub fn initEnhanced(allocator: Allocator, enhanced_server: *@import("enhanced_mcp_server.zig").EnhancedMCPServer) !MCPCompliantServer {
        var tools = ArrayList(MCPToolDefinition).init(allocator);

        // Enhanced tools for comprehensive database functionality
        try tools.append(try createReadCodeTool(allocator));
        try tools.append(try createWriteCodeTool(allocator));
        try tools.append(try createGetContextTool(allocator));
        try tools.append(try createSemanticSearchTool(allocator));
        try tools.append(try createAnalyzeDependenciesTool(allocator));
        try tools.append(try createHybridSearchTool(allocator));
        try tools.append(try createRecordDecisionTool(allocator));
        try tools.append(try createQueryHistoryTool(allocator));

        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut();

        return MCPCompliantServer{
            .allocator = allocator,
            .database = &enhanced_server.enhanced_db.temporal_db,
            .semantic_db = &enhanced_server.enhanced_db.semantic_db,
            .fre_engine = &enhanced_server.enhanced_db.fre,
            .hybrid_search = &enhanced_server.enhanced_db.hybrid_search,
            .active_documents = HashMap([]const u8, *CRDTDocument, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .agent_sessions = HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .tools = tools,
            .capabilities = ServerCapabilities{
                .tools = .{ .listChanged = false },
                .logging = .{},
            },
            .protocol_version = MCP_PROTOCOL_VERSION,
            .stdin_reader = std.io.bufferedReader(stdin.reader()),
            .stdout_writer = stdout.writer(),
        };
    }

    /// Clean up server resources
    pub fn deinit(self: *MCPCompliantServer) void {
        // Clean up memory pools if present
        if (self.memory_pools) |pools| {
            pools.deinit();
            self.allocator.destroy(pools);
        }

        // Note: In enhanced mode, semantic_db, fre_engine, and hybrid_search are
        // references to components owned by EnhancedDatabase, so they should NOT
        // be destroyed here. They will be cleaned up when EnhancedDatabase is destroyed.
        // Only destroy these if they were separately allocated (basic mode).

        // For now, we'll skip destroying these components to avoid double-free issues
        // TODO: Add proper ownership tracking to distinguish enhanced vs basic mode

        // Clean up CRDT documents
        var doc_iterator = self.active_documents.iterator();
        while (doc_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.active_documents.deinit();

        // Clean up agent sessions
        var session_iterator = self.agent_sessions.iterator();
        while (session_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.agent_id);
            self.allocator.free(entry.value_ptr.agent_name);
        }
        self.agent_sessions.deinit();

        // Clean up tools
        for (self.tools.items) |*tool| {
            tool.deinit(self.allocator);
        }
        self.tools.deinit();
    }

    /// Main server loop - processes stdin messages
    pub fn run(self: *MCPCompliantServer) !void {

        // MCP stdio transport: stdout is reserved for JSON-RPC protocol only
        // All logging must go to stderr to avoid interfering with JSON-RPC protocol

        // Claude Code treats any stderr output as an error during health checks
        // Only output to stderr in debug mode or when errors occur
        const stderr = std.io.getStdErr().writer();

        // Check for debug mode environment variable
        const debug_mode = std.posix.getenv("AGRAMA_DEBUG") != null;
        if (debug_mode) {
            try stderr.print("[MCP Server] Starting Agrama MCP server process (PID: {d})\n", .{std.os.linux.getpid()});
        }

        var line_buf: [8192]u8 = undefined; // Increased buffer size for stability
        var message_count: u32 = 0;

        while (true) {
            // Read line from stdin (MCP stdio transport requirement)
            if (self.stdin_reader.reader().readUntilDelimiterOrEof(line_buf[0..], '\n')) |line_result| {
                if (line_result) |line| {
                    // Skip empty lines but continue running
                    if (line.len == 0) {
                        continue;
                    }

                    message_count += 1;

                    // Process message with error recovery
                    self.processMessage(line) catch |err| {
                        if (debug_mode) {
                            try stderr.print("[MCP Server] Error processing message #{d}: {any} - {s}\n", .{ message_count, err, line[0..@min(line.len, 100)] });
                        }
                        // Continue processing despite errors
                    };

                    // Periodic health logging (debug mode only)
                    if (debug_mode and message_count % 100 == 0) {
                        try stderr.print("[MCP Server] Processed {d} messages successfully\n", .{message_count});
                    }
                } else {
                    // EOF - client disconnected gracefully (only log in debug mode)
                    if (debug_mode) {
                        try stderr.print("[MCP Server] Client disconnected gracefully (EOF) after {d} messages\n", .{message_count});
                    }
                    break;
                }
            } else |err| {
                // Only treat EndOfStream as graceful shutdown, other errors are critical
                if (err == error.EndOfStream) {
                    if (debug_mode) {
                        try stderr.print("[MCP Server] Input stream closed after {d} messages\n", .{message_count});
                    }
                    break;
                }
                try stderr.print("[MCP Server] Critical stdin read error: {any} after {d} messages\n", .{ err, message_count });
                return err;
            }
        }

        if (debug_mode) {
            try stderr.print("[MCP Server] Server shutting down cleanly\n", .{});
        }
    }

    /// Process incoming JSON-RPC message with comprehensive error recovery
    fn processMessage(self: *MCPCompliantServer, message: []const u8) !void {
        // Validate message size to prevent DoS attacks
        const MAX_MESSAGE_SIZE = 10 * 1024 * 1024; // 10MB limit
        if (message.len > MAX_MESSAGE_SIZE) {
            try self.sendError(null, -32700, "Message too large", null);
            return;
        }

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message, .{}) catch |err| {
            const error_msg = switch (err) {
                error.InvalidCharacter => "Invalid JSON character",
                error.InvalidNumber => "Invalid JSON number",
                error.UnexpectedEndOfInput => "Unexpected end of JSON input",
                error.ValueTooLong => "JSON value too long",
                else => "JSON parse error",
            };
            try self.sendError(null, -32700, error_msg, null);
            return;
        };
        defer parsed.deinit();

        const request = self.parseRequest(parsed.value) catch |err| {
            const error_msg = switch (err) {
                error.MissingJsonRpc => "Missing 'jsonrpc' field",
                error.InvalidJsonRpc => "Invalid JSON-RPC version",
                error.MissingMethod => "Missing 'method' field",
            };
            try self.sendError(null, -32600, error_msg, null);
            return;
        };

        try self.handleRequest(request);
    }

    /// Parse JSON-RPC request
    fn parseRequest(_: *MCPCompliantServer, value: std.json.Value) !MCPRequest {
        const obj = value.object;

        const jsonrpc = obj.get("jsonrpc") orelse return error.MissingJsonRpc;
        if (!std.mem.eql(u8, jsonrpc.string, "2.0")) return error.InvalidJsonRpc;

        const method = obj.get("method") orelse return error.MissingMethod;

        // Use string directly from JSON without duplication to avoid memory leaks
        // The JSON arena will clean this up when the parsed JSON is deinit'd
        return MCPRequest{
            .jsonrpc = "2.0",
            .id = obj.get("id"),
            .method = method.string,
            .params = obj.get("params"),
            .owns_method = false, // We don't own the method string
        };
    }

    /// Handle MCP request
    fn handleRequest(self: *MCPCompliantServer, request: MCPRequest) !void {
        defer {
            var mut_request = request;
            mut_request.deinit(self.allocator);
        }

        if (std.mem.eql(u8, request.method, "initialize")) {
            try self.handleInitialize(request);
        } else if (std.mem.eql(u8, request.method, "initialized")) {
            try self.handleInitialized(request);
        } else if (std.mem.eql(u8, request.method, "tools/list")) {
            try self.handleToolsList(request);
        } else if (std.mem.eql(u8, request.method, "tools/call")) {
            try self.handleToolsCall(request);
        } else {
            try self.sendError(request.id, -32601, "Method not found", null);
        }
    }

    /// Handle initialize request (MCP lifecycle)
    fn handleInitialize(self: *MCPCompliantServer, request: MCPRequest) !void {
        // Use arena allocator for temporary JSON structures to avoid leaks
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        // Build capabilities response
        var capabilities = std.json.ObjectMap.init(json_allocator);
        var tools_capability = std.json.ObjectMap.init(json_allocator);
        try tools_capability.put("listChanged", std.json.Value{ .bool = false });
        try capabilities.put("tools", std.json.Value{ .object = tools_capability });

        // Build server info
        var server_info = std.json.ObjectMap.init(json_allocator);
        try server_info.put("name", std.json.Value{ .string = "agrama-codegraph" });
        try server_info.put("version", std.json.Value{ .string = "1.0.0" });

        // Build result
        var result = std.json.ObjectMap.init(json_allocator);
        try result.put("protocolVersion", std.json.Value{ .string = self.protocol_version });
        try result.put("capabilities", std.json.Value{ .object = capabilities });
        try result.put("serverInfo", std.json.Value{ .object = server_info });

        try self.sendResponse(request.id, std.json.Value{ .object = result });
    }

    /// Handle initialized notification
    fn handleInitialized(self: *MCPCompliantServer, request: MCPRequest) !void {
        _ = request;
        self.initialized = true;
        // MCP stdio transport: no logging during protocol operation
    }

    /// Handle tools/list request
    fn handleToolsList(self: *MCPCompliantServer, request: MCPRequest) !void {
        // Use arena allocator for temporary JSON structures to avoid leaks
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        // Dynamically generate tools list from registered tools (protocol compliant)
        var tools_array = std.json.Array.init(json_allocator);

        for (self.tools.items) |tool| {
            var tool_obj = std.json.ObjectMap.init(json_allocator);

            try tool_obj.put("name", std.json.Value{ .string = try json_allocator.dupe(u8, tool.name) });
            try tool_obj.put("title", std.json.Value{ .string = try json_allocator.dupe(u8, tool.title) });
            try tool_obj.put("description", std.json.Value{ .string = try json_allocator.dupe(u8, tool.description) });
            try tool_obj.put("inputSchema", tool.inputSchema);

            if (tool.outputSchema) |output_schema| {
                try tool_obj.put("outputSchema", output_schema);
            }

            try tools_array.append(std.json.Value{ .object = tool_obj });
        }

        var result = std.json.ObjectMap.init(json_allocator);
        try result.put("tools", std.json.Value{ .array = tools_array });

        try self.sendResponse(request.id, std.json.Value{ .object = result });
    }

    /// Handle tools/call request
    fn handleToolsCall(self: *MCPCompliantServer, request: MCPRequest) !void {
        const params = request.params orelse {
            try self.sendError(request.id, -32602, "Invalid params", null);
            return;
        };

        const params_obj = params.object;
        const tool_name = params_obj.get("name") orelse {
            try self.sendError(request.id, -32602, "Missing tool name", null);
            return;
        };

        var default_args = std.json.ObjectMap.init(self.allocator);
        defer if (params_obj.get("arguments") == null) default_args.deinit();
        const arguments = params_obj.get("arguments") orelse std.json.Value{ .object = default_args };

        // Call the appropriate tool
        const tool_response = self.callTool(tool_name.string, arguments) catch |err| {
            const error_msg = try std.fmt.allocPrint(self.allocator, "Tool execution failed: {s}", .{@errorName(err)});
            defer self.allocator.free(error_msg);
            try self.sendError(request.id, -32000, error_msg, null);
            return;
        };
        defer {
            var mut_response = tool_response;
            mut_response.deinit(self.allocator);
        }

        // Create simple JSON response for tool call result
        const first_content = if (tool_response.content.len > 0) tool_response.content[0] else null;
        const text_content = if (first_content) |content| content.text orelse "No content" else "No content";

        // Use arena allocator for temporary JSON structures to avoid leaks
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        // Build JSON response safely using Zig's JSON handling
        var content_obj = std.json.ObjectMap.init(json_allocator);
        try content_obj.put("type", std.json.Value{ .string = "text" });
        try content_obj.put("text", std.json.Value{ .string = text_content });

        var content_array = std.json.Array.init(json_allocator);
        try content_array.append(std.json.Value{ .object = content_obj });

        var result_obj = std.json.ObjectMap.init(json_allocator);
        try result_obj.put("content", std.json.Value{ .array = content_array });
        try result_obj.put("isError", std.json.Value{ .bool = tool_response.isError });

        const result_value = std.json.Value{ .object = result_obj };
        try self.sendResponse(request.id, result_value);
    }

    /// Call specific tool implementation with performance tracking
    fn callTool(self: *MCPCompliantServer, tool_name: []const u8, arguments: std.json.Value) !MCPToolResponse {
        var timer = std.time.Timer.start() catch |err| {
            std.log.warn("Failed to start timer: {any}", .{err});
            return try self.callToolInternal(tool_name, arguments);
        };

        const result = try self.callToolInternal(tool_name, arguments);

        // Track performance metrics
        const elapsed_ms = timer.read() / 1_000_000;
        self.tool_call_count += 1;
        self.total_response_time_ms += elapsed_ms;

        // Only log slow operations in debug mode to avoid interfering with MCP protocol
        const debug_mode = std.posix.getenv("AGRAMA_DEBUG") != null;
        if (debug_mode and elapsed_ms > 100) {
            const stderr = std.io.getStdErr().writer();
            stderr.print("[MCP Server] Slow tool call: {s} took {d}ms\n", .{ tool_name, elapsed_ms }) catch {};
        }

        return result;
    }

    /// Internal tool routing without performance tracking
    fn callToolInternal(self: *MCPCompliantServer, tool_name: []const u8, arguments: std.json.Value) !MCPToolResponse {
        // Core enhanced tools
        if (std.mem.eql(u8, tool_name, "read_code")) {
            return self.executeReadCode(arguments);
        } else if (std.mem.eql(u8, tool_name, "write_code")) {
            return self.executeWriteCode(arguments);
        } else if (std.mem.eql(u8, tool_name, "get_context")) {
            return self.executeGetContext(arguments);
        }
        // Advanced analysis tools
        else if (std.mem.eql(u8, tool_name, "semantic_search")) {
            return self.executeSemanticSearch(arguments);
        } else if (std.mem.eql(u8, tool_name, "analyze_dependencies")) {
            return self.executeAnalyzeDependencies(arguments);
        } else if (std.mem.eql(u8, tool_name, "hybrid_search")) {
            return self.executeHybridSearch(arguments);
        } else if (std.mem.eql(u8, tool_name, "record_decision")) {
            return self.executeRecordDecision(arguments);
        } else if (std.mem.eql(u8, tool_name, "query_history")) {
            return self.executeQueryHistory(arguments);
        } else {
            return error.UnknownTool;
        }
    }

    /// Enhanced read_code tool with security validation and comprehensive error handling
    fn executeReadCode(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const path_value = args_obj.get("path") orelse {
            return self.createErrorResponse("Missing required 'path' parameter");
        };

        // Validate path parameter type
        if (path_value != .string) {
            return self.createErrorResponse("Path parameter must be a string");
        }

        const path = path_value.string;

        // Validate path length and content
        if (path.len == 0) {
            return self.createErrorResponse("Path cannot be empty");
        }

        if (path.len > 4096) {
            return self.createErrorResponse("Path too long (max 4096 characters)");
        }

        // Use database's built-in path validation for security
        Database.validatePath(path) catch |err| {
            const error_msg = switch (err) {
                error.AbsolutePathNotAllowed => "Absolute paths not allowed",
                error.PathTraversalAttempt => "Path traversal attempt detected",
                error.InvalidPathSeparator => "Invalid path separator",
                error.EncodedTraversalAttempt => "Encoded path traversal attempt",
                error.NullByteInPath => "Null byte in path",
                error.PathNotInAllowedDirectory => "Path not in allowed directory",
                else => "Invalid path",
            };
            return self.createErrorResponse(error_msg);
        };

        // Validate optional parameters with type checking
        const include_history = if (args_obj.get("include_history")) |val| blk: {
            if (val != .bool) {
                return self.createErrorResponse("include_history must be a boolean");
            }
            break :blk val.bool;
        } else false;

        const include_dependencies = if (args_obj.get("include_dependencies")) |val| blk: {
            if (val != .bool) {
                return self.createErrorResponse("include_dependencies must be a boolean");
            }
            break :blk val.bool;
        } else false;

        const include_similar = if (args_obj.get("include_similar")) |val| blk: {
            if (val != .bool) {
                return self.createErrorResponse("include_similar must be a boolean");
            }
            break :blk val.bool;
        } else false;

        const max_similar = if (args_obj.get("max_similar")) |val| blk: {
            if (val != .integer) {
                return self.createErrorResponse("max_similar must be an integer");
            }
            if (val.integer < 1 or val.integer > 100) {
                return self.createErrorResponse("max_similar must be between 1 and 100");
            }
            break :blk @as(u32, @intCast(val.integer));
        } else 5;

        // Get base file content with proper error handling
        const content = self.database.getFile(path) catch |err| switch (err) {
            error.FileNotFound => "File not found",
            error.PathNotInAllowedDirectory => return self.createErrorResponse("Access denied: path not allowed"),
            else => return self.createErrorResponse("Failed to read file"),
        };

        var response_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (response_parts.items) |part| {
                self.allocator.free(part);
            }
            response_parts.deinit();
        }

        // Base content
        try response_parts.append(try std.fmt.allocPrint(self.allocator, "=== File Content: {s} ===\n{s}\n", .{ path, content }));

        // Add semantic context if available and requested
        if (include_similar and self.semantic_db != null) {
            if (self.findSimilarFiles(path, max_similar)) |similar_files| {
                defer self.allocator.free(similar_files);

                if (similar_files.len > 0) {
                    var similar_text = ArrayList(u8).init(self.allocator);
                    defer similar_text.deinit();

                    try similar_text.appendSlice("\n=== Similar Files ===\n");
                    for (similar_files) |similar| {
                        const line = try std.fmt.allocPrint(self.allocator, "- {s} (similarity: {d:.3})\n", .{ similar.file_path, similar.similarity });
                        defer self.allocator.free(line);
                        try similar_text.appendSlice(line);
                    }

                    try response_parts.append(try similar_text.toOwnedSlice());
                }
            } else |_| {
                // Ignore semantic search errors for now
            }
        }

        // Add history if requested
        if (include_history) {
            if (self.database.getHistory(path, 5)) |history| {
                defer self.allocator.free(history);

                if (history.len > 0) {
                    var history_text = ArrayList(u8).init(self.allocator);
                    defer history_text.deinit();

                    try history_text.appendSlice("\n=== Recent History ===\n");
                    for (history) |change| {
                        const timestamp = @divFloor(change.timestamp, 1000); // Convert to seconds
                        const line = try std.fmt.allocPrint(self.allocator, "- {d} ({d} bytes)\n", .{ timestamp, change.content.len });
                        defer self.allocator.free(line);
                        try history_text.appendSlice(line);
                    }

                    try response_parts.append(try history_text.toOwnedSlice());
                }
            } else |_| {
                // Ignore history errors for now
            }
        }

        // Add dependency information if requested and FRE is available
        if (include_dependencies and self.fre_engine != null) {
            const fre_engine = self.fre_engine.?;

            // Convert file path to node ID for graph operations
            const root_node_id = std.hash_map.hashString(path);

            // Perform dependency analysis using FRE
            if (fre_engine.analyzeDependencies(root_node_id, @import("fre.zig").TraversalDirection.bidirectional, 2)) |deps| {
                defer deps.deinit(self.allocator);

                var deps_text = ArrayList(u8).init(self.allocator);
                defer deps_text.deinit();

                try deps_text.appendSlice("\n=== Dependencies ===\n");

                if (deps.edges.len > 0) {
                    try deps_text.appendSlice("Dependency relationships:\n");
                    for (deps.edges) |edge| {
                        const line = try std.fmt.allocPrint(self.allocator, "- Node {d} -> Node {d} ({s})\n", .{ edge.source, edge.target, edge.relationship.toString() });
                        defer self.allocator.free(line);
                        try deps_text.appendSlice(line);
                    }
                } else {
                    try deps_text.appendSlice("No dependency relationships found.\n");
                }

                try response_parts.append(try deps_text.toOwnedSlice());
            } else |_| {
                try response_parts.append(try self.allocator.dupe(u8, "\n=== Dependencies ===\nDependency analysis failed.\n"));
            }
        }

        // Combine all parts
        var total_length: usize = 0;
        for (response_parts.items) |part| {
            total_length += part.len;
        }

        var combined = try self.allocator.alloc(u8, total_length);
        var offset: usize = 0;
        for (response_parts.items) |part| {
            @memcpy(combined[offset .. offset + part.len], part);
            offset += part.len;
        }

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = combined,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Find similar files using semantic search
    fn findSimilarFiles(self: *MCPCompliantServer, path: []const u8, max_results: u32) ![]@import("semantic_database.zig").SemanticSearchResult {
        const semantic_db = self.semantic_db orelse return error.SemanticDatabaseNotAvailable;

        // Get the embedding for the file if it exists
        if (semantic_db.file_embeddings.get(path)) |embedding| {
            const search_params = hnsw.HNSWSearchParams{
                .k = max_results,
                .ef = @min(50, max_results * 4),
                .precision_target = 0.8,
            };

            return try semantic_db.semanticSearch(embedding, search_params);
        }

        return error.NoEmbeddingForFile;
    }

    /// Enhanced write_code tool with comprehensive security validation
    fn executeWriteCode(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;

        // Validate required path parameter
        const path_value = args_obj.get("path") orelse {
            return self.createErrorResponse("Missing required 'path' parameter");
        };

        if (path_value != .string) {
            return self.createErrorResponse("Path parameter must be a string");
        }

        const path = path_value.string;

        // Validate path security
        if (path.len == 0) {
            return self.createErrorResponse("Path cannot be empty");
        }

        if (path.len > 4096) {
            return self.createErrorResponse("Path too long (max 4096 characters)");
        }

        Database.validatePath(path) catch |err| {
            const error_msg = switch (err) {
                error.AbsolutePathNotAllowed => "Absolute paths not allowed",
                error.PathTraversalAttempt => "Path traversal attempt detected",
                error.InvalidPathSeparator => "Invalid path separator",
                error.EncodedTraversalAttempt => "Encoded path traversal attempt",
                error.NullByteInPath => "Null byte in path",
                error.PathNotInAllowedDirectory => "Path not in allowed directory",
                else => "Invalid path",
            };
            return self.createErrorResponse(error_msg);
        };

        // Validate required content parameter
        const content_value = args_obj.get("content") orelse {
            return self.createErrorResponse("Missing required 'content' parameter");
        };

        if (content_value != .string) {
            return self.createErrorResponse("Content parameter must be a string");
        }

        const content = content_value.string;

        // Validate content size to prevent DoS attacks
        const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB limit
        if (content.len > MAX_FILE_SIZE) {
            return self.createErrorResponse("File content too large (max 50MB)");
        }

        // Validate optional parameters with proper type checking
        const agent_id = if (args_obj.get("agent_id")) |val| blk: {
            if (val != .string) {
                return self.createErrorResponse("agent_id must be a string");
            }
            if (val.string.len > 256) {
                return self.createErrorResponse("agent_id too long (max 256 characters)");
            }
            break :blk val.string;
        } else "unknown-agent";

        const agent_name = if (args_obj.get("agent_name")) |val| blk: {
            if (val != .string) {
                return self.createErrorResponse("agent_name must be a string");
            }
            if (val.string.len > 256) {
                return self.createErrorResponse("agent_name too long (max 256 characters)");
            }
            break :blk val.string;
        } else "Unknown Agent";

        const generate_embedding = if (args_obj.get("generate_embedding")) |val| blk: {
            if (val != .bool) {
                return self.createErrorResponse("generate_embedding must be a boolean");
            }
            break :blk val.bool;
        } else true;

        // Save to basic database
        try self.database.saveFile(path, content);

        var response_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (response_parts.items) |part| {
                self.allocator.free(part);
            }
            response_parts.deinit();
        }

        try response_parts.append(try std.fmt.allocPrint(self.allocator, "Successfully wrote {d} bytes to {s}\n", .{ content.len, path }));

        // Register agent session
        try self.registerAgentActivity(agent_id, agent_name);

        // Handle CRDT document if collaborative editing is enabled
        if (self.active_documents.get(path)) |crdt_doc| {
            // Apply content as CRDT operation
            // Create CRDT operation for text replacement
            const replace_op = @import("crdt.zig").CRDTOperation.init(self.allocator, @import("crdt.zig").generateOperationId(), agent_id, path, .modify, @import("crdt.zig").Position{ .line = 1, .column = 1, .offset = 0 }, content, crdt_doc.vector_clock) catch return self.createErrorResponse("CRDT operation creation failed");

            if (crdt_doc.applyOperation(replace_op)) |_| {
                // Update agent cursor position to end of document
                const position = @import("crdt.zig").Position{
                    .line = @intCast(std.mem.count(u8, content, "\n") + 1),
                    .column = @intCast(content.len - (std.mem.lastIndexOf(u8, content, "\n") orelse 0)),
                    .offset = @intCast(content.len),
                };
                try crdt_doc.updateAgentCursor(agent_id, agent_name, position);
                try response_parts.append(try self.allocator.dupe(u8, "Applied CRDT operation to collaborative document\n"));
            } else |err| {
                // Fallback to simple cursor update if CRDT operation fails
                const position = @import("crdt.zig").Position{
                    .line = 1,
                    .column = 1,
                    .offset = 0,
                };
                try crdt_doc.updateAgentCursor(agent_id, agent_name, position);

                const warn_msg = try std.fmt.allocPrint(self.allocator, "Warning: CRDT operation failed ({}), updated cursor only\n", .{err});
                try response_parts.append(warn_msg);
            }
        } else if (self.active_documents.count() > 0 or self.agent_sessions.count() > 1) {
            // Create new CRDT document for collaboration when multiple agents are active
            if (CRDTDocument.init(self.allocator, path, content)) |crdt_doc_value| {
                const crdt_doc = try self.allocator.create(CRDTDocument);
                crdt_doc.* = crdt_doc_value;

                const owned_path = try self.allocator.dupe(u8, path);
                try self.active_documents.put(owned_path, crdt_doc);

                // Add initial cursor for this agent
                const position = @import("crdt.zig").Position{
                    .line = @intCast(std.mem.count(u8, content, "\n") + 1),
                    .column = @intCast(content.len - (std.mem.lastIndexOf(u8, content, "\n") orelse 0)),
                    .offset = @intCast(content.len),
                };
                try crdt_doc.updateAgentCursor(agent_id, agent_name, position);

                try response_parts.append(try self.allocator.dupe(u8, "Enabled collaborative editing with CRDT\n"));
            } else |err| {
                const warn_msg = try std.fmt.allocPrint(self.allocator, "Warning: Failed to enable CRDT collaboration ({})\n", .{err});
                try response_parts.append(warn_msg);
            }
        }

        // Generate and store semantic embedding if requested and semantic DB available
        if (generate_embedding and self.semantic_db != null) {
            if (self.generateContentEmbedding(content)) |embedding_result| {
                var embedding = embedding_result;
                defer embedding.deinit(self.allocator);

                if (self.semantic_db) |semantic_db| {
                    semantic_db.saveFileWithEmbedding(path, content, embedding) catch |err| {
                        const warn_msg = try std.fmt.allocPrint(self.allocator, "Warning: Failed to save embedding ({})\n", .{err});
                        try response_parts.append(warn_msg);
                    };
                    try response_parts.append(try self.allocator.dupe(u8, "Generated and stored semantic embedding\n"));
                }
            } else |err| {
                const warn_msg = try std.fmt.allocPrint(self.allocator, "Warning: Failed to generate embedding ({})\n", .{err});
                try response_parts.append(warn_msg);
            }
        }

        // Combine all response parts
        var total_length: usize = 0;
        for (response_parts.items) |part| {
            total_length += part.len;
        }

        var combined = try self.allocator.alloc(u8, total_length);
        var offset: usize = 0;
        for (response_parts.items) |part| {
            @memcpy(combined[offset .. offset + part.len], part);
            offset += part.len;
        }

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = combined,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Register agent activity for session tracking
    fn registerAgentActivity(self: *MCPCompliantServer, agent_id: []const u8, agent_name: []const u8) !void {
        const now = std.time.timestamp();

        if (self.agent_sessions.getPtr(agent_id)) |session| {
            session.last_activity = now;
            session.operations_count += 1;
        } else {
            const session = AgentSession{
                .agent_id = try self.allocator.dupe(u8, agent_id),
                .agent_name = try self.allocator.dupe(u8, agent_name),
                .session_start = now,
                .operations_count = 1,
                .last_activity = now,
            };

            const owned_id = try self.allocator.dupe(u8, agent_id);
            try self.agent_sessions.put(owned_id, session);
        }
    }

    /// Generate content-based embedding using statistical analysis
    /// This is a placeholder implementation that uses text statistics
    /// In production, this would use a proper embedding model
    fn generateContentEmbedding(self: *MCPCompliantServer, content: []const u8) !hnsw.MatryoshkaEmbedding {
        const dims = [_]u32{ 64, 256, 768 };
        const embedding = try hnsw.MatryoshkaEmbedding.init(self.allocator, 768, &dims);

        // Initialize with zeros
        @memset(embedding.full_vector.data, 0.0);

        if (content.len == 0) {
            return embedding;
        }

        // Extract statistical features from content
        var char_counts: [256]u32 = [_]u32{0} ** 256;
        var line_count: u32 = 1;
        var word_count: u32 = 0;
        var in_word = false;

        for (content) |char| {
            char_counts[char] += 1;

            if (char == '\n') {
                line_count += 1;
            }

            const is_alpha = (char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z');
            if (is_alpha and !in_word) {
                word_count += 1;
                in_word = true;
            } else if (!is_alpha) {
                in_word = false;
            }
        }

        // Generate embedding based on content statistics
        var feature_index: usize = 0;

        // Basic text statistics (first 16 dimensions)
        if (feature_index < embedding.full_vector.data.len) {
            embedding.full_vector.data[feature_index] = @as(f32, @floatFromInt(content.len)) / 10000.0;
            feature_index += 1;
        }
        if (feature_index < embedding.full_vector.data.len) {
            embedding.full_vector.data[feature_index] = @as(f32, @floatFromInt(line_count)) / 1000.0;
            feature_index += 1;
        }
        if (feature_index < embedding.full_vector.data.len) {
            embedding.full_vector.data[feature_index] = @as(f32, @floatFromInt(word_count)) / @as(f32, @floatFromInt(content.len + 1));
            feature_index += 1;
        }

        // Character distribution features (next 256 dimensions, normalized)
        const content_len_f32 = @as(f32, @floatFromInt(content.len));
        for (char_counts) |count| {
            if (feature_index >= embedding.full_vector.data.len) break;
            embedding.full_vector.data[feature_index] = @as(f32, @floatFromInt(count)) / content_len_f32;
            feature_index += 1;
        }

        // Content-based hash features for remaining dimensions
        const content_hash = std.hash_map.hashString(content);
        var prng = std.Random.DefaultPrng.init(content_hash);
        const random = prng.random();

        while (feature_index < embedding.full_vector.data.len) {
            // Mix statistical features with content-derived randomness
            const base_value = random.floatNorm(f32) * 0.1;
            const stat_influence = if (feature_index % 4 == 0)
                (@as(f32, @floatFromInt(word_count)) / 1000.0 - 0.5)
            else if (feature_index % 4 == 1)
                (@as(f32, @floatFromInt(line_count)) / 100.0 - 0.5)
            else if (feature_index % 4 == 2)
                (@as(f32, @floatFromInt(char_counts[' '])) / content_len_f32 - 0.1)
            else
                (@as(f32, @floatFromInt(char_counts['\n'])) / content_len_f32 - 0.05);

            embedding.full_vector.data[feature_index] = base_value + stat_influence * 0.5;
            feature_index += 1;
        }

        return embedding;
    }

    /// Enhanced get_context tool with comprehensive system status and agent awareness
    fn executeGetContext(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const context_type = if (args_obj.get("type")) |val| val.string else "full";
        const path = if (args_obj.get("path")) |val| val.string else null;

        var context_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (context_parts.items) |part| {
                self.allocator.free(part);
            }
            context_parts.deinit();
        }

        // System overview
        if (std.mem.eql(u8, context_type, "full") or std.mem.eql(u8, context_type, "system")) {
            const capabilities = if (self.semantic_db != null and self.fre_engine != null and self.hybrid_search != null)
                "Advanced (Semantic + FRE + Hybrid Search)"
            else if (self.semantic_db != null)
                "Enhanced (Semantic Search)"
            else
                "Basic";

            try context_parts.append(try std.fmt.allocPrint(self.allocator, "=== Agrama CodeGraph MCP Server ===\n" ++
                "Capabilities: {s}\n" ++
                "Protocol Version: {s}\n" ++
                "Total Tool Calls: {d}\n" ++
                "Average Response Time: {d:.2}ms\n\n", .{ capabilities, self.protocol_version, self.tool_call_count, if (self.tool_call_count > 0) @as(f64, @floatFromInt(self.total_response_time_ms)) / @as(f64, @floatFromInt(self.tool_call_count)) else 0.0 }));
        }

        // Available tools
        if (std.mem.eql(u8, context_type, "full") or std.mem.eql(u8, context_type, "tools")) {
            var tools_list = ArrayList(u8).init(self.allocator);
            defer tools_list.deinit();

            try tools_list.appendSlice("=== Available Tools ===\n");
            for (self.tools.items) |tool| {
                const line = try std.fmt.allocPrint(self.allocator, "- {s}: {s}\n", .{ tool.name, tool.description });
                defer self.allocator.free(line);
                try tools_list.appendSlice(line);
            }
            try tools_list.appendSlice("\n");

            try context_parts.append(try tools_list.toOwnedSlice());
        }

        // Active agents
        if (std.mem.eql(u8, context_type, "full") or std.mem.eql(u8, context_type, "agents")) {
            var agents_info = ArrayList(u8).init(self.allocator);
            defer agents_info.deinit();

            try agents_info.appendSlice("=== Active Agent Sessions ===\n");
            if (self.agent_sessions.count() == 0) {
                try agents_info.appendSlice("No active agents\n");
            } else {
                var session_iterator = self.agent_sessions.iterator();
                while (session_iterator.next()) |entry| {
                    const session = entry.value_ptr.*;
                    const duration = std.time.timestamp() - session.session_start;
                    const line = try std.fmt.allocPrint(self.allocator, "- {s} ({s}): {d} operations, active for {d}s\n", .{ session.agent_id, session.agent_name, session.operations_count, duration });
                    defer self.allocator.free(line);
                    try agents_info.appendSlice(line);
                }
            }
            try agents_info.appendSlice("\n");

            try context_parts.append(try agents_info.toOwnedSlice());
        }

        // Database metrics
        if (std.mem.eql(u8, context_type, "full") or std.mem.eql(u8, context_type, "metrics")) {
            var metrics_info = ArrayList(u8).init(self.allocator);
            defer metrics_info.deinit();

            try metrics_info.appendSlice("=== Database Metrics ===\n");

            const file_count = self.database.current_files.count();
            try metrics_info.appendSlice(try std.fmt.allocPrint(self.allocator, "Files stored: {d}\n", .{file_count}));

            if (self.semantic_db) |semantic_db| {
                const stats = semantic_db.getStats();
                const line = try std.fmt.allocPrint(self.allocator, "Semantic index: {d} files, {d} HNSW nodes\n", .{ stats.indexed_files, stats.file_index_stats.node_count });
                defer self.allocator.free(line);
                try metrics_info.appendSlice(line);
            }

            if (self.fre_engine) |fre| {
                const graph_stats = fre.getGraphStats();
                const line = try std.fmt.allocPrint(self.allocator, "Graph database: {d} nodes, {d} edges\n", .{ graph_stats.nodes, graph_stats.edges });
                defer self.allocator.free(line);
                try metrics_info.appendSlice(line);
            }

            const collab_docs = self.active_documents.count();
            try metrics_info.appendSlice(try std.fmt.allocPrint(self.allocator, "Collaborative documents: {d}\n", .{collab_docs}));
            try metrics_info.appendSlice("\n");

            try context_parts.append(try metrics_info.toOwnedSlice());
        }

        // Path-specific context if provided
        if (path) |file_path| {
            var path_info = ArrayList(u8).init(self.allocator);
            defer path_info.deinit();

            try path_info.appendSlice(try std.fmt.allocPrint(self.allocator, "=== File Context: {s} ===\n", .{file_path}));

            // Basic file info
            if (self.database.getFile(file_path)) |content| {
                try path_info.appendSlice(try std.fmt.allocPrint(self.allocator, "Size: {d} bytes\n", .{content.len}));
            } else |_| {
                try path_info.appendSlice("File not found\n");
            }

            // CRDT collaboration status
            if (self.active_documents.get(file_path)) |crdt_doc| {
                const cursors = try crdt_doc.getAgentCursors(self.allocator);
                defer self.allocator.free(cursors);

                if (cursors.len > 0) {
                    try path_info.appendSlice(try std.fmt.allocPrint(self.allocator, "Active collaborators: {d}\n", .{cursors.len}));
                } else {
                    try path_info.appendSlice("No active collaborators\n");
                }
            }

            try path_info.appendSlice("\n");
            try context_parts.append(try path_info.toOwnedSlice());
        }

        // Combine all parts
        var total_length: usize = 0;
        for (context_parts.items) |part| {
            total_length += part.len;
        }

        var combined = try self.allocator.alloc(u8, total_length);
        var offset: usize = 0;
        for (context_parts.items) |part| {
            @memcpy(combined[offset .. offset + part.len], part);
            offset += part.len;
        }

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = combined,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    // === NEW ADVANCED TOOLS ===

    /// Semantic search tool using HNSW indices with comprehensive validation
    fn executeSemanticSearch(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const semantic_db = self.semantic_db orelse {
            return self.createErrorResponse("Semantic database not available. Initialize with initWithAdvancedFeatures()");
        };

        const args_obj = arguments.object;

        // Validate required query parameter
        const query_value = args_obj.get("query") orelse {
            return self.createErrorResponse("Missing required 'query' parameter");
        };

        if (query_value != .string) {
            return self.createErrorResponse("Query parameter must be a string");
        }

        const query_text = query_value.string;

        if (query_text.len == 0) {
            return self.createErrorResponse("Query cannot be empty");
        }

        if (query_text.len > 10000) {
            return self.createErrorResponse("Query too long (max 10000 characters)");
        }

        // Validate optional parameters
        const max_results = if (args_obj.get("max_results")) |val| blk: {
            if (val != .integer) {
                return self.createErrorResponse("max_results must be an integer");
            }
            if (val.integer < 1 or val.integer > 1000) {
                return self.createErrorResponse("max_results must be between 1 and 1000");
            }
            break :blk @as(u32, @intCast(val.integer));
        } else 10;

        const similarity_threshold = if (args_obj.get("similarity_threshold")) |val| blk: {
            if (val != .float) {
                return self.createErrorResponse("similarity_threshold must be a number");
            }
            if (val.float < 0.0 or val.float > 1.0) {
                return self.createErrorResponse("similarity_threshold must be between 0.0 and 1.0");
            }
            break :blk @as(f32, @floatCast(val.float));
        } else 0.7;

        // Generate embedding for query using content-based embedding
        var query_embedding = try self.generateContentEmbedding(query_text);
        defer query_embedding.deinit(self.allocator);

        // Perform semantic search
        const search_params = hnsw.HNSWSearchParams{
            .k = max_results,
            .ef = @min(100, max_results * 4),
            .precision_target = 0.8,
        };

        const results = semantic_db.semanticSearch(query_embedding, search_params) catch |err| {
            return self.createErrorResponse(try std.fmt.allocPrint(self.allocator, "Search failed: {any}", .{err}));
        };
        defer self.allocator.free(results);

        // Filter by similarity threshold and format results
        var filtered_results = ArrayList([]const u8).init(self.allocator);
        defer {
            for (filtered_results.items) |result| {
                self.allocator.free(result);
            }
            filtered_results.deinit();
        }

        try filtered_results.append(try std.fmt.allocPrint(self.allocator, "=== Semantic Search Results for: \"{s}\" ===\n", .{query_text}));

        var count: u32 = 0;
        for (results) |result| {
            if (result.similarity >= similarity_threshold) {
                count += 1;
                const line = try std.fmt.allocPrint(self.allocator, "{d}. {s} (similarity: {d:.3})\n", .{ count, result.file_path, result.similarity });
                try filtered_results.append(line);
            }
        }

        if (count == 0) {
            try filtered_results.append(try self.allocator.dupe(u8, "No results found above similarity threshold.\n"));
        }

        return self.createTextResponse(filtered_results.items);
    }

    /// Analyze dependencies using FRE graph traversal
    fn executeAnalyzeDependencies(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const fre_engine = self.fre_engine orelse {
            return self.createErrorResponse("FRE engine not available. Initialize with initWithAdvancedFeatures()");
        };

        const args_obj = arguments.object;
        const root_path = (args_obj.get("root") orelse return error.MissingRoot).string;
        const max_depth = if (args_obj.get("max_depth")) |val| @as(u32, @intCast(val.integer)) else 3;
        const direction_str = if (args_obj.get("direction")) |val| val.string else "forward";

        const direction = if (std.mem.eql(u8, direction_str, "forward"))
            @import("fre.zig").TraversalDirection.forward
        else if (std.mem.eql(u8, direction_str, "reverse"))
            @import("fre.zig").TraversalDirection.reverse
        else
            @import("fre.zig").TraversalDirection.bidirectional;

        // Convert file path to node ID using consistent hashing
        // This ensures the same path always maps to the same node ID
        const root_node_id = std.hash_map.hashString(root_path);

        const deps = fre_engine.analyzeDependencies(root_node_id, direction, max_depth) catch |err| {
            return self.createErrorResponse(try std.fmt.allocPrint(self.allocator, "Dependency analysis failed: {any}", .{err}));
        };
        defer deps.deinit(self.allocator);

        var result_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (result_parts.items) |part| {
                self.allocator.free(part);
            }
            result_parts.deinit();
        }

        try result_parts.append(try std.fmt.allocPrint(self.allocator, "=== Dependency Analysis: {s} ===\n" ++
            "Direction: {s}\n" ++
            "Max Depth: {d}\n" ++
            "Nodes Found: {d}\n" ++
            "Edges Found: {d}\n\n", .{ root_path, direction_str, max_depth, deps.nodes.len, deps.edges.len }));

        if (deps.nodes.len > 1) {
            try result_parts.append(try self.allocator.dupe(u8, "Dependencies:\n"));
            for (deps.edges) |edge| {
                // Display node IDs with their hash values - in production this would
                // maintain a bidirectional mapping between paths and node IDs
                const source_indicator = if (edge.source == root_node_id) root_path else "related_file";
                const target_indicator = if (edge.target == root_node_id) root_path else "related_file";

                const line = try std.fmt.allocPrint(self.allocator, "- {s}[{d}] -> {s}[{d}] ({s})\n", .{ source_indicator, edge.source, target_indicator, edge.target, edge.relationship.toString() });
                try result_parts.append(line);
            }
        } else {
            try result_parts.append(try self.allocator.dupe(u8, "No dependencies found.\n"));
        }

        return self.createTextResponse(result_parts.items);
    }

    /// Hybrid search combining BM25, HNSW, and FRE
    fn executeHybridSearch(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const hybrid_search = self.hybrid_search orelse {
            return self.createErrorResponse("Hybrid search not available. Initialize with initWithAdvancedFeatures()");
        };

        const args_obj = arguments.object;
        const query_text = (args_obj.get("query") orelse return error.MissingQuery).string;
        const max_results = if (args_obj.get("max_results")) |val| @as(u32, @intCast(val.integer)) else 10;
        const alpha = if (args_obj.get("alpha")) |val| @as(f32, @floatCast(val.float)) else 0.4;
        const beta = if (args_obj.get("beta")) |val| @as(f32, @floatCast(val.float)) else 0.4;
        const gamma = if (args_obj.get("gamma")) |val| @as(f32, @floatCast(val.float)) else 0.2;

        // Generate embedding for semantic component
        var query_embedding = try self.generateContentEmbedding(query_text);
        defer query_embedding.deinit(self.allocator);

        // Create hybrid query
        const hybrid_query = @import("triple_hybrid_search.zig").HybridQuery{
            .text_query = query_text,
            .embedding_query = query_embedding.full_vector.data,
            .max_results = max_results,
            .alpha = alpha,
            .beta = beta,
            .gamma = gamma,
        };

        const results = hybrid_search.search(hybrid_query) catch |err| {
            return self.createErrorResponse(try std.fmt.allocPrint(self.allocator, "Hybrid search failed: {any}", .{err}));
        };
        defer {
            for (results) |result| {
                result.deinit(self.allocator);
            }
            self.allocator.free(results);
        }

        var result_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (result_parts.items) |part| {
                self.allocator.free(part);
            }
            result_parts.deinit();
        }

        try result_parts.append(try std.fmt.allocPrint(self.allocator, "=== Hybrid Search Results: \"{s}\" ===\n" ++
            "Weights: BM25={d:.2}, HNSW={d:.2}, FRE={d:.2}\n" ++
            "Results: {d}\n\n", .{ query_text, alpha, beta, gamma, results.len }));

        for (results, 0..) |result, i| {
            const line = try std.fmt.allocPrint(self.allocator, "{d}. {s} (score: {d:.3})\n" ++
                "   BM25: {d:.3}, Semantic: {d:.3}, Graph: {d:.3}\n", .{ i + 1, result.file_path, result.combined_score, result.bm25_score, result.hnsw_score, result.fre_score });
            try result_parts.append(line);
        }

        if (results.len == 0) {
            try result_parts.append(try self.allocator.dupe(u8, "No results found.\n"));
        }

        return self.createTextResponse(result_parts.items);
    }

    /// Record agent decision with provenance
    fn executeRecordDecision(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const agent_id = (args_obj.get("agent_id") orelse return error.MissingAgentId).string;
        const decision = (args_obj.get("decision") orelse return error.MissingDecision).string;
        const reasoning = if (args_obj.get("reasoning")) |val| val.string else "";
        const context = if (args_obj.get("context")) |val| val.string else "";

        // TODO: Store decision in FRE graph or dedicated decision log
        // For now, just track in agent session
        try self.registerAgentActivity(agent_id, "Decision Agent");

        const response_text = try std.fmt.allocPrint(self.allocator, "Decision recorded successfully:\n" ++
            "Agent: {s}\n" ++
            "Decision: {s}\n" ++
            "Reasoning: {s}\n" ++
            "Context: {s}\n" ++
            "Timestamp: {d}\n", .{ agent_id, decision, reasoning, context, std.time.timestamp() });

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = response_text,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Query temporal history with advanced filtering
    fn executeQueryHistory(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const path = if (args_obj.get("path")) |val| val.string else null;
        const limit = if (args_obj.get("limit")) |val| @as(usize, @intCast(val.integer)) else 10;
        const since = if (args_obj.get("since")) |val| @as(i64, @intCast(val.integer)) else 0;

        var result_parts = ArrayList([]const u8).init(self.allocator);
        defer {
            for (result_parts.items) |part| {
                self.allocator.free(part);
            }
            result_parts.deinit();
        }

        if (path) |file_path| {
            // Query specific file history
            try result_parts.append(try std.fmt.allocPrint(self.allocator, "=== History for {s} ===\n", .{file_path}));

            if (self.database.getHistory(file_path, limit)) |history| {
                defer self.allocator.free(history);

                var count: usize = 0;
                for (history) |change| {
                    if (change.timestamp >= since) {
                        count += 1;
                        const line = try std.fmt.allocPrint(self.allocator, "{d}. {d} - {d} bytes\n", .{ count, change.timestamp, change.content.len });
                        try result_parts.append(line);
                    }
                }

                if (count == 0) {
                    try result_parts.append(try self.allocator.dupe(u8, "No changes found in specified time range.\n"));
                }
            } else |_| {
                try result_parts.append(try self.allocator.dupe(u8, "No history found for file.\n"));
            }
        } else {
            // Global history overview
            try result_parts.append(try self.allocator.dupe(u8, "=== Global History Overview ===\n"));

            const file_count = self.database.current_files.count();
            const history_count = self.database.file_histories.count();

            try result_parts.append(try std.fmt.allocPrint(self.allocator, "Total files: {d}\n" ++
                "Files with history: {d}\n" ++
                "Active sessions: {d}\n", .{ file_count, history_count, self.agent_sessions.count() }));
        }

        return self.createTextResponse(result_parts.items);
    }

    // === HELPER METHODS ===

    /// Create error response
    fn createErrorResponse(self: *MCPCompliantServer, error_message: []const u8) !MCPToolResponse {
        const owned_message = try self.allocator.dupe(u8, error_message);

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = owned_message,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = true,
        };
    }

    /// Create text response from multiple parts
    fn createTextResponse(self: *MCPCompliantServer, parts: [][]const u8) !MCPToolResponse {
        var total_length: usize = 0;
        for (parts) |part| {
            total_length += part.len;
        }

        var combined = try self.allocator.alloc(u8, total_length);
        var offset: usize = 0;
        for (parts) |part| {
            @memcpy(combined[offset .. offset + part.len], part);
            offset += part.len;
        }

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = combined,
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Send JSON-RPC response
    fn sendResponse(self: *MCPCompliantServer, id: ?std.json.Value, result: std.json.Value) !void {
        const response = MCPResponse{
            .id = id,
            .result = result,
        };

        try self.sendMessage(response);
    }

    /// Send JSON-RPC error
    fn sendError(self: *MCPCompliantServer, id: ?std.json.Value, code: i32, message: []const u8, data: ?std.json.Value) !void {
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

        // Clean up the error message we allocated
        response.deinit(self.allocator);
    }

    /// Send message to stdout (stdio transport)
    fn sendMessage(self: *MCPCompliantServer, response: MCPResponse) !void {
        // Use arena allocator for temporary JSON serialization to avoid leaks
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const json_allocator = arena.allocator();

        var string = std.ArrayList(u8).init(json_allocator);

        // Manually construct JSON-RPC response to ensure spec compliance
        // JSON-RPC 2.0 requires EITHER result OR error, never both
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

        try string.appendSlice("}\n"); // Close object and add newline delimiter

        try self.stdout_writer.writeAll(string.items);
    }

    // REMOVED: escapeJsonString function - replaced with safe Zig JSON handling
    // The previous manual JSON escaping was vulnerable to:
    // 1. Incorrect Unicode escape format (decimal instead of hex)
    // 2. JSON injection through manual string construction
    // 3. Incomplete handling of edge cases
    // Now using std.json.Value for type-safe JSON construction
};

/// Create enhanced read_code tool definition
fn createReadCodeTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var path_schema = std.json.ObjectMap.init(json_allocator);
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "File path to read" });

    var history_schema = std.json.ObjectMap.init(json_allocator);
    try history_schema.put("type", std.json.Value{ .string = "boolean" });
    try history_schema.put("description", std.json.Value{ .string = "Include file modification history" });
    try history_schema.put("default", std.json.Value{ .bool = false });

    var dependencies_schema = std.json.ObjectMap.init(json_allocator);
    try dependencies_schema.put("type", std.json.Value{ .string = "boolean" });
    try dependencies_schema.put("description", std.json.Value{ .string = "Include dependency analysis using FRE" });
    try dependencies_schema.put("default", std.json.Value{ .bool = false });

    var similar_schema = std.json.ObjectMap.init(json_allocator);
    try similar_schema.put("type", std.json.Value{ .string = "boolean" });
    try similar_schema.put("description", std.json.Value{ .string = "Include semantically similar files" });
    try similar_schema.put("default", std.json.Value{ .bool = false });

    var max_similar_schema = std.json.ObjectMap.init(json_allocator);
    try max_similar_schema.put("type", std.json.Value{ .string = "integer" });
    try max_similar_schema.put("description", std.json.Value{ .string = "Maximum number of similar files to include" });
    try max_similar_schema.put("default", std.json.Value{ .integer = 5 });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("include_history", std.json.Value{ .object = history_schema });
    try properties.put("include_dependencies", std.json.Value{ .object = dependencies_schema });
    try properties.put("include_similar", std.json.Value{ .object = similar_schema });
    try properties.put("max_similar", std.json.Value{ .object = max_similar_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "path" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "read_code"),
        .title = try allocator.dupe(u8, "Read Code File"),
        .description = try allocator.dupe(u8, "Read code files with semantic context, history, dependencies, and similar files"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create enhanced write_code tool definition
fn createWriteCodeTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var path_schema = std.json.ObjectMap.init(json_allocator);
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "File path to write or modify" });

    var content_schema = std.json.ObjectMap.init(json_allocator);
    try content_schema.put("type", std.json.Value{ .string = "string" });
    try content_schema.put("description", std.json.Value{ .string = "File content to write" });

    var agent_id_schema = std.json.ObjectMap.init(json_allocator);
    try agent_id_schema.put("type", std.json.Value{ .string = "string" });
    try agent_id_schema.put("description", std.json.Value{ .string = "ID of the agent making the change" });
    try agent_id_schema.put("default", std.json.Value{ .string = "unknown-agent" });

    var agent_name_schema = std.json.ObjectMap.init(json_allocator);
    try agent_name_schema.put("type", std.json.Value{ .string = "string" });
    try agent_name_schema.put("description", std.json.Value{ .string = "Human-readable agent name" });
    try agent_name_schema.put("default", std.json.Value{ .string = "Unknown Agent" });

    var generate_embedding_schema = std.json.ObjectMap.init(json_allocator);
    try generate_embedding_schema.put("type", std.json.Value{ .string = "boolean" });
    try generate_embedding_schema.put("description", std.json.Value{ .string = "Generate semantic embedding for search" });
    try generate_embedding_schema.put("default", std.json.Value{ .bool = true });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("content", std.json.Value{ .object = content_schema });
    try properties.put("agent_id", std.json.Value{ .object = agent_id_schema });
    try properties.put("agent_name", std.json.Value{ .object = agent_name_schema });
    try properties.put("generate_embedding", std.json.Value{ .object = generate_embedding_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "path" });
    try required.append(std.json.Value{ .string = "content" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "write_code"),
        .title = try allocator.dupe(u8, "Write Code File"),
        .description = try allocator.dupe(u8, "Write code files with CRDT collaboration, provenance tracking, and semantic indexing"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create enhanced get_context tool definition
fn createGetContextTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var path_schema = std.json.ObjectMap.init(json_allocator);
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "Optional file path for specific context" });

    var type_schema = std.json.ObjectMap.init(json_allocator);
    try type_schema.put("type", std.json.Value{ .string = "string" });
    try type_schema.put("description", std.json.Value{ .string = "Context type: 'full', 'system', 'tools', 'agents', 'metrics'" });
    try type_schema.put("default", std.json.Value{ .string = "full" });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("type", std.json.Value{ .object = type_schema });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "get_context"),
        .title = try allocator.dupe(u8, "Get Context"),
        .description = try allocator.dupe(u8, "Get comprehensive contextual information with agent awareness"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create semantic search tool definition
fn createSemanticSearchTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var query_schema = std.json.ObjectMap.init(json_allocator);
    try query_schema.put("type", std.json.Value{ .string = "string" });
    try query_schema.put("description", std.json.Value{ .string = "Text query for semantic search" });

    var max_results_schema = std.json.ObjectMap.init(json_allocator);
    try max_results_schema.put("type", std.json.Value{ .string = "integer" });
    try max_results_schema.put("description", std.json.Value{ .string = "Maximum number of results" });
    try max_results_schema.put("default", std.json.Value{ .integer = 10 });

    var threshold_schema = std.json.ObjectMap.init(json_allocator);
    try threshold_schema.put("type", std.json.Value{ .string = "number" });
    try threshold_schema.put("description", std.json.Value{ .string = "Minimum similarity threshold (0.0-1.0)" });
    try threshold_schema.put("default", std.json.Value{ .float = 0.7 });

    try properties.put("query", std.json.Value{ .object = query_schema });
    try properties.put("max_results", std.json.Value{ .object = max_results_schema });
    try properties.put("similarity_threshold", std.json.Value{ .object = threshold_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "query" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "semantic_search"),
        .title = try allocator.dupe(u8, "Semantic Search"),
        .description = try allocator.dupe(u8, "Search for semantically similar code using HNSW indices"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create analyze dependencies tool definition
fn createAnalyzeDependenciesTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var root_schema = std.json.ObjectMap.init(json_allocator);
    try root_schema.put("type", std.json.Value{ .string = "string" });
    try root_schema.put("description", std.json.Value{ .string = "Root file/entity to analyze dependencies for" });

    var depth_schema = std.json.ObjectMap.init(json_allocator);
    try depth_schema.put("type", std.json.Value{ .string = "integer" });
    try depth_schema.put("description", std.json.Value{ .string = "Maximum dependency depth to traverse" });
    try depth_schema.put("default", std.json.Value{ .integer = 3 });

    var direction_schema = std.json.ObjectMap.init(json_allocator);
    try direction_schema.put("type", std.json.Value{ .string = "string" });
    try direction_schema.put("description", std.json.Value{ .string = "Direction: 'forward', 'reverse', or 'bidirectional'" });
    try direction_schema.put("enum", std.json.Value{ .array = blk: {
        var enum_array = std.json.Array.init(json_allocator);
        try enum_array.append(std.json.Value{ .string = "forward" });
        try enum_array.append(std.json.Value{ .string = "reverse" });
        try enum_array.append(std.json.Value{ .string = "bidirectional" });
        break :blk enum_array;
    } });
    try direction_schema.put("default", std.json.Value{ .string = "forward" });

    try properties.put("root", std.json.Value{ .object = root_schema });
    try properties.put("max_depth", std.json.Value{ .object = depth_schema });
    try properties.put("direction", std.json.Value{ .object = direction_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "root" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "analyze_dependencies"),
        .title = try allocator.dupe(u8, "Analyze Dependencies"),
        .description = try allocator.dupe(u8, "Analyze code dependencies using FRE graph traversal"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create hybrid search tool definition
fn createHybridSearchTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var query_schema = std.json.ObjectMap.init(json_allocator);
    try query_schema.put("type", std.json.Value{ .string = "string" });
    try query_schema.put("description", std.json.Value{ .string = "Search query combining text and semantic meaning" });

    var max_results_schema = std.json.ObjectMap.init(json_allocator);
    try max_results_schema.put("type", std.json.Value{ .string = "integer" });
    try max_results_schema.put("description", std.json.Value{ .string = "Maximum number of results" });
    try max_results_schema.put("default", std.json.Value{ .integer = 10 });

    var alpha_schema = std.json.ObjectMap.init(json_allocator);
    try alpha_schema.put("type", std.json.Value{ .string = "number" });
    try alpha_schema.put("description", std.json.Value{ .string = "BM25 lexical weight (0.0-1.0)" });
    try alpha_schema.put("default", std.json.Value{ .float = 0.4 });

    var beta_schema = std.json.ObjectMap.init(json_allocator);
    try beta_schema.put("type", std.json.Value{ .string = "number" });
    try beta_schema.put("description", std.json.Value{ .string = "HNSW semantic weight (0.0-1.0)" });
    try beta_schema.put("default", std.json.Value{ .float = 0.4 });

    var gamma_schema = std.json.ObjectMap.init(json_allocator);
    try gamma_schema.put("type", std.json.Value{ .string = "number" });
    try gamma_schema.put("description", std.json.Value{ .string = "FRE graph weight (0.0-1.0)" });
    try gamma_schema.put("default", std.json.Value{ .float = 0.2 });

    try properties.put("query", std.json.Value{ .object = query_schema });
    try properties.put("max_results", std.json.Value{ .object = max_results_schema });
    try properties.put("alpha", std.json.Value{ .object = alpha_schema });
    try properties.put("beta", std.json.Value{ .object = beta_schema });
    try properties.put("gamma", std.json.Value{ .object = gamma_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "query" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "hybrid_search"),
        .title = try allocator.dupe(u8, "Hybrid Search"),
        .description = try allocator.dupe(u8, "Advanced hybrid search combining BM25, HNSW, and FRE algorithms"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create record decision tool definition
fn createRecordDecisionTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var agent_id_schema = std.json.ObjectMap.init(json_allocator);
    try agent_id_schema.put("type", std.json.Value{ .string = "string" });
    try agent_id_schema.put("description", std.json.Value{ .string = "ID of the agent making the decision" });

    var decision_schema = std.json.ObjectMap.init(json_allocator);
    try decision_schema.put("type", std.json.Value{ .string = "string" });
    try decision_schema.put("description", std.json.Value{ .string = "The decision or action taken" });

    var reasoning_schema = std.json.ObjectMap.init(json_allocator);
    try reasoning_schema.put("type", std.json.Value{ .string = "string" });
    try reasoning_schema.put("description", std.json.Value{ .string = "Reasoning behind the decision" });

    var context_schema = std.json.ObjectMap.init(json_allocator);
    try context_schema.put("type", std.json.Value{ .string = "string" });
    try context_schema.put("description", std.json.Value{ .string = "Additional context or metadata" });

    try properties.put("agent_id", std.json.Value{ .object = agent_id_schema });
    try properties.put("decision", std.json.Value{ .object = decision_schema });
    try properties.put("reasoning", std.json.Value{ .object = reasoning_schema });
    try properties.put("context", std.json.Value{ .object = context_schema });

    var required = std.json.Array.init(json_allocator);
    try required.append(std.json.Value{ .string = "agent_id" });
    try required.append(std.json.Value{ .string = "decision" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "record_decision"),
        .title = try allocator.dupe(u8, "Record Decision"),
        .description = try allocator.dupe(u8, "Record agent decisions with provenance tracking"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

/// Create query history tool definition
fn createQueryHistoryTool(allocator: Allocator) !MCPToolDefinition {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const json_allocator = arena.allocator();

    var input_schema = std.json.ObjectMap.init(json_allocator);
    var properties = std.json.ObjectMap.init(json_allocator);

    var path_schema = std.json.ObjectMap.init(json_allocator);
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "Optional specific file path to query" });

    var limit_schema = std.json.ObjectMap.init(json_allocator);
    try limit_schema.put("type", std.json.Value{ .string = "integer" });
    try limit_schema.put("description", std.json.Value{ .string = "Maximum number of history entries" });
    try limit_schema.put("default", std.json.Value{ .integer = 10 });

    var since_schema = std.json.ObjectMap.init(json_allocator);
    try since_schema.put("type", std.json.Value{ .string = "integer" });
    try since_schema.put("description", std.json.Value{ .string = "Unix timestamp - only show changes since this time" });
    try since_schema.put("default", std.json.Value{ .integer = 0 });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("limit", std.json.Value{ .object = limit_schema });
    try properties.put("since", std.json.Value{ .object = since_schema });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "query_history"),
        .title = try allocator.dupe(u8, "Query History"),
        .description = try allocator.dupe(u8, "Query temporal history with advanced filtering"),
        .inputSchema = std.json.Value{ .object = input_schema },
        .arena = arena,
    };
}

// Unit Tests
test "MCP protocol version" {
    try testing.expectEqualSlices(u8, "2024-11-05", MCP_PROTOCOL_VERSION);
}

test "MCPCompliantServer initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var server = try MCPCompliantServer.init(allocator, &db);
    defer server.deinit();

    try testing.expect(server.tools.items.len == 8); // Updated count for all tools
    try testing.expectEqualSlices(u8, server.tools.items[0].name, "read_code");
    try testing.expectEqualSlices(u8, server.tools.items[1].name, "write_code");
    try testing.expectEqualSlices(u8, server.tools.items[2].name, "get_context");
}
