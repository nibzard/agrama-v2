const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const print = std.debug.print;

const Database = @import("database.zig").Database;

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
        // Note: id and params are owned by the parsed JSON,
        // so we don't manually deinit them
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

    pub fn deinit(self: *MCPToolDefinition, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.title);
        allocator.free(self.description);
        // Note: inputSchema and outputSchema are handled by JSON arena
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

/// MCP Compliant Server Implementation
pub const MCPCompliantServer = struct {
    allocator: Allocator,
    database: *Database,
    tools: ArrayList(MCPToolDefinition),
    capabilities: ServerCapabilities,
    initialized: bool = false,
    protocol_version: []const u8,
    stdin_reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    stdout_writer: std.fs.File.Writer,

    /// Initialize MCP Compliant Server
    pub fn init(allocator: Allocator, database: *Database) !MCPCompliantServer {
        var tools = ArrayList(MCPToolDefinition).init(allocator);

        // Define read_code tool according to MCP specification
        try tools.append(try createReadCodeTool(allocator));
        try tools.append(try createWriteCodeTool(allocator));
        try tools.append(try createGetContextTool(allocator));

        const stdin = std.io.getStdIn();
        const stdout = std.io.getStdOut();

        return MCPCompliantServer{
            .allocator = allocator,
            .database = database,
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
        for (self.tools.items) |*tool| {
            tool.deinit(self.allocator);
        }
        self.tools.deinit();
    }

    /// Main server loop - processes stdin messages
    pub fn run(self: *MCPCompliantServer) !void {
        std.log.info("MCP Compliant Server starting on stdio transport", .{});

        var line_buf: [4096]u8 = undefined;

        while (true) {
            // Read line from stdin (MCP stdio transport requirement)
            if (try self.stdin_reader.reader().readUntilDelimiterOrEof(line_buf[0..], '\n')) |line| {
                try self.processMessage(line);
            } else {
                // EOF - client disconnected
                break;
            }
        }
    }

    /// Process incoming JSON-RPC message
    fn processMessage(self: *MCPCompliantServer, message: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message, .{}) catch {
            try self.sendError(null, -32700, "Parse error", null);
            return;
        };
        defer parsed.deinit();

        const request = self.parseRequest(parsed.value) catch {
            try self.sendError(null, -32600, "Invalid Request", null);
            return;
        };

        try self.handleRequest(request);
    }

    /// Parse JSON-RPC request
    fn parseRequest(self: *MCPCompliantServer, value: std.json.Value) !MCPRequest {
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
        // Build capabilities response
        var capabilities = std.json.ObjectMap.init(self.allocator);
        defer capabilities.deinit();

        var tools_capability = std.json.ObjectMap.init(self.allocator);
        defer tools_capability.deinit();
        try tools_capability.put("listChanged", std.json.Value{ .bool = false });
        try capabilities.put("tools", std.json.Value{ .object = tools_capability });

        // Build server info
        var server_info = std.json.ObjectMap.init(self.allocator);
        defer server_info.deinit();
        try server_info.put("name", std.json.Value{ .string = "agrama-codegraph" });
        try server_info.put("version", std.json.Value{ .string = "1.0.0" });

        // Build result
        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
        try result.put("protocolVersion", std.json.Value{ .string = self.protocol_version });
        try result.put("capabilities", std.json.Value{ .object = capabilities });
        try result.put("serverInfo", std.json.Value{ .object = server_info });

        try self.sendResponse(request.id, std.json.Value{ .object = result });
    }

    /// Handle initialized notification
    fn handleInitialized(self: *MCPCompliantServer, request: MCPRequest) !void {
        _ = request;
        self.initialized = true;
        std.log.info("MCP Server initialized successfully", .{});
    }

    /// Handle tools/list request
    fn handleToolsList(self: *MCPCompliantServer, request: MCPRequest) !void {
        // Dynamically generate tools list from registered tools (protocol compliant)
        var tools_array = std.json.Array.init(self.allocator);
        defer tools_array.deinit();

        for (self.tools.items) |tool| {
            var tool_obj = std.json.ObjectMap.init(self.allocator);
            defer tool_obj.deinit();

            try tool_obj.put("name", std.json.Value{ .string = try self.allocator.dupe(u8, tool.name) });
            try tool_obj.put("title", std.json.Value{ .string = try self.allocator.dupe(u8, tool.title) });
            try tool_obj.put("description", std.json.Value{ .string = try self.allocator.dupe(u8, tool.description) });
            try tool_obj.put("inputSchema", tool.inputSchema);

            if (tool.outputSchema) |output_schema| {
                try tool_obj.put("outputSchema", output_schema);
            }

            try tools_array.append(std.json.Value{ .object = tool_obj });
        }

        var result = std.json.ObjectMap.init(self.allocator);
        defer result.deinit();
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

        // Build JSON response safely using Zig's JSON handling
        var content_obj = std.json.ObjectMap.init(self.allocator);
        defer content_obj.deinit();
        try content_obj.put("type", std.json.Value{ .string = "text" });
        try content_obj.put("text", std.json.Value{ .string = text_content });

        var content_array = std.json.Array.init(self.allocator);
        defer content_array.deinit();
        try content_array.append(std.json.Value{ .object = content_obj });

        var result_obj = std.json.ObjectMap.init(self.allocator);
        defer result_obj.deinit();
        try result_obj.put("content", std.json.Value{ .array = content_array });
        try result_obj.put("isError", std.json.Value{ .bool = tool_response.isError });

        const result_value = std.json.Value{ .object = result_obj };
        try self.sendResponse(request.id, result_value);
    }

    /// Call specific tool implementation
    fn callTool(self: *MCPCompliantServer, tool_name: []const u8, arguments: std.json.Value) !MCPToolResponse {
        if (std.mem.eql(u8, tool_name, "read_code")) {
            return self.executeReadCode(arguments);
        } else if (std.mem.eql(u8, tool_name, "write_code")) {
            return self.executeWriteCode(arguments);
        } else if (std.mem.eql(u8, tool_name, "get_context")) {
            return self.executeGetContext(arguments);
        } else {
            return error.UnknownTool;
        }
    }

    /// Execute read_code tool
    fn executeReadCode(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const path_value = args_obj.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const content = self.database.getFile(path) catch |err| switch (err) {
            error.FileNotFound => "File not found",
            else => return err,
        };

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = try self.allocator.dupe(u8, content),
        };

        return MCPToolResponse{
            .content = response_content,
            .isError = false,
        };
    }

    /// Execute write_code tool
    fn executeWriteCode(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        const args_obj = arguments.object;
        const path_value = args_obj.get("path") orelse return error.MissingPath;
        const path = path_value.string;
        const content_value = args_obj.get("content") orelse return error.MissingContent;
        const content = content_value.string;

        try self.database.saveFile(path, content);

        const response_text = try std.fmt.allocPrint(self.allocator, "Successfully wrote {d} bytes to {s}", .{ content.len, path });

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

    /// Execute get_context tool
    fn executeGetContext(self: *MCPCompliantServer, arguments: std.json.Value) !MCPToolResponse {
        _ = arguments;

        const context_info = try std.fmt.allocPrint(self.allocator, "Agrama CodeGraph MCP Server\nTools available: read_code, write_code, get_context\nDatabase ready for AI collaboration", .{});

        var response_content = try self.allocator.alloc(MCPContent, 1);
        response_content[0] = MCPContent{
            .type = try self.allocator.dupe(u8, "text"),
            .text = context_info,
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
        var string = std.ArrayList(u8).init(self.allocator);
        defer string.deinit();

        try std.json.stringify(response, .{}, string.writer());
        try string.append('\n'); // MCP requires newline delimiter

        try self.stdout_writer.writeAll(string.items);
    }

    // REMOVED: escapeJsonString function - replaced with safe Zig JSON handling
    // The previous manual JSON escaping was vulnerable to:
    // 1. Incorrect Unicode escape format (decimal instead of hex)
    // 2. JSON injection through manual string construction
    // 3. Incomplete handling of edge cases
    // Now using std.json.Value for type-safe JSON construction
};

/// Create read_code tool definition
fn createReadCodeTool(allocator: Allocator) !MCPToolDefinition {
    var input_schema = std.json.ObjectMap.init(allocator);
    defer input_schema.deinit();

    var properties = std.json.ObjectMap.init(allocator);
    defer properties.deinit();

    var path_schema = std.json.ObjectMap.init(allocator);
    defer path_schema.deinit();
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "File path to read" });

    var history_schema = std.json.ObjectMap.init(allocator);
    defer history_schema.deinit();
    try history_schema.put("type", std.json.Value{ .string = "boolean" });
    try history_schema.put("description", std.json.Value{ .string = "Include file history" });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("include_history", std.json.Value{ .object = history_schema });

    var required = std.json.Array.init(allocator);
    defer required.deinit();
    try required.append(std.json.Value{ .string = "path" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "read_code"),
        .title = try allocator.dupe(u8, "Read Code File"),
        .description = try allocator.dupe(u8, "Read and analyze code files with optional history"),
        .inputSchema = std.json.Value{ .object = input_schema },
    };
}

/// Create write_code tool definition
fn createWriteCodeTool(allocator: Allocator) !MCPToolDefinition {
    var input_schema = std.json.ObjectMap.init(allocator);
    defer input_schema.deinit();

    var properties = std.json.ObjectMap.init(allocator);
    defer properties.deinit();

    var path_schema = std.json.ObjectMap.init(allocator);
    defer path_schema.deinit();
    try path_schema.put("type", std.json.Value{ .string = "string" });

    var content_schema = std.json.ObjectMap.init(allocator);
    defer content_schema.deinit();
    try content_schema.put("type", std.json.Value{ .string = "string" });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("content", std.json.Value{ .object = content_schema });

    var required = std.json.Array.init(allocator);
    defer required.deinit();
    try required.append(std.json.Value{ .string = "path" });
    try required.append(std.json.Value{ .string = "content" });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });
    try input_schema.put("required", std.json.Value{ .array = required });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "write_code"),
        .title = try allocator.dupe(u8, "Write Code File"),
        .description = try allocator.dupe(u8, "Write or modify code files with provenance tracking"),
        .inputSchema = std.json.Value{ .object = input_schema },
    };
}

/// Create get_context tool definition
fn createGetContextTool(allocator: Allocator) !MCPToolDefinition {
    var input_schema = std.json.ObjectMap.init(allocator);
    var properties = std.json.ObjectMap.init(allocator);

    // Add optional parameters for context tool
    var path_schema = std.json.ObjectMap.init(allocator);
    try path_schema.put("type", std.json.Value{ .string = "string" });
    try path_schema.put("description", std.json.Value{ .string = "Optional file path for specific context" });

    var type_schema = std.json.ObjectMap.init(allocator);
    try type_schema.put("type", std.json.Value{ .string = "string" });
    try type_schema.put("description", std.json.Value{ .string = "Context type: 'full', 'metrics', or 'agents'" });
    try type_schema.put("default", std.json.Value{ .string = "full" });

    try properties.put("path", std.json.Value{ .object = path_schema });
    try properties.put("type", std.json.Value{ .object = type_schema });

    try input_schema.put("type", std.json.Value{ .string = "object" });
    try input_schema.put("properties", std.json.Value{ .object = properties });

    return MCPToolDefinition{
        .name = try allocator.dupe(u8, "get_context"),
        .title = try allocator.dupe(u8, "Get Context"),
        .description = try allocator.dupe(u8, "Get comprehensive contextual information"),
        .inputSchema = std.json.Value{ .object = input_schema },
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

    try testing.expect(server.tools.items.len == 3);
    try testing.expectEqualSlices(u8, server.tools.items[0].name, "read_code");
    try testing.expectEqualSlices(u8, server.tools.items[1].name, "write_code");
    try testing.expectEqualSlices(u8, server.tools.items[2].name, "get_context");
}
