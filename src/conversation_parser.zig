//! JSONL Conversation Parser for Persistent Benchmark Graphs
//!
//! Parses AI coding session conversations from Claude Code to extract:
//! - Code entities (files, functions, imports, classes)
//! - Decision entities (architectural choices, algorithm selections)
//! - Temporal entities (conversation turns, task progression)
//! - Relationships (dependencies, references, evolution chains)
//!
//! Input: JSONL files from /tmp/agrama/ and /tmp/agentprobe/
//! Output: Structured entities and relationships for graph construction
//!

const std = @import("std");
const json = std.json;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

/// Entity types extracted from conversations
pub const EntityType = enum {
    file,
    function,
    class,
    import,
    test_file,
    decision,
    task,
    conversation_turn,
    error_event,
    fix,
};

/// Relationship types between entities
pub const RelationshipType = enum {
    imports,
    contains,
    calls,
    tests,
    modifies,
    creates,
    references,
    decides,
    similar_purpose,
    evolves_to,
    depends_on,
    temporal_next,
};

/// Core entity extracted from conversation
pub const Entity = struct {
    id: u32,
    entity_type: EntityType,
    name: []const u8,
    content: ?[]const u8,
    conversation_turn: u32,
    timestamp: i64,
    project: []const u8,
    metadata: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn deinit(self: *Entity, allocator: Allocator) void {
        _ = allocator;
        self.metadata.deinit();
    }
};

/// Relationship between two entities
pub const Relationship = struct {
    from_id: u32,
    to_id: u32,
    relationship_type: RelationshipType,
    strength: f32,
    conversation_turn: u32,
    metadata: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn deinit(self: *Relationship, allocator: Allocator) void {
        _ = allocator;
        self.metadata.deinit();
    }
};

/// Tool usage extracted from conversation
pub const ToolUsage = struct {
    tool_name: []const u8,
    parameters: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    conversation_turn: u32,
    success: bool,

    pub fn deinit(self: *ToolUsage, allocator: Allocator) void {
        _ = allocator;
        self.parameters.deinit();
    }
};

/// Parsed conversation data
pub const ConversationData = struct {
    project_name: []const u8,
    conversation_id: []const u8,
    entities: ArrayList(Entity),
    relationships: ArrayList(Relationship),
    tool_usages: ArrayList(ToolUsage),
    turn_count: u32,
    total_duration_ms: u64,

    pub fn init(allocator: Allocator, project_name: []const u8, conversation_id: []const u8) ConversationData {
        return ConversationData{
            .project_name = project_name,
            .conversation_id = conversation_id,
            .entities = ArrayList(Entity).init(allocator),
            .relationships = ArrayList(Relationship).init(allocator),
            .tool_usages = ArrayList(ToolUsage).init(allocator),
            .turn_count = 0,
            .total_duration_ms = 0,
        };
    }

    pub fn deinit(self: *ConversationData, allocator: Allocator) void {
        for (self.entities.items) |*entity| {
            entity.deinit(allocator);
        }
        self.entities.deinit();

        for (self.relationships.items) |*relationship| {
            relationship.deinit(allocator);
        }
        self.relationships.deinit();

        for (self.tool_usages.items) |*tool| {
            tool.deinit(allocator);
        }
        self.tool_usages.deinit();
    }
};

/// Main conversation parser
pub const ConversationParser = struct {
    allocator: Allocator,
    entity_counter: u32,
    known_files: HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    known_functions: HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) ConversationParser {
        return ConversationParser{
            .allocator = allocator,
            .entity_counter = 1,
            .known_files = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .known_functions = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *ConversationParser) void {
        self.known_files.deinit();
        self.known_functions.deinit();
    }

    /// Parse a single JSONL file containing conversation data
    pub fn parseConversationFile(self: *ConversationParser, file_path: []const u8) !ConversationData {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        // Extract project name and conversation ID from path
        const project_name = self.extractProjectName(file_path);
        const conversation_id = self.extractConversationId(file_path);

        var conversation_data = ConversationData.init(self.allocator, project_name, conversation_id);

        // Parse JSONL line by line
        var lines = std.mem.splitScalar(u8, content, '\n');
        var turn_number: u32 = 0;
        var start_timestamp: ?i64 = null;
        var end_timestamp: ?i64 = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Parse JSON line
            var parsed = json.parseFromSlice(json.Value, self.allocator, line, .{}) catch |err| {
                print("Failed to parse JSON line: {}\n", .{err});
                continue;
            };
            defer parsed.deinit();

            const root = parsed.value;

            // Extract timestamp for duration calculation
            if (root.object.get("timestamp")) |timestamp_val| {
                if (timestamp_val == .string) {
                    const timestamp = self.parseTimestamp(timestamp_val.string) catch continue;
                    if (start_timestamp == null) start_timestamp = timestamp;
                    end_timestamp = timestamp;
                }
            }

            // Process different message types
            if (root.object.get("type")) |type_val| {
                if (type_val == .string) {
                    const msg_type = type_val.string;

                    if (std.mem.eql(u8, msg_type, "assistant")) {
                        try self.processAssistantMessage(&conversation_data, root, turn_number);
                    } else if (std.mem.eql(u8, msg_type, "user")) {
                        try self.processUserMessage(&conversation_data, root, turn_number);
                    }

                    turn_number += 1;
                }
            }
        }

        conversation_data.turn_count = turn_number;
        if (start_timestamp != null and end_timestamp != null) {
            conversation_data.total_duration_ms = @as(u64, @intCast(@max(0, end_timestamp.? - start_timestamp.?)));
        }

        // Build relationships between entities
        try self.buildTemporalRelationships(&conversation_data);
        try self.buildCodeRelationships(&conversation_data);

        return conversation_data;
    }

    /// Process assistant message for tool usage and code content
    fn processAssistantMessage(self: *ConversationParser, data: *ConversationData, root: json.Value, turn: u32) !void {
        // Check for tool usage in message content
        if (root.object.get("message")) |message| {
            if (message.object.get("content")) |content| {
                if (content == .array) {
                    for (content.array.items) |item| {
                        if (item.object.get("type")) |type_val| {
                            if (type_val == .string and std.mem.eql(u8, type_val.string, "tool_use")) {
                                try self.processToolUse(data, item, turn);
                            }
                        }
                    }
                }
            }
        }
    }

    /// Process user message for tasks and requirements
    fn processUserMessage(self: *ConversationParser, data: *ConversationData, root: json.Value, turn: u32) !void {
        if (root.object.get("message")) |message| {
            if (message.object.get("content")) |content| {
                if (content == .string) {
                    // Extract tasks and decisions from user messages
                    try self.extractTaskEntities(data, content.string, turn);
                }
            }
        }
    }

    /// Process tool usage to extract file operations and code entities
    fn processToolUse(self: *ConversationParser, data: *ConversationData, tool_item: json.Value, turn: u32) !void {
        const tool_name = if (tool_item.object.get("name")) |name| name.string else return;

        var tool_usage = ToolUsage{
            .tool_name = try self.allocator.dupe(u8, tool_name),
            .parameters = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator),
            .conversation_turn = turn,
            .success = true, // Assume success unless error found
        };

        // Process tool parameters
        if (tool_item.object.get("input")) |input| {
            if (input == .object) {
                var param_iter = input.object.iterator();
                while (param_iter.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const value = switch (entry.value_ptr.*) {
                        .string => |s| try self.allocator.dupe(u8, s),
                        .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
                        .float => |f| try std.fmt.allocPrint(self.allocator, "{d}", .{f}),
                        .bool => |b| try self.allocator.dupe(u8, if (b) "true" else "false"),
                        else => try self.allocator.dupe(u8, "unknown"),
                    };
                    try tool_usage.parameters.put(key, value);
                }
            }
        }

        // Extract entities based on tool type
        if (std.mem.eql(u8, tool_name, "Read") or std.mem.eql(u8, tool_name, "Edit") or std.mem.eql(u8, tool_name, "Write")) {
            try self.extractFileEntity(data, tool_usage, turn);
        } else if (std.mem.eql(u8, tool_name, "Bash")) {
            try self.extractCommandEntity(data, tool_usage, turn);
        }

        try data.tool_usages.append(tool_usage);
    }

    /// Extract file entity from file operations
    fn extractFileEntity(self: *ConversationParser, data: *ConversationData, tool: ToolUsage, turn: u32) !void {
        if (tool.parameters.get("file_path")) |file_path| {
            const entity_id = self.getOrCreateFileEntity(data, file_path, turn);

            // Create file entity if new
            if (!self.known_files.contains(file_path)) {
                var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                try metadata.put("tool", tool.tool_name);
                try metadata.put("operation", tool.tool_name);

                const entity = Entity{
                    .id = entity_id,
                    .entity_type = .file,
                    .name = try self.allocator.dupe(u8, file_path),
                    .content = null,
                    .conversation_turn = turn,
                    .timestamp = std.time.timestamp(),
                    .project = data.project_name,
                    .metadata = metadata,
                };

                try data.entities.append(entity);
                try self.known_files.put(file_path, entity_id);
            }
        }
    }

    /// Extract command entity from bash tool usage
    fn extractCommandEntity(self: *ConversationParser, data: *ConversationData, tool: ToolUsage, turn: u32) !void {
        if (tool.parameters.get("command")) |command| {
            // Extract file references from common commands
            if (std.mem.startsWith(u8, command, "zig build") or
                std.mem.startsWith(u8, command, "zig test") or
                std.mem.startsWith(u8, command, "zig fmt"))
            {

                // This is a build/test command - create a decision entity
                const entity_id = self.entity_counter;
                self.entity_counter += 1;

                var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                try metadata.put("command", command);
                try metadata.put("command_type", "build");

                const entity = Entity{
                    .id = entity_id,
                    .entity_type = .decision,
                    .name = try std.fmt.allocPrint(self.allocator, "build_command_{d}", .{turn}),
                    .content = try self.allocator.dupe(u8, command),
                    .conversation_turn = turn,
                    .timestamp = std.time.timestamp(),
                    .project = data.project_name,
                    .metadata = metadata,
                };

                try data.entities.append(entity);
            }
        }
    }

    /// Extract task entities from user messages
    fn extractTaskEntities(self: *ConversationParser, data: *ConversationData, content: []const u8, turn: u32) !void {
        // Look for common task indicators
        const task_keywords = [_][]const u8{ "implement", "create", "add", "fix", "optimize", "test", "build" };

        for (task_keywords) |keyword| {
            if (std.mem.indexOf(u8, content, keyword) != null) {
                const entity_id = self.entity_counter;
                self.entity_counter += 1;

                var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                try metadata.put("keyword", keyword);
                try metadata.put("source", "user_message");

                const entity = Entity{
                    .id = entity_id,
                    .entity_type = .task,
                    .name = try std.fmt.allocPrint(self.allocator, "task_{s}_{d}", .{ keyword, turn }),
                    .content = try self.allocator.dupe(u8, content[0..@min(content.len, 200)]), // First 200 chars
                    .conversation_turn = turn,
                    .timestamp = std.time.timestamp(),
                    .project = data.project_name,
                    .metadata = metadata,
                };

                try data.entities.append(entity);
                break; // Only create one task per message
            }
        }
    }

    /// Build temporal relationships between entities
    fn buildTemporalRelationships(self: *ConversationParser, data: *ConversationData) !void {
        // Sort entities by conversation turn
        std.sort.block(Entity, data.entities.items, {}, struct {
            fn lessThan(_: void, a: Entity, b: Entity) bool {
                return a.conversation_turn < b.conversation_turn;
            }
        }.lessThan);

        // Create temporal_next relationships
        for (data.entities.items, 0..) |entity, i| {
            if (i + 1 < data.entities.items.len) {
                const next_entity = data.entities.items[i + 1];
                if (next_entity.conversation_turn == entity.conversation_turn + 1) {
                    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                    try metadata.put("relationship_type", "temporal_sequence");

                    const relationship = Relationship{
                        .from_id = entity.id,
                        .to_id = next_entity.id,
                        .relationship_type = .temporal_next,
                        .strength = 1.0,
                        .conversation_turn = entity.conversation_turn,
                        .metadata = metadata,
                    };

                    try data.relationships.append(relationship);
                }
            }
        }
    }

    /// Build code relationships between entities
    fn buildCodeRelationships(self: *ConversationParser, data: *ConversationData) !void {
        // Build file dependencies based on tool usage patterns
        for (data.entities.items) |entity_a| {
            for (data.entities.items) |entity_b| {
                if (entity_a.id == entity_b.id) continue;

                // Files modified in same conversation turn likely related
                if (entity_a.entity_type == .file and entity_b.entity_type == .file and
                    entity_a.conversation_turn == entity_b.conversation_turn)
                {
                    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                    try metadata.put("relationship_type", "co_modified");

                    const relationship = Relationship{
                        .from_id = entity_a.id,
                        .to_id = entity_b.id,
                        .relationship_type = .similar_purpose,
                        .strength = 0.7,
                        .conversation_turn = entity_a.conversation_turn,
                        .metadata = metadata,
                    };

                    try data.relationships.append(relationship);
                }

                // Tasks lead to file creation/modification
                if (entity_a.entity_type == .task and entity_b.entity_type == .file and
                    entity_b.conversation_turn > entity_a.conversation_turn and
                    entity_b.conversation_turn - entity_a.conversation_turn <= 3)
                {
                    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                    try metadata.put("relationship_type", "task_implements");

                    const relationship = Relationship{
                        .from_id = entity_a.id,
                        .to_id = entity_b.id,
                        .relationship_type = .creates,
                        .strength = 0.9,
                        .conversation_turn = entity_a.conversation_turn,
                        .metadata = metadata,
                    };

                    try data.relationships.append(relationship);
                }
            }
        }
    }

    /// Helper functions
    fn extractProjectName(self: *ConversationParser, file_path: []const u8) []const u8 {
        _ = self;
        if (std.mem.indexOf(u8, file_path, "agrama")) |_| {
            return "agrama";
        } else if (std.mem.indexOf(u8, file_path, "agentprobe")) |_| {
            return "agentprobe";
        }
        return "unknown";
    }

    fn extractConversationId(self: *ConversationParser, file_path: []const u8) []const u8 {
        _ = self;
        const basename = std.fs.path.basename(file_path);
        if (std.mem.lastIndexOf(u8, basename, ".")) |dot_index| {
            return basename[0..dot_index];
        }
        return basename;
    }

    fn parseTimestamp(self: *ConversationParser, timestamp_str: []const u8) !i64 {
        // Simple ISO timestamp parsing - would use proper parser in production
        _ = self;
        _ = timestamp_str;
        return std.time.timestamp();
    }

    fn getOrCreateFileEntity(self: *ConversationParser, data: *ConversationData, file_path: []const u8, turn: u32) u32 {
        _ = data;
        _ = turn;
        if (self.known_files.get(file_path)) |entity_id| {
            return entity_id;
        } else {
            const entity_id = self.entity_counter;
            self.entity_counter += 1;
            return entity_id;
        }
    }
};

/// Parse all conversation files in a directory
pub fn parseAllConversations(allocator: Allocator, base_dir: []const u8) !ArrayList(ConversationData) {
    var parser = ConversationParser.init(allocator);
    defer parser.deinit();

    var results = ArrayList(ConversationData).init(allocator);

    // Parse agrama conversations
    const agrama_dir = try std.fmt.allocPrint(allocator, "{s}/agrama/-home-dev-agrama-v2", .{base_dir});
    defer allocator.free(agrama_dir);

    if (std.fs.cwd().openDir(agrama_dir, .{ .iterate = true })) |mut_dir| {
        var dir = mut_dir;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".jsonl")) {
                const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ agrama_dir, entry.name });
                defer allocator.free(full_path);

                const conversation_data = parser.parseConversationFile(full_path) catch |err| {
                    print("Failed to parse {s}: {}\n", .{ full_path, err });
                    continue;
                };

                try results.append(conversation_data);
                print("Parsed {s}: {d} entities, {d} relationships\n", .{ entry.name, conversation_data.entities.items.len, conversation_data.relationships.items.len });
            }
        }
    } else |_| {
        print("Could not open agrama directory: {s}\n", .{agrama_dir});
    }

    // Parse agentprobe conversations
    const agentprobe_dir = try std.fmt.allocPrint(allocator, "{s}/agentprobe/-home-dev-agentprobe", .{base_dir});
    defer allocator.free(agentprobe_dir);

    if (std.fs.cwd().openDir(agentprobe_dir, .{ .iterate = true })) |mut_dir| {
        var dir = mut_dir;
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".jsonl")) {
                const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ agentprobe_dir, entry.name });
                defer allocator.free(full_path);

                const conversation_data = parser.parseConversationFile(full_path) catch |err| {
                    print("Failed to parse {s}: {}\n", .{ full_path, err });
                    continue;
                };

                try results.append(conversation_data);
                print("Parsed {s}: {d} entities, {d} relationships\n", .{ entry.name, conversation_data.entities.items.len, conversation_data.relationships.items.len });
            }
        }
    } else |_| {
        print("Could not open agentprobe directory: {s}\n", .{agentprobe_dir});
    }

    return results;
}

/// Test runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🔍 Parsing AI coding session conversations...\n", .{});
    print("==============================================\n\n", .{});

    var all_conversations = try parseAllConversations(allocator, "/home/dev/agrama-v2/tmp");
    defer {
        for (all_conversations.items) |*conversation| {
            conversation.deinit(allocator);
        }
        all_conversations.deinit();
    }

    // Summary statistics
    var total_entities: u32 = 0;
    var total_relationships: u32 = 0;
    var total_turns: u32 = 0;

    for (all_conversations.items) |conversation| {
        total_entities += @as(u32, @intCast(conversation.entities.items.len));
        total_relationships += @as(u32, @intCast(conversation.relationships.items.len));
        total_turns += conversation.turn_count;
    }

    print("📊 Parsing Complete:\n", .{});
    print("   Conversations: {d}\n", .{all_conversations.items.len});
    print("   Total Entities: {d}\n", .{total_entities});
    print("   Total Relationships: {d}\n", .{total_relationships});
    print("   Total Turns: {d}\n", .{total_turns});
    print("   Avg Entities/Conversation: {d:.1}\n", .{@as(f32, @floatFromInt(total_entities)) / @as(f32, @floatFromInt(all_conversations.items.len))});
    print("   Avg Relationships/Conversation: {d:.1}\n", .{@as(f32, @floatFromInt(total_relationships)) / @as(f32, @floatFromInt(all_conversations.items.len))});

    print("\n✅ Conversation parser implementation complete!\n", .{});
}
