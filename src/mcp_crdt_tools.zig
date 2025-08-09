const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const Database = @import("database.zig").Database;
const CRDTManager = @import("crdt_manager.zig").CRDTManager;
const crdt = @import("crdt.zig");
const MCPServer = @import("mcp_server.zig").MCPServer;

const CRDTOperation = crdt.CRDTOperation;
const Position = crdt.Position;
const OperationType = crdt.OperationType;

/// Enhanced MCP context with CRDT support
pub const MCPCRDTContext = struct {
    agent_id: []const u8,
    agent_name: []const u8,
    database: *Database,
    crdt_manager: *CRDTManager,
    allocator: Allocator,
};

/// Enhanced read_code tool with collaborative awareness
pub const ReadCodeCRDTTool = struct {
    pub const name = "read_code_collaborative";
    pub const description = "Read code file with real-time collaborative context";

    pub fn execute(arguments: std.json.Value, context: MCPCRDTContext) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const include_cursors = if (arguments.object.get("include_agent_cursors")) |v| v.bool else true;
        const include_recent_ops = if (arguments.object.get("include_recent_changes")) |v| v.bool else true;
        const include_history = if (arguments.object.get("include_history")) |v| v.bool else false;
        const history_limit = if (arguments.object.get("history_limit")) |v| @as(usize, @intCast(v.integer)) else 5;

        // Get collaborative context from CRDT manager
        var collaborative_context = try context.crdt_manager.getCollaborativeContext(path, include_cursors, include_recent_ops);
        defer collaborative_context.deinit(context.allocator);

        // Create result object
        var result = std.json.ObjectMap.init(context.allocator);
        try result.put("path", std.json.Value{ .string = path });
        try result.put("content", std.json.Value{ .string = collaborative_context.content });
        try result.put("exists", std.json.Value{ .bool = collaborative_context.content.len > 0 });

        // Add collaborative information
        if (collaborative_context.agent_cursors) |cursors| {
            var cursors_array = std.json.Array.init(context.allocator);
            for (cursors) |cursor| {
                var cursor_obj = std.json.ObjectMap.init(context.allocator);
                try cursor_obj.put("agent_id", std.json.Value{ .string = cursor.agent_id });
                try cursor_obj.put("agent_name", std.json.Value{ .string = cursor.agent_name });

                var position_obj = std.json.ObjectMap.init(context.allocator);
                try position_obj.put("line", std.json.Value{ .integer = @as(i64, @intCast(cursor.position.line)) });
                try position_obj.put("column", std.json.Value{ .integer = @as(i64, @intCast(cursor.position.column)) });
                try position_obj.put("offset", std.json.Value{ .integer = @as(i64, @intCast(cursor.position.offset)) });
                try cursor_obj.put("position", std.json.Value{ .object = position_obj });

                try cursor_obj.put("updated_at", std.json.Value{ .integer = cursor.updated_at });
                try cursors_array.append(std.json.Value{ .object = cursor_obj });
            }
            try result.put("agent_cursors", std.json.Value{ .array = cursors_array });
        }

        // Add recent collaborative operations
        if (collaborative_context.recent_operations) |operations| {
            var ops_array = std.json.Array.init(context.allocator);
            for (operations) |operation| {
                var op_obj = std.json.ObjectMap.init(context.allocator);
                try op_obj.put("operation_id", std.json.Value{ .integer = @as(i64, @intCast(operation.operation_id & 0x7FFFFFFFFFFFFFFF)) });
                try op_obj.put("agent_id", std.json.Value{ .string = operation.agent_id });
                try op_obj.put("operation_type", std.json.Value{ .string = @tagName(operation.operation_type) });

                var position_obj = std.json.ObjectMap.init(context.allocator);
                try position_obj.put("line", std.json.Value{ .integer = @as(i64, @intCast(operation.position.line)) });
                try position_obj.put("column", std.json.Value{ .integer = @as(i64, @intCast(operation.position.column)) });
                try position_obj.put("offset", std.json.Value{ .integer = @as(i64, @intCast(operation.position.offset)) });
                try op_obj.put("position", std.json.Value{ .object = position_obj });

                try op_obj.put("content_preview", std.json.Value{ .string = if (operation.content.len > 50)
                    operation.content[0..47] ++ "..."
                else
                    operation.content });
                try op_obj.put("created_at", std.json.Value{ .integer = operation.created_at });
                try ops_array.append(std.json.Value{ .object = op_obj });
            }
            try result.put("recent_operations", std.json.Value{ .array = ops_array });
        }

        // Add conflict information
        if (collaborative_context.conflicts) |conflicts| {
            var conflicts_array = std.json.Array.init(context.allocator);
            for (conflicts) |conflict| {
                var conflict_obj = std.json.ObjectMap.init(context.allocator);
                try conflict_obj.put("conflict_id", std.json.Value{ .integer = @as(i64, @intCast(conflict.conflict_id & 0x7FFFFFFFFFFFFFFF)) });
                try conflict_obj.put("operations_count", std.json.Value{ .integer = @as(i64, @intCast(conflict.conflicting_operations.items.len)) });
                try conflict_obj.put("detected_at", std.json.Value{ .integer = conflict.detected_at });
                try conflict_obj.put("resolved", std.json.Value{ .bool = conflict.resolved_at != null });
                try conflicts_array.append(std.json.Value{ .object = conflict_obj });
            }
            try result.put("conflicts", std.json.Value{ .array = conflicts_array });
        }

        // Add traditional history if requested
        if (include_history) {
            const history = context.database.getHistory(path, history_limit) catch |err| switch (err) {
                error.FileNotFound => &[_]@import("database.zig").Change{},
                else => return err,
            };
            defer if (history.len > 0) context.allocator.free(history);

            var history_array = std.json.Array.init(context.allocator);
            for (history) |change| {
                var change_obj = std.json.ObjectMap.init(context.allocator);
                try change_obj.put("timestamp", std.json.Value{ .integer = change.timestamp });
                try change_obj.put("content_preview", std.json.Value{ .string = if (change.content.len > 100)
                    change.content[0..97] ++ "..."
                else
                    change.content });
                try history_array.append(std.json.Value{ .object = change_obj });
            }
            try result.put("history", std.json.Value{ .array = history_array });
        }

        return std.json.Value{ .object = result };
    }
};

/// Enhanced write_code tool with CRDT conflict resolution
pub const WriteCodeCRDTTool = struct {
    pub const name = "write_code_collaborative";
    pub const description = "Write code with CRDT conflict resolution";

    pub fn execute(arguments: std.json.Value, context: MCPCRDTContext) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        const content_value = arguments.object.get("content") orelse return error.MissingContent;
        const content = content_value.string;

        const reasoning_value = arguments.object.get("reasoning") orelse return error.MissingReasoning;
        const reasoning = reasoning_value.string;

        // Parse operation type
        const operation_type_str = if (arguments.object.get("operation_type")) |v| v.string else "modify";
        const operation_type = std.meta.stringToEnum(OperationType, operation_type_str) orelse .modify;

        // Parse position (default to beginning of file)
        var position = Position{ .line = 1, .column = 0, .offset = 0 };
        if (arguments.object.get("position")) |pos_value| {
            if (pos_value.object.get("line")) |line_val| {
                position.line = @as(u32, @intCast(line_val.integer));
            }
            if (pos_value.object.get("column")) |col_val| {
                position.column = @as(u32, @intCast(col_val.integer));
            }
            if (pos_value.object.get("offset")) |offset_val| {
                position.offset = @as(u64, @intCast(offset_val.integer));
            }
        }

        // Create CRDT operation
        const operation = try context.crdt_manager.createWriteOperation(context.agent_id, path, operation_type, position, content);
        defer {
            var mutable_op = operation;
            mutable_op.deinit(context.allocator);
        }

        // Apply operation with conflict resolution
        try context.crdt_manager.applyOperation(operation);

        // Get updated collaborative context to show results
        var collaborative_context = try context.crdt_manager.getCollaborativeContext(path, true, false);
        defer collaborative_context.deinit(context.allocator);

        // Create result
        var result = std.json.ObjectMap.init(context.allocator);
        try result.put("path", std.json.Value{ .string = path });
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("operation_id", std.json.Value{ .integer = @as(i64, @intCast(operation.operation_id & 0x7FFFFFFFFFFFFFFF)) });
        try result.put("operation_type", std.json.Value{ .string = @tagName(operation_type) });
        try result.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });
        try result.put("reasoning", std.json.Value{ .string = reasoning });

        // Include final merged content
        try result.put("merged_content_length", std.json.Value{ .integer = @as(i64, @intCast(collaborative_context.content.len)) });

        // Show any conflicts that were detected/resolved
        if (collaborative_context.conflicts) |conflicts| {
            try result.put("conflicts_detected", std.json.Value{ .integer = @as(i64, @intCast(conflicts.len)) });

            if (conflicts.len > 0) {
                var conflict_summaries = std.json.Array.init(context.allocator);
                for (conflicts) |conflict| {
                    var conflict_obj = std.json.ObjectMap.init(context.allocator);
                    try conflict_obj.put("conflict_id", std.json.Value{ .integer = @as(i64, @intCast(conflict.conflict_id & 0x7FFFFFFFFFFFFFFF)) });
                    try conflict_obj.put("operations_involved", std.json.Value{ .integer = @as(i64, @intCast(conflict.conflicting_operations.items.len)) });
                    try conflict_obj.put("auto_resolved", std.json.Value{ .bool = conflict.resolved_at != null });
                    if (conflict.resolution_strategy) |strategy| {
                        try conflict_obj.put("resolution_strategy", std.json.Value{ .string = @tagName(strategy) });
                    }
                    try conflict_summaries.append(std.json.Value{ .object = conflict_obj });
                }
                try result.put("conflict_details", std.json.Value{ .array = conflict_summaries });
            }
        } else {
            try result.put("conflicts_detected", std.json.Value{ .integer = 0 });
        }

        // Show current collaborative state
        if (collaborative_context.agent_cursors) |cursors| {
            try result.put("active_agents", std.json.Value{ .integer = @as(i64, @intCast(cursors.len)) });
        } else {
            try result.put("active_agents", std.json.Value{ .integer = 0 });
        }

        return std.json.Value{ .object = result };
    }
};

/// Tool for updating agent cursor position in collaborative editing
pub const UpdateCursorTool = struct {
    pub const name = "update_cursor";
    pub const description = "Update agent cursor position for collaborative editing visualization";

    pub fn execute(arguments: std.json.Value, context: MCPCRDTContext) !std.json.Value {
        const path_value = arguments.object.get("path") orelse return error.MissingPath;
        const path = path_value.string;

        // Parse cursor position
        var position = Position{ .line = 1, .column = 0, .offset = 0 };
        if (arguments.object.get("position")) |pos_value| {
            if (pos_value.object.get("line")) |line_val| {
                position.line = @as(u32, @intCast(line_val.integer));
            }
            if (pos_value.object.get("column")) |col_val| {
                position.column = @as(u32, @intCast(col_val.integer));
            }
            if (pos_value.object.get("offset")) |offset_val| {
                position.offset = @as(u64, @intCast(offset_val.integer));
            }
        }

        // Update cursor position
        try context.crdt_manager.updateAgentCursor(context.agent_id, path, position);

        // Create result
        var result = std.json.ObjectMap.init(context.allocator);
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("agent_id", std.json.Value{ .string = context.agent_id });
        try result.put("path", std.json.Value{ .string = path });

        var position_obj = std.json.ObjectMap.init(context.allocator);
        try position_obj.put("line", std.json.Value{ .integer = @as(i64, @intCast(position.line)) });
        try position_obj.put("column", std.json.Value{ .integer = @as(i64, @intCast(position.column)) });
        try position_obj.put("offset", std.json.Value{ .integer = @as(i64, @intCast(position.offset)) });
        try result.put("position", std.json.Value{ .object = position_obj });

        try result.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });

        return std.json.Value{ .object = result };
    }
};

/// Tool for getting comprehensive collaborative context
pub const GetCollaborativeContextTool = struct {
    pub const name = "get_collaborative_context";
    pub const description = "Get comprehensive collaborative editing context and statistics";

    pub fn execute(arguments: std.json.Value, context: MCPCRDTContext) !std.json.Value {
        const path_value = arguments.object.get("path");
        const context_type_value = arguments.object.get("type");
        const context_type = if (context_type_value) |v| v.string else "full";

        var result = std.json.ObjectMap.init(context.allocator);

        // Get CRDT manager statistics
        const crdt_stats = context.crdt_manager.getStats();
        var stats_obj = std.json.ObjectMap.init(context.allocator);
        try stats_obj.put("active_agents", std.json.Value{ .integer = @as(i64, @intCast(crdt_stats.active_agents)) });
        try stats_obj.put("active_documents", std.json.Value{ .integer = @as(i64, @intCast(crdt_stats.active_documents)) });
        try stats_obj.put("total_operations", std.json.Value{ .integer = @as(i64, @intCast(crdt_stats.total_operations)) });
        try stats_obj.put("total_conflicts", std.json.Value{ .integer = @as(i64, @intCast(crdt_stats.total_conflicts)) });
        try stats_obj.put("global_conflicts", std.json.Value{ .integer = @as(i64, @intCast(crdt_stats.global_conflicts)) });
        try result.put("crdt_stats", std.json.Value{ .object = stats_obj });

        // Add specific file context if path provided
        if (path_value) |pv| {
            const path = pv.string;

            var file_context = try context.crdt_manager.getCollaborativeContext(path, true, true // Include cursors and recent ops
            );
            defer file_context.deinit(context.allocator);

            var file_obj = std.json.ObjectMap.init(context.allocator);
            try file_obj.put("path", std.json.Value{ .string = path });
            try file_obj.put("content_length", std.json.Value{ .integer = @as(i64, @intCast(file_context.content.len)) });

            // Agent information for this file
            if (file_context.agent_cursors) |cursors| {
                try file_obj.put("active_agents_count", std.json.Value{ .integer = @as(i64, @intCast(cursors.len)) });

                var agents_array = std.json.Array.init(context.allocator);
                for (cursors) |cursor| {
                    var agent_obj = std.json.ObjectMap.init(context.allocator);
                    try agent_obj.put("agent_id", std.json.Value{ .string = cursor.agent_id });
                    try agent_obj.put("agent_name", std.json.Value{ .string = cursor.agent_name });
                    try agent_obj.put("last_activity", std.json.Value{ .integer = cursor.updated_at });
                    try agents_array.append(std.json.Value{ .object = agent_obj });
                }
                try file_obj.put("active_agents", std.json.Value{ .array = agents_array });
            }

            // Recent collaborative activity
            if (file_context.recent_operations) |operations| {
                try file_obj.put("recent_operations_count", std.json.Value{ .integer = @as(i64, @intCast(operations.len)) });
            }

            // Conflict status
            if (file_context.conflicts) |conflicts| {
                try file_obj.put("unresolved_conflicts", std.json.Value{ .integer = @as(i64, @intCast(conflicts.len)) });
            }

            try result.put("file_context", std.json.Value{ .object = file_obj });
        }

        try result.put("context_type", std.json.Value{ .string = context_type });
        try result.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });

        return std.json.Value{ .object = result };
    }
};

/// Tool registry for CRDT-enhanced MCP tools
pub const CRDTToolRegistry = struct {
    pub fn registerTools(mcp_server: *MCPServer, crdt_manager: *CRDTManager) !void {
        // Note: This is a conceptual implementation
        // The actual MCP server would need to be modified to support CRDT tools
        _ = mcp_server;
        _ = crdt_manager;

        std.log.info("CRDT tools would be registered: {s}, {s}, {s}, {s}", .{
            ReadCodeCRDTTool.name,
            WriteCodeCRDTTool.name,
            UpdateCursorTool.name,
            GetCollaborativeContextTool.name,
        });
    }
};

// Unit Tests
test "ReadCodeCRDTTool execution with collaborative context" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var ws_server = @import("websocket.zig").WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var crdt_manager = try CRDTManager.init(allocator, &db, &ws_server);
    defer crdt_manager.deinit();

    // Register agent and create test file
    try crdt_manager.registerAgent("agent-1", "Test Agent");
    try db.saveFile("test.txt", "Hello, collaborative world!");

    // Create context
    const context = MCPCRDTContext{
        .agent_id = "agent-1",
        .agent_name = "Test Agent",
        .database = &db,
        .crdt_manager = &crdt_manager,
        .allocator = allocator,
    };

    // Create arguments
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    try arguments.put("path", std.json.Value{ .string = "test.txt" });
    try arguments.put("include_agent_cursors", std.json.Value{ .bool = true });

    // Execute tool
    var result = try ReadCodeCRDTTool.execute(std.json.Value{ .object = arguments }, context);
    defer result.object.deinit();

    // Verify results
    try testing.expect(result.object.get("exists").?.bool == true);
    try testing.expect(result.object.contains("agent_cursors"));
    try testing.expectEqualSlices(u8, "test.txt", result.object.get("path").?.string);
}

test "WriteCodeCRDTTool execution with operation creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var ws_server = @import("websocket.zig").WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var crdt_manager = try CRDTManager.init(allocator, &db, &ws_server);
    defer crdt_manager.deinit();

    // Register agent
    try crdt_manager.registerAgent("agent-1", "Test Agent");

    // Create context
    const context = MCPCRDTContext{
        .agent_id = "agent-1",
        .agent_name = "Test Agent",
        .database = &db,
        .crdt_manager = &crdt_manager,
        .allocator = allocator,
    };

    // Create arguments
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    try arguments.put("path", std.json.Value{ .string = "new_file.txt" });
    try arguments.put("content", std.json.Value{ .string = "Hello, CRDT!" });
    try arguments.put("reasoning", std.json.Value{ .string = "Testing CRDT write operation" });
    try arguments.put("operation_type", std.json.Value{ .string = "insert" });

    // Execute tool
    var result = try WriteCodeCRDTTool.execute(std.json.Value{ .object = arguments }, context);
    defer result.object.deinit();

    // Verify results
    try testing.expect(result.object.get("success").?.bool == true);
    try testing.expect(result.object.contains("operation_id"));
    try testing.expectEqualSlices(u8, "new_file.txt", result.object.get("path").?.string);
    try testing.expect(result.object.get("conflicts_detected").?.integer == 0);

    // Verify file was actually saved to database
    const saved_content = try db.getFile("new_file.txt");
    try testing.expectEqualSlices(u8, "Hello, CRDT!", saved_content);
}
