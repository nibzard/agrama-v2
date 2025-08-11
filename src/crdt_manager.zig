const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Database = @import("database.zig").Database;
const WebSocketServer = @import("websocket.zig").WebSocketServer;
const crdt = @import("crdt.zig");

const CRDTDocument = crdt.CRDTDocument;
const CRDTOperation = crdt.CRDTOperation;
const VectorClock = crdt.VectorClock;
const Position = crdt.Position;
const OperationType = crdt.OperationType;
const ConflictEvent = crdt.ConflictEvent;
const AgentCursor = crdt.AgentCursor;

/// CRDT session information for each agent
pub const AgentCRDTSession = struct {
    agent_id: []const u8,
    agent_name: []const u8,
    vector_clock: VectorClock,
    active_documents: ArrayList([]const u8),
    cursor_positions: HashMap([]const u8, Position, HashContext, std.hash_map.default_max_load_percentage),
    pending_operations: ArrayList(CRDTOperation),
    connected_at: i64,
    last_activity: i64,

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

    pub fn init(allocator: Allocator, agent_id: []const u8, agent_name: []const u8) !AgentCRDTSession {
        const owned_id = try allocator.dupe(u8, agent_id);
        const owned_name = try allocator.dupe(u8, agent_name);
        const vector_clock = try VectorClock.init(allocator, agent_id);
        const timestamp = std.time.timestamp();

        return AgentCRDTSession{
            .agent_id = owned_id,
            .agent_name = owned_name,
            .vector_clock = vector_clock,
            .active_documents = ArrayList([]const u8).init(allocator),
            .cursor_positions = HashMap([]const u8, Position, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .pending_operations = ArrayList(CRDTOperation).init(allocator),
            .connected_at = timestamp,
            .last_activity = timestamp,
        };
    }

    pub fn deinit(self: *AgentCRDTSession, allocator: Allocator) void {
        allocator.free(self.agent_id);
        allocator.free(self.agent_name);
        self.vector_clock.deinit();

        for (self.active_documents.items) |doc_path| {
            allocator.free(doc_path);
        }
        self.active_documents.deinit();

        var cursor_iterator = self.cursor_positions.iterator();
        while (cursor_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.cursor_positions.deinit();

        for (self.pending_operations.items) |*operation| {
            operation.deinit(allocator);
        }
        self.pending_operations.deinit();
    }

    /// Update cursor position for a document
    pub fn updateCursor(self: *AgentCRDTSession, allocator: Allocator, document_path: []const u8, position: Position) !void {
        const owned_path = try allocator.dupe(u8, document_path);

        // Remove existing cursor position if it exists
        if (self.cursor_positions.fetchRemove(document_path)) |kv| {
            allocator.free(kv.key);
        }

        try self.cursor_positions.put(owned_path, position);
        self.last_activity = std.time.timestamp();
    }

    /// Add document to active list
    pub fn activateDocument(self: *AgentCRDTSession, allocator: Allocator, document_path: []const u8) !void {
        // Check if already active
        for (self.active_documents.items) |active_path| {
            if (std.mem.eql(u8, active_path, document_path)) {
                return; // Already active
            }
        }

        const owned_path = try allocator.dupe(u8, document_path);
        try self.active_documents.append(owned_path);
        self.last_activity = std.time.timestamp();
    }

    /// Queue operation for processing
    pub fn queueOperation(self: *AgentCRDTSession, operation: CRDTOperation) !void {
        try self.pending_operations.append(operation);
        self.last_activity = std.time.timestamp();
    }

    /// Get next logical time for this agent
    pub fn nextLogicalTime(self: *AgentCRDTSession) !u64 {
        return self.vector_clock.tick();
    }
};

/// Core CRDT manager for multi-agent collaboration
pub const CRDTManager = struct {
    allocator: Allocator,
    database: *Database,
    websocket_server: *WebSocketServer,
    documents: HashMap([]const u8, CRDTDocument, HashContext, std.hash_map.default_max_load_percentage),
    agent_sessions: HashMap([]const u8, AgentCRDTSession, HashContext, std.hash_map.default_max_load_percentage),
    global_vector_clock: VectorClock,
    conflict_events: ArrayList(ConflictEvent),
    mutex: Mutex,
    cleanup_interval_seconds: i64,
    last_cleanup: i64,

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

    /// Initialize CRDT Manager
    pub fn init(allocator: Allocator, database: *Database, websocket_server: *WebSocketServer) !CRDTManager {
        const global_clock = try VectorClock.init(allocator, "crdt-manager");

        return CRDTManager{
            .allocator = allocator,
            .database = database,
            .websocket_server = websocket_server,
            .documents = HashMap([]const u8, CRDTDocument, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .agent_sessions = HashMap([]const u8, AgentCRDTSession, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .global_vector_clock = global_clock,
            .conflict_events = ArrayList(ConflictEvent).init(allocator),
            .mutex = Mutex{},
            .cleanup_interval_seconds = 300, // 5 minutes
            .last_cleanup = std.time.timestamp(),
        };
    }

    /// Clean up CRDT Manager resources
    pub fn deinit(self: *CRDTManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up documents
        var doc_iterator = self.documents.iterator();
        while (doc_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.documents.deinit();

        // Clean up agent sessions
        var session_iterator = self.agent_sessions.iterator();
        while (session_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.agent_sessions.deinit();

        // Clean up conflict events
        for (self.conflict_events.items) |*conflict| {
            conflict.deinit(self.allocator);
        }
        self.conflict_events.deinit();

        self.global_vector_clock.deinit();
    }

    /// Register agent for CRDT collaboration
    pub fn registerAgent(self: *CRDTManager, agent_id: []const u8, agent_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const session = try AgentCRDTSession.init(self.allocator, agent_id, agent_name);
        try self.agent_sessions.put(session.agent_id, session);

        // Broadcast agent registration
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"crdt_agent_registered\",\"agent_id\":\"{s}\",\"agent_name\":\"{s}\",\"timestamp\":{d}}}", .{ agent_id, agent_name, std.time.timestamp() });
        defer self.allocator.free(event);
        self.websocket_server.broadcast(event);

        std.log.info("CRDT agent registered: {s} ({s})", .{ agent_name, agent_id });
    }

    /// Unregister agent from CRDT collaboration
    pub fn unregisterAgent(self: *CRDTManager, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.agent_sessions.fetchRemove(agent_id)) |kv| {
            var session = kv.value;
            session.deinit(self.allocator);

            // Broadcast agent unregistration
            const event = std.fmt.allocPrint(self.allocator, "{{\"type\":\"crdt_agent_unregistered\",\"agent_id\":\"{s}\",\"timestamp\":{d}}}", .{ agent_id, std.time.timestamp() }) catch return;
            defer self.allocator.free(event);
            self.websocket_server.broadcast(event);

            std.log.info("CRDT agent unregistered: {s}", .{agent_id});
        }
    }

    /// Get or create CRDT document for file path
    pub fn getOrCreateDocument(self: *CRDTManager, path: []const u8) !*CRDTDocument {
        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = try self.documents.getOrPut(path);
        if (!gop.found_existing) {
            const owned_path = try self.allocator.dupe(u8, path);

            // Load existing content from database if available
            const existing_content = self.database.getFile(path) catch "";

            gop.key_ptr.* = owned_path;
            gop.value_ptr.* = try CRDTDocument.init(self.allocator, path, existing_content);
        }

        return gop.value_ptr;
    }

    /// Apply CRDT operation with conflict resolution
    pub fn applyOperation(self: *CRDTManager, operation: CRDTOperation) !void {
        const doc = try self.getOrCreateDocument(operation.document_path);

        // Apply operation to CRDT document (handles conflict detection)
        try doc.applyOperation(operation);

        // Update database with new content
        const current_content = doc.getCurrentContent();
        try self.database.saveFile(operation.document_path, current_content);

        // Broadcast operation to other agents
        try self.broadcastOperation(operation);

        // Check for new conflicts
        const unresolved_conflicts = try doc.getUnresolvedConflicts(self.allocator);
        defer self.allocator.free(unresolved_conflicts);

        if (unresolved_conflicts.len > 0) {
            try self.broadcastConflicts(unresolved_conflicts);
        }
    }

    /// Create CRDT operation for collaborative write
    pub fn createWriteOperation(self: *CRDTManager, agent_id: []const u8, document_path: []const u8, operation_type: OperationType, position: Position, content: []const u8) !CRDTOperation {
        self.mutex.lock();
        defer self.mutex.unlock();

        const agent_session = self.agent_sessions.getPtr(agent_id) orelse return error.AgentNotFound;
        _ = try agent_session.nextLogicalTime(); // Update logical time

        return CRDTOperation.init(self.allocator, crdt.generateOperationId(), agent_id, document_path, operation_type, position, content, agent_session.vector_clock);
    }

    /// Update agent cursor position
    pub fn updateAgentCursor(self: *CRDTManager, agent_id: []const u8, document_path: []const u8, position: Position) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update agent session
        if (self.agent_sessions.getPtr(agent_id)) |session| {
            try session.updateCursor(self.allocator, document_path, position);
            try session.activateDocument(self.allocator, document_path);
        }

        // Update document
        const doc = try self.getOrCreateDocument(document_path);
        const agent_name = if (self.agent_sessions.get(agent_id)) |session| session.agent_name else "Unknown";
        try doc.updateAgentCursor(agent_id, agent_name, position);

        // Broadcast cursor update
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_cursor_update\",\"agent_id\":\"{s}\",\"document_path\":\"{s}\",\"position\":{{\"line\":{d},\"column\":{d},\"offset\":{d}}},\"timestamp\":{d}}}", .{ agent_id, document_path, position.line, position.column, position.offset, std.time.timestamp() });
        defer self.allocator.free(event);
        self.websocket_server.broadcast(event);
    }

    /// Get collaborative context for a document
    pub fn getCollaborativeContext(self: *CRDTManager, document_path: []const u8, include_cursors: bool, include_recent_ops: bool) !CollaborativeContext {
        self.mutex.lock();
        defer self.mutex.unlock();

        const doc = try self.getOrCreateDocument(document_path);
        var context = CollaborativeContext.init(self.allocator);

        // Basic document info
        context.document_path = try self.allocator.dupe(u8, document_path);
        context.content = try self.allocator.dupe(u8, doc.getCurrentContent());

        // Agent cursors
        if (include_cursors) {
            context.agent_cursors = try doc.getAgentCursors(self.allocator);
        }

        // Recent operations
        if (include_recent_ops) {
            context.recent_operations = try doc.getRecentOperations(self.allocator, 10);
        }

        // Unresolved conflicts
        context.conflicts = try doc.getUnresolvedConflicts(self.allocator);

        return context;
    }

    /// Broadcast CRDT operation to all connected agents
    fn broadcastOperation(self: *CRDTManager, operation: CRDTOperation) !void {
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"crdt_operation\",\"operation_id\":\"{any}\",\"agent_id\":\"{s}\",\"document_path\":\"{s}\",\"operation_type\":\"{s}\",\"position\":{{\"line\":{d},\"column\":{d},\"offset\":{d}}},\"content_length\":{d},\"timestamp\":{d}}}", .{ operation.operation_id, operation.agent_id, operation.document_path, @tagName(operation.operation_type), operation.position.line, operation.position.column, operation.position.offset, operation.content.len, std.time.timestamp() });
        defer self.allocator.free(event);
        self.websocket_server.broadcast(event);
    }

    /// Broadcast conflict events
    fn broadcastConflicts(self: *CRDTManager, conflicts: []ConflictEvent) !void {
        for (conflicts) |conflict| {
            const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"conflict_detected\",\"conflict_id\":\"{any}\",\"document_path\":\"{s}\",\"operations_count\":{d},\"detected_at\":{d}}}", .{ conflict.conflict_id, conflict.document_path, conflict.conflicting_operations.items.len, conflict.detected_at });
            defer self.allocator.free(event);
            self.websocket_server.broadcast(event);
        }
    }

    /// Get statistics about CRDT collaboration
    pub fn getStats(self: *CRDTManager) CRDTStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total_operations: u64 = 0;
        var total_conflicts: u64 = 0;
        var active_documents: u32 = 0;

        var doc_iterator = self.documents.iterator();
        while (doc_iterator.next()) |entry| {
            const doc = entry.value_ptr;
            total_operations += doc.operations.items.len;
            total_conflicts += doc.conflicts.items.len;
            active_documents += 1;
        }

        return CRDTStats{
            .active_agents = @as(u32, @intCast(self.agent_sessions.count())),
            .active_documents = active_documents,
            .total_operations = total_operations,
            .total_conflicts = total_conflicts,
            .global_conflicts = @as(u32, @intCast(self.conflict_events.items.len)),
        };
    }

    /// Perform maintenance tasks
    pub fn performMaintenance(self: *CRDTManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();

        if (current_time - self.last_cleanup < self.cleanup_interval_seconds) {
            return;
        }

        // TODO: Implement cleanup of old operations, resolved conflicts, etc.
        self.last_cleanup = current_time;
    }
};

/// Collaborative context information for Observatory display
pub const CollaborativeContext = struct {
    document_path: []const u8,
    content: []const u8,
    agent_cursors: ?[]AgentCursor = null,
    recent_operations: ?[]CRDTOperation = null,
    conflicts: ?[]ConflictEvent = null,
    active_agents_count: u32 = 0,

    pub fn init(allocator: Allocator) CollaborativeContext {
        _ = allocator;
        return CollaborativeContext{
            .document_path = "",
            .content = "",
        };
    }

    pub fn deinit(self: *CollaborativeContext, allocator: Allocator) void {
        allocator.free(self.document_path);
        allocator.free(self.content);

        if (self.agent_cursors) |cursors| {
            allocator.free(cursors);
        }

        if (self.recent_operations) |operations| {
            allocator.free(operations);
        }

        if (self.conflicts) |conflicts| {
            allocator.free(conflicts);
        }
    }
};

/// CRDT collaboration statistics
pub const CRDTStats = struct {
    active_agents: u32,
    active_documents: u32,
    total_operations: u64,
    total_conflicts: u64,
    global_conflicts: u32,
};

// Unit Tests
test "CRDTManager initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var crdt_manager = try CRDTManager.init(allocator, &db, &ws_server);
    defer crdt_manager.deinit();

    const stats = crdt_manager.getStats();
    try testing.expect(stats.active_agents == 0);
    try testing.expect(stats.active_documents == 0);
}

test "agent registration and CRDT session management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var crdt_manager = try CRDTManager.init(allocator, &db, &ws_server);
    defer crdt_manager.deinit();

    try crdt_manager.registerAgent("agent-1", "Test Agent");

    const stats = crdt_manager.getStats();
    try testing.expect(stats.active_agents == 1);

    crdt_manager.unregisterAgent("agent-1");
    const stats_after = crdt_manager.getStats();
    try testing.expect(stats_after.active_agents == 0);
}

test "CRDT document creation and operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var crdt_manager = try CRDTManager.init(allocator, &db, &ws_server);
    defer crdt_manager.deinit();

    // Register agent
    try crdt_manager.registerAgent("agent-1", "Test Agent");

    // Create document
    const doc = try crdt_manager.getOrCreateDocument("test.txt");
    try testing.expect(std.mem.eql(u8, doc.document_path, "test.txt"));

    // Create and apply operation
    const operation = try crdt_manager.createWriteOperation("agent-1", "test.txt", .insert, Position{ .line = 1, .column = 0, .offset = 0 }, "Hello, CRDT World!");
    defer {
        var mutable_op = operation;
        mutable_op.deinit(allocator);
    }

    try crdt_manager.applyOperation(operation);

    const stats = crdt_manager.getStats();
    try testing.expect(stats.active_documents == 1);
    try testing.expect(stats.total_operations == 1);
}
