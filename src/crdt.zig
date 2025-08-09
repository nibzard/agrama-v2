const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Database = @import("database.zig").Database;
const WebSocketServer = @import("websocket.zig").WebSocketServer;

/// Vector clock for causally ordering CRDT operations
pub const VectorClock = struct {
    agent_id: []const u8,
    clocks: HashMap([]const u8, u64, HashContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

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

    pub fn init(allocator: Allocator, agent_id: []const u8) !VectorClock {
        var clocks = HashMap([]const u8, u64, HashContext, std.hash_map.default_max_load_percentage).init(allocator);
        const owned_agent_id = try allocator.dupe(u8, agent_id);
        try clocks.put(owned_agent_id, 0);

        return VectorClock{
            .agent_id = owned_agent_id,
            .clocks = clocks,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VectorClock) void {
        var iterator = self.clocks.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.clocks.deinit();
        // Note: agent_id is already freed in the iterator above since it's a key in clocks
    }

    /// Increment local logical time
    pub fn tick(self: *VectorClock) !u64 {
        const current = self.clocks.get(self.agent_id) orelse 0;
        const new_time = current + 1;
        try self.clocks.put(self.agent_id, new_time);
        return new_time;
    }

    /// Update vector clock based on received operation
    pub fn update(self: *VectorClock, remote_agent: []const u8, remote_time: u64) !void {
        // Update our time for the remote agent
        const gop = try self.clocks.getOrPut(remote_agent);
        if (!gop.found_existing) {
            gop.key_ptr.* = try self.allocator.dupe(u8, remote_agent);
            gop.value_ptr.* = 0;
        }
        gop.value_ptr.* = @max(gop.value_ptr.*, remote_time);

        // Increment our own logical time
        _ = try self.tick();
    }

    /// Check if this vector clock happens before another
    pub fn happensBefore(self: VectorClock, other: VectorClock) bool {
        var self_less_than_other = false;
        var self_iterator = self.clocks.iterator();

        while (self_iterator.next()) |entry| {
            const agent = entry.key_ptr.*;
            const self_time = entry.value_ptr.*;
            const other_time = other.clocks.get(agent) orelse 0;

            if (self_time > other_time) {
                return false; // self > other for some agent
            } else if (self_time < other_time) {
                self_less_than_other = true;
            }
        }

        // Check agents that exist in other but not in self
        var other_iterator = other.clocks.iterator();
        while (other_iterator.next()) |entry| {
            const agent = entry.key_ptr.*;
            if (!self.clocks.contains(agent)) {
                const other_time = entry.value_ptr.*;
                if (other_time > 0) {
                    self_less_than_other = true;
                }
            }
        }

        return self_less_than_other;
    }

    /// Check if two vector clocks are concurrent (causally unrelated)
    pub fn isConcurrentWith(self: VectorClock, other: VectorClock) bool {
        return !self.happensBefore(other) and !other.happensBefore(self);
    }
};

/// Position in a document for CRDT operations
pub const Position = struct {
    line: u32,
    column: u32,
    offset: u64, // Absolute character offset

    pub fn compare(a: Position, b: Position) std.math.Order {
        if (a.offset < b.offset) return .lt;
        if (a.offset > b.offset) return .gt;
        return .eq;
    }
};

/// Types of CRDT operations on documents
pub const OperationType = enum {
    insert,
    delete,
    modify,
    cursor_move,
};

/// CRDT operation representing a change to a document
pub const CRDTOperation = struct {
    operation_id: u128,
    agent_id: []const u8,
    document_path: []const u8,
    operation_type: OperationType,
    position: Position,
    content: []const u8,
    timestamp: VectorClock,
    dependencies: ArrayList(u128),
    created_at: i64, // Wall clock time for ordering tie-breaking

    pub fn init(allocator: Allocator, operation_id: u128, agent_id: []const u8, document_path: []const u8, operation_type: OperationType, position: Position, content: []const u8, timestamp: VectorClock) !CRDTOperation {
        return CRDTOperation{
            .operation_id = operation_id,
            .agent_id = try allocator.dupe(u8, agent_id),
            .document_path = try allocator.dupe(u8, document_path),
            .operation_type = operation_type,
            .position = position,
            .content = try allocator.dupe(u8, content),
            .timestamp = timestamp,
            .dependencies = ArrayList(u128).init(allocator),
            .created_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *CRDTOperation, allocator: Allocator) void {
        allocator.free(self.agent_id);
        allocator.free(self.document_path);
        allocator.free(self.content);
        self.timestamp.deinit();
        self.dependencies.deinit();
    }

    /// Check if this operation causally depends on another
    pub fn dependsOn(self: CRDTOperation, other: CRDTOperation) bool {
        return self.timestamp.happensBefore(other.timestamp);
    }

    /// Check if two operations conflict (concurrent and affect same location)
    pub fn conflictsWith(self: CRDTOperation, other: CRDTOperation) bool {
        // Must be on same document
        if (!std.mem.eql(u8, self.document_path, other.document_path)) {
            return false;
        }

        // Must be concurrent (causally unrelated)
        if (!self.timestamp.isConcurrentWith(other.timestamp)) {
            return false;
        }

        // Must affect overlapping regions
        return self.affectsPosition(other.position) or other.affectsPosition(self.position);
    }

    /// Check if this operation affects a given position
    fn affectsPosition(self: CRDTOperation, pos: Position) bool {
        return switch (self.operation_type) {
            .insert => self.position.offset <= pos.offset,
            .delete => self.position.offset <= pos.offset and
                pos.offset < self.position.offset + self.content.len,
            .modify => self.position.offset <= pos.offset and
                pos.offset < self.position.offset + self.content.len,
            .cursor_move => false, // Cursor moves don't affect text
        };
    }
};

/// Represents a conflict between CRDT operations
pub const ConflictEvent = struct {
    conflict_id: u128,
    document_path: []const u8,
    conflicting_operations: ArrayList(CRDTOperation),
    detected_at: i64,
    resolution_strategy: ?ConflictResolutionStrategy = null,
    resolved_at: ?i64 = null,

    pub const ConflictResolutionStrategy = enum {
        last_writer_wins,
        semantic_merge,
        agent_priority,
        human_intervention,
        syntax_preserving,
    };

    pub fn init(allocator: Allocator, conflict_id: u128, document_path: []const u8) !ConflictEvent {
        return ConflictEvent{
            .conflict_id = conflict_id,
            .document_path = try allocator.dupe(u8, document_path),
            .conflicting_operations = ArrayList(CRDTOperation).init(allocator),
            .detected_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *ConflictEvent, allocator: Allocator) void {
        allocator.free(self.document_path);
        for (self.conflicting_operations.items) |*operation| {
            operation.deinit(allocator);
        }
        self.conflicting_operations.deinit();
    }
};

/// Agent cursor position for real-time collaboration visualization
pub const AgentCursor = struct {
    agent_id: []const u8,
    agent_name: []const u8,
    document_path: []const u8,
    position: Position,
    updated_at: i64,

    pub fn init(allocator: Allocator, agent_id: []const u8, agent_name: []const u8, document_path: []const u8, position: Position) !AgentCursor {
        return AgentCursor{
            .agent_id = try allocator.dupe(u8, agent_id),
            .agent_name = try allocator.dupe(u8, agent_name),
            .document_path = try allocator.dupe(u8, document_path),
            .position = position,
            .updated_at = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *AgentCursor, allocator: Allocator) void {
        allocator.free(self.agent_id);
        allocator.free(self.agent_name);
        allocator.free(self.document_path);
    }
};

/// CRDT document representing a collaboratively edited file
pub const CRDTDocument = struct {
    allocator: Allocator,
    document_path: []const u8,
    content: ArrayList(u8),
    operations: ArrayList(CRDTOperation),
    vector_clock: VectorClock,
    agent_cursors: HashMap([]const u8, AgentCursor, HashContext, std.hash_map.default_max_load_percentage),
    conflicts: ArrayList(ConflictEvent),
    mutex: Mutex,

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

    pub fn init(allocator: Allocator, document_path: []const u8, initial_content: []const u8) !CRDTDocument {
        var content = ArrayList(u8).init(allocator);
        try content.appendSlice(initial_content);

        const vector_clock = try VectorClock.init(allocator, "system");

        return CRDTDocument{
            .allocator = allocator,
            .document_path = try allocator.dupe(u8, document_path),
            .content = content,
            .operations = ArrayList(CRDTOperation).init(allocator),
            .vector_clock = vector_clock,
            .agent_cursors = HashMap([]const u8, AgentCursor, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .conflicts = ArrayList(ConflictEvent).init(allocator),
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *CRDTDocument) void {
        self.allocator.free(self.document_path);
        self.content.deinit();

        for (self.operations.items) |*operation| {
            operation.deinit(self.allocator);
        }
        self.operations.deinit();

        self.vector_clock.deinit();

        var cursor_iterator = self.agent_cursors.iterator();
        while (cursor_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.agent_cursors.deinit();

        for (self.conflicts.items) |*conflict| {
            conflict.deinit(self.allocator);
        }
        self.conflicts.deinit();
    }

    /// Get current document content as string
    pub fn getCurrentContent(self: *CRDTDocument) []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.content.items;
    }

    /// Apply a CRDT operation to the document
    pub fn applyOperation(self: *CRDTDocument, operation: CRDTOperation) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check for conflicts with existing operations
        var conflicts = ArrayList(CRDTOperation).init(self.allocator);
        defer conflicts.deinit();

        for (self.operations.items) |existing_op| {
            if (operation.conflictsWith(existing_op)) {
                try conflicts.append(existing_op);
            }
        }

        if (conflicts.items.len > 0) {
            // Create conflict event
            var conflict_event = try ConflictEvent.init(self.allocator, operation.operation_id, self.document_path);

            // Add the conflicting operation
            try conflict_event.conflicting_operations.append(operation);

            // Add existing conflicting operations
            for (conflicts.items) |conflict_op| {
                try conflict_event.conflicting_operations.append(conflict_op);
            }

            try self.conflicts.append(conflict_event);

            // For now, use simple last-writer-wins resolution
            try self.resolveConflictLastWriterWins(&conflict_event);
        } else {
            // No conflicts, apply operation directly
            try self.applyOperationDirect(operation);
        }

        // Store operation in history
        try self.operations.append(operation);

        // Update vector clock
        try self.vector_clock.update(operation.agent_id, operation.timestamp.clocks.get(operation.agent_id) orelse 0);
    }

    /// Apply operation directly to document content (assumes no conflicts)
    fn applyOperationDirect(self: *CRDTDocument, operation: CRDTOperation) !void {
        switch (operation.operation_type) {
            .insert => {
                try self.content.insertSlice(operation.position.offset, operation.content);
            },
            .delete => {
                const end_offset = @min(operation.position.offset + operation.content.len, self.content.items.len);

                if (operation.position.offset < self.content.items.len) {
                    self.content.replaceRange(operation.position.offset, end_offset - operation.position.offset, "") catch |err| {
                        std.log.err("Failed to delete content: {}", .{err});
                        return;
                    };
                }
            },
            .modify => {
                const end_offset = @min(operation.position.offset + operation.content.len, self.content.items.len);

                if (operation.position.offset < self.content.items.len) {
                    self.content.replaceRange(operation.position.offset, end_offset - operation.position.offset, operation.content) catch |err| {
                        std.log.err("Failed to modify content: {}", .{err});
                        return;
                    };
                }
            },
            .cursor_move => {
                // Cursor moves don't change document content
                // This is handled in updateAgentCursor
            },
        }
    }

    /// Resolve conflict using last-writer-wins strategy
    fn resolveConflictLastWriterWins(self: *CRDTDocument, conflict: *ConflictEvent) !void {
        // Find operation with latest wall-clock timestamp
        var latest_operation: ?CRDTOperation = null;
        var latest_time: i64 = 0;

        for (conflict.conflicting_operations.items) |operation| {
            if (operation.created_at > latest_time) {
                latest_time = operation.created_at;
                latest_operation = operation;
            }
        }

        if (latest_operation) |op| {
            try self.applyOperationDirect(op);
            conflict.resolution_strategy = .last_writer_wins;
            conflict.resolved_at = std.time.timestamp();
        }
    }

    /// Update agent cursor position
    pub fn updateAgentCursor(self: *CRDTDocument, agent_id: []const u8, agent_name: []const u8, position: Position) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const cursor = try AgentCursor.init(self.allocator, agent_id, agent_name, self.document_path, position);

        // Remove existing cursor for this agent if it exists
        if (self.agent_cursors.fetchRemove(agent_id)) |kv| {
            var mutable_cursor = kv.value;
            mutable_cursor.deinit(self.allocator);
        }

        try self.agent_cursors.put(cursor.agent_id, cursor);
    }

    /// Get all agent cursors for this document
    pub fn getAgentCursors(self: *CRDTDocument, allocator: Allocator) ![]AgentCursor {
        self.mutex.lock();
        defer self.mutex.unlock();

        var cursors = ArrayList(AgentCursor).init(allocator);
        var iterator = self.agent_cursors.iterator();

        while (iterator.next()) |entry| {
            try cursors.append(entry.value_ptr.*);
        }

        return cursors.toOwnedSlice();
    }

    /// Get recent operations (for Observatory display)
    pub fn getRecentOperations(self: *CRDTDocument, allocator: Allocator, limit: usize) ![]CRDTOperation {
        self.mutex.lock();
        defer self.mutex.unlock();

        const actual_limit = @min(limit, self.operations.items.len);
        var recent_ops = try allocator.alloc(CRDTOperation, actual_limit);

        // Get the most recent operations
        for (0..actual_limit) |i| {
            const source_index = self.operations.items.len - 1 - i;
            recent_ops[i] = self.operations.items[source_index];
        }

        return recent_ops;
    }

    /// Get all unresolved conflicts
    pub fn getUnresolvedConflicts(self: *CRDTDocument, allocator: Allocator) ![]ConflictEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        var unresolved = ArrayList(ConflictEvent).init(allocator);

        for (self.conflicts.items) |conflict| {
            if (conflict.resolved_at == null) {
                try unresolved.append(conflict);
            }
        }

        return unresolved.toOwnedSlice();
    }
};

/// Generate unique operation ID
pub fn generateOperationId() u128 {
    // Simple implementation using timestamp + random
    const timestamp = @as(u128, @intCast(std.time.timestamp()));
    const random = std.crypto.random.int(u64);
    return (timestamp << 64) | random;
}

// Unit Tests
test "VectorClock initialization and operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var clock = try VectorClock.init(allocator, "agent-1");
    defer clock.deinit();

    // Test tick operation
    const time1 = try clock.tick();
    const time2 = try clock.tick();

    try testing.expect(time1 == 1);
    try testing.expect(time2 == 2);

    // Test update from remote agent
    try clock.update("agent-2", 5);
    const time3 = try clock.tick();
    try testing.expect(time3 == 3); // Our clock continues from 2 -> 3
}

test "CRDT operation creation and conflict detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var clock1 = try VectorClock.init(allocator, "agent-1");
    defer clock1.deinit();

    var clock2 = try VectorClock.init(allocator, "agent-2");
    defer clock2.deinit();

    const op1 = try CRDTOperation.init(allocator, generateOperationId(), "agent-1", "test.txt", .insert, Position{ .line = 1, .column = 5, .offset = 5 }, "hello", clock1);
    defer {
        var mutable_op1 = op1;
        mutable_op1.deinit(allocator);
    }

    const op2 = try CRDTOperation.init(allocator, generateOperationId(), "agent-2", "test.txt", .insert, Position{ .line = 1, .column = 3, .offset = 3 }, "world", clock2);
    defer {
        var mutable_op2 = op2;
        mutable_op2.deinit(allocator);
    }

    // These operations should be considered concurrent and conflicting
    try testing.expect(op1.timestamp.isConcurrentWith(op2.timestamp));
    try testing.expect(op1.conflictsWith(op2));
}

test "CRDTDocument basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc = try CRDTDocument.init(allocator, "test.txt", "Hello World");
    defer doc.deinit();

    const initial_content = doc.getCurrentContent();
    try testing.expectEqualSlices(u8, "Hello World", initial_content);

    // Test cursor update
    try doc.updateAgentCursor("agent-1", "Test Agent", Position{ .line = 1, .column = 6, .offset = 6 });

    const cursors = try doc.getAgentCursors(allocator);
    defer allocator.free(cursors);

    try testing.expect(cursors.len == 1);
    try testing.expectEqualSlices(u8, "agent-1", cursors[0].agent_id);
}
