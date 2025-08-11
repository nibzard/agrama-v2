const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Database = @import("database.zig").Database;
const MCPServer = @import("mcp_server.zig").MCPServer;
const WebSocketServer = @import("websocket.zig").WebSocketServer;

/// File lock information for coordinating multi-agent access
pub const FileLock = struct {
    path: []const u8,
    agent_id: []const u8,
    lock_type: LockType,
    acquired_at: i64,
    expires_at: i64,

    pub const LockType = enum {
        read,
        write,
        exclusive,
    };

    pub fn init(allocator: Allocator, path: []const u8, agent_id: []const u8, lock_type: LockType, duration_seconds: i64) !FileLock {
        const owned_path = try allocator.dupe(u8, path);
        const owned_agent_id = try allocator.dupe(u8, agent_id);
        const now = std.time.timestamp();

        return FileLock{
            .path = owned_path,
            .agent_id = owned_agent_id,
            .lock_type = lock_type,
            .acquired_at = now,
            .expires_at = now + duration_seconds,
        };
    }

    pub fn deinit(self: *FileLock, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.agent_id);
    }

    pub fn isExpired(self: FileLock) bool {
        return std.time.timestamp() >= self.expires_at;
    }

    pub fn canCoexistWith(self: FileLock, other: FileLock, current_time: i64) bool {
        // Check if locks are expired
        if (current_time >= self.expires_at or current_time >= other.expires_at) {
            return true;
        }

        // Same agent can have multiple locks
        if (std.mem.eql(u8, self.agent_id, other.agent_id)) {
            return true;
        }

        // Multiple read locks can coexist
        if (self.lock_type == .read and other.lock_type == .read) {
            return true;
        }

        // All other combinations conflict
        return false;
    }
};

/// Agent session information
pub const AgentSession = struct {
    id: []const u8,
    name: []const u8,
    capabilities: ArrayList([]const u8),
    connected_at: i64,
    last_activity: i64,
    requests_handled: u64,
    files_accessed: HashMap([]const u8, i64, HashContext, std.hash_map.default_max_load_percentage),
    is_active: bool,

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

    pub fn init(allocator: Allocator, id: []const u8, name: []const u8) !AgentSession {
        const owned_id = try allocator.dupe(u8, id);
        const owned_name = try allocator.dupe(u8, name);
        const timestamp = std.time.timestamp();

        return AgentSession{
            .id = owned_id,
            .name = owned_name,
            .capabilities = ArrayList([]const u8).init(allocator),
            .connected_at = timestamp,
            .last_activity = timestamp,
            .requests_handled = 0,
            .files_accessed = HashMap([]const u8, i64, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .is_active = true,
        };
    }

    pub fn deinit(self: *AgentSession, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);

        for (self.capabilities.items) |capability| {
            allocator.free(capability);
        }
        self.capabilities.deinit();

        var file_iterator = self.files_accessed.iterator();
        while (file_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.files_accessed.deinit();
    }

    pub fn addCapability(self: *AgentSession, allocator: Allocator, capability: []const u8) !void {
        const owned_capability = try allocator.dupe(u8, capability);
        try self.capabilities.append(owned_capability);
    }

    pub fn recordFileAccess(self: *AgentSession, allocator: Allocator, path: []const u8) !void {
        const owned_path = try allocator.dupe(u8, path);
        const timestamp = std.time.timestamp();

        // Update or insert file access time
        const gop = try self.files_accessed.getOrPut(owned_path);
        if (gop.found_existing) {
            allocator.free(owned_path); // Free the duplicate
        } else {
            gop.key_ptr.* = owned_path;
        }
        gop.value_ptr.* = timestamp;

        self.last_activity = timestamp;
        self.requests_handled += 1;
    }

    pub fn hasCapability(self: AgentSession, capability: []const u8) bool {
        for (self.capabilities.items) |cap| {
            if (std.mem.eql(u8, cap, capability)) return true;
        }
        return false;
    }
};

/// Agent coordination and management system
pub const AgentManager = struct {
    allocator: Allocator,
    sessions: HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage),
    file_locks: ArrayList(FileLock),
    mcp_server: *MCPServer,
    websocket_server: *WebSocketServer,
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

    /// Initialize Agent Manager
    pub fn init(allocator: Allocator, mcp_server: *MCPServer, websocket_server: *WebSocketServer) AgentManager {
        return AgentManager{
            .allocator = allocator,
            .sessions = HashMap([]const u8, AgentSession, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .file_locks = ArrayList(FileLock).init(allocator),
            .mcp_server = mcp_server,
            .websocket_server = websocket_server,
            .mutex = Mutex{},
            .cleanup_interval_seconds = 300, // 5 minutes
            .last_cleanup = std.time.timestamp(),
        };
    }

    /// Clean up Agent Manager resources
    pub fn deinit(self: *AgentManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up sessions
        var session_iterator = self.sessions.iterator();
        while (session_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.sessions.deinit();

        // Clean up file locks
        for (self.file_locks.items) |*lock| {
            lock.deinit(self.allocator);
        }
        self.file_locks.deinit();
    }

    /// Register a new agent session
    pub fn registerAgent(self: *AgentManager, agent_id: []const u8, agent_name: []const u8, capabilities: []const []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var session = try AgentSession.init(self.allocator, agent_id, agent_name);

        // Add capabilities
        for (capabilities) |capability| {
            try session.addCapability(self.allocator, capability);
        }

        try self.sessions.put(session.id, session);

        // Agent registration with MCP server handled automatically during tool execution

        // Broadcast agent registration
        const capabilities_json = try self.formatCapabilities(capabilities);
        defer self.allocator.free(capabilities_json);
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_registered\",\"agent_id\":\"{s}\",\"agent_name\":\"{s}\",\"capabilities\":{s}}}", .{ session.id, session.name, capabilities_json });
        defer self.allocator.free(event);
        self.websocket_server.broadcast(event);

        std.log.info("Agent registered: {s} ({s}) with {d} capabilities", .{ session.name, session.id, capabilities.len });
    }

    /// Unregister an agent session
    pub fn unregisterAgent(self: *AgentManager, agent_id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.fetchRemove(agent_id)) |kv| {
            var session = kv.value;

            // Release all file locks held by this agent
            self.releaseAgentLocks(agent_id);

            // Clean up session
            session.deinit(self.allocator);

            // Agent cleanup handled automatically by MCP server session management

            // Broadcast agent unregistration
            const event = std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_unregistered\",\"agent_id\":\"{s}\"}}", .{agent_id}) catch return;
            defer self.allocator.free(event);
            self.websocket_server.broadcast(event);

            std.log.info("Agent unregistered: {s}", .{agent_id});
        }
    }

    /// Acquire a file lock for an agent
    pub fn acquireLock(self: *AgentManager, agent_id: []const u8, path: []const u8, lock_type: FileLock.LockType, duration_seconds: i64) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();

        // Check if agent exists
        if (!self.sessions.contains(agent_id)) {
            return error.AgentNotFound;
        }

        // Create the new lock
        const new_lock = try FileLock.init(self.allocator, path, agent_id, lock_type, duration_seconds);

        // Check for conflicts with existing locks
        for (self.file_locks.items) |existing_lock| {
            if (std.mem.eql(u8, existing_lock.path, path)) {
                if (!new_lock.canCoexistWith(existing_lock, current_time)) {
                    // Conflict detected
                    var mutable_new_lock = new_lock;
                    mutable_new_lock.deinit(self.allocator);
                    return false;
                }
            }
        }

        // No conflicts, add the lock
        try self.file_locks.append(new_lock);

        // Record file access in agent session
        if (self.sessions.getPtr(agent_id)) |session| {
            try session.recordFileAccess(self.allocator, path);
        }

        // Broadcast lock acquisition
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"file_lock_acquired\",\"agent_id\":\"{s}\",\"path\":\"{s}\",\"lock_type\":\"{s}\"}}", .{ agent_id, path, @tagName(lock_type) });
        defer self.allocator.free(event);
        self.websocket_server.broadcast(event);

        return true;
    }

    /// Release a specific file lock
    pub fn releaseLock(self: *AgentManager, agent_id: []const u8, path: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.file_locks.items.len) {
            const lock = &self.file_locks.items[i];
            if (std.mem.eql(u8, lock.agent_id, agent_id) and std.mem.eql(u8, lock.path, path)) {
                // Release this lock
                lock.deinit(self.allocator);
                _ = self.file_locks.swapRemove(i);

                // Broadcast lock release
                const event = std.fmt.allocPrint(self.allocator, "{{\"type\":\"file_lock_released\",\"agent_id\":\"{s}\",\"path\":\"{s}\"}}", .{ agent_id, path }) catch return;
                defer self.allocator.free(event);
                self.websocket_server.broadcast(event);

                return;
            }
            i += 1;
        }
    }

    /// Release all locks held by an agent
    fn releaseAgentLocks(self: *AgentManager, agent_id: []const u8) void {
        // Note: mutex should already be locked when this is called
        var i: usize = 0;
        while (i < self.file_locks.items.len) {
            const lock = &self.file_locks.items[i];
            if (std.mem.eql(u8, lock.agent_id, agent_id)) {
                lock.deinit(self.allocator);
                _ = self.file_locks.swapRemove(i);
                continue; // Don't increment i since we removed an item
            }
            i += 1;
        }
    }

    /// Check if an agent can access a file
    pub fn canAccessFile(self: *AgentManager, agent_id: []const u8, path: []const u8, access_type: FileLock.LockType) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();

        // Clean up expired locks first
        self.cleanupExpiredLocks();

        // Check for conflicts
        for (self.file_locks.items) |lock| {
            if (std.mem.eql(u8, lock.path, path)) {
                // Same agent always has access to files they've locked
                if (std.mem.eql(u8, lock.agent_id, agent_id)) {
                    continue;
                }

                // Check if the requested access conflicts with existing lock
                const test_lock = FileLock{
                    .path = path,
                    .agent_id = agent_id,
                    .lock_type = access_type,
                    .acquired_at = current_time,
                    .expires_at = current_time + 1, // Dummy expiration
                };

                if (!test_lock.canCoexistWith(lock, current_time)) {
                    return false;
                }
            }
        }

        return true;
    }

    /// Get agent session information
    pub fn getAgentSession(self: *AgentManager, agent_id: []const u8) ?AgentSession {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sessions.get(agent_id);
    }

    /// Get all active agents
    pub fn getActiveAgents(self: *AgentManager, allocator: Allocator) ![]AgentSession {
        self.mutex.lock();
        defer self.mutex.unlock();

        var active_agents = ArrayList(AgentSession).init(allocator);
        var session_iterator = self.sessions.iterator();

        while (session_iterator.next()) |entry| {
            if (entry.value_ptr.is_active) {
                try active_agents.append(entry.value_ptr.*);
            }
        }

        return active_agents.toOwnedSlice();
    }

    /// Cleanup expired locks and inactive agents
    pub fn performMaintenance(self: *AgentManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();

        // Only run cleanup if enough time has passed
        if (current_time - self.last_cleanup < self.cleanup_interval_seconds) {
            return;
        }

        self.cleanupExpiredLocks();
        self.cleanupInactiveSessions(current_time);

        self.last_cleanup = current_time;
    }

    /// Clean up expired file locks
    fn cleanupExpiredLocks(self: *AgentManager) void {
        // Note: mutex should already be locked when this is called
        const current_time = std.time.timestamp();

        var i: usize = 0;
        while (i < self.file_locks.items.len) {
            const lock = &self.file_locks.items[i];
            if (current_time >= lock.expires_at) { // Check expiration
                std.log.debug("Cleaning up expired lock: {s} by {s}", .{ lock.path, lock.agent_id });
                lock.deinit(self.allocator);
                _ = self.file_locks.swapRemove(i);
                continue; // Don't increment i since we removed an item
            }
            i += 1;
        }
    }

    /// Clean up inactive agent sessions (no activity for 1 hour)
    fn cleanupInactiveSessions(self: *AgentManager, current_time: i64) void {
        // Note: mutex should already be locked when this is called
        const inactive_threshold = 3600; // 1 hour in seconds

        // Store owned copies of agent IDs to avoid use-after-free
        var agents_to_remove = ArrayList([]u8).init(self.allocator);
        defer {
            for (agents_to_remove.items) |agent_id| {
                self.allocator.free(agent_id);
            }
            agents_to_remove.deinit();
        }

        var session_iterator = self.sessions.iterator();
        while (session_iterator.next()) |entry| {
            const session = entry.value_ptr;
            if (current_time - session.last_activity > inactive_threshold) {
                // Create owned copy to avoid use-after-free when session is removed
                const owned_agent_id = self.allocator.dupe(u8, session.id) catch continue;
                agents_to_remove.append(owned_agent_id) catch {
                    self.allocator.free(owned_agent_id);
                    continue;
                };
            }
        }

        // Remove inactive agents - now safe from use-after-free
        for (agents_to_remove.items) |agent_id| {
            std.log.info("Cleaning up inactive agent: {s}", .{agent_id});
            if (self.sessions.fetchRemove(agent_id)) |kv| {
                var session = kv.value;
                self.releaseAgentLocks(agent_id);
                session.deinit(self.allocator);
                // Agent cleanup handled automatically by MCP server session management
            }
        }
    }

    /// Format capabilities for JSON output
    fn formatCapabilities(self: *AgentManager, capabilities: []const []const u8) ![]const u8 {
        if (capabilities.len == 0) {
            return try self.allocator.dupe(u8, "[]");
        }

        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        try result.append('[');
        for (capabilities, 0..) |capability, i| {
            if (i > 0) try result.appendSlice(",");
            try result.append('"');
            try result.appendSlice(capability);
            try result.append('"');
        }
        try result.append(']');

        return result.toOwnedSlice();
    }

    /// Get comprehensive statistics
    pub fn getStats(self: *AgentManager) struct {
        active_agents: u32,
        total_file_locks: u32,
        total_requests_handled: u64,
        avg_files_per_agent: f64,
    } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total_requests: u64 = 0;
        var total_files: u64 = 0;
        var active_count: u32 = 0;

        var session_iterator = self.sessions.iterator();
        while (session_iterator.next()) |entry| {
            const session = entry.value_ptr;
            if (session.is_active) {
                active_count += 1;
                total_requests += session.requests_handled;
                total_files += session.files_accessed.count();
            }
        }

        const avg_files_per_agent = if (active_count > 0)
            @as(f64, @floatFromInt(total_files)) / @as(f64, @floatFromInt(active_count))
        else
            0.0;

        return .{
            .active_agents = active_count,
            .total_file_locks = @as(u32, @intCast(self.file_locks.items.len)),
            .total_requests_handled = total_requests,
            .avg_files_per_agent = avg_files_per_agent,
        };
    }
};

// Unit Tests
test "AgentManager initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var mcp_server = try MCPServer.init(allocator, &db);
    defer mcp_server.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var agent_manager = AgentManager.init(allocator, &mcp_server, &ws_server);
    defer agent_manager.deinit();

    const stats = agent_manager.getStats();
    try testing.expect(stats.active_agents == 0);
    try testing.expect(stats.total_file_locks == 0);
}

test "agent registration and session management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var mcp_server = try MCPServer.init(allocator, &db);
    defer mcp_server.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var agent_manager = AgentManager.init(allocator, &mcp_server, &ws_server);
    defer agent_manager.deinit();

    const capabilities = [_][]const u8{ "read_code", "write_code" };
    try agent_manager.registerAgent("agent-1", "Test Agent", &capabilities);

    var stats = agent_manager.getStats();
    try testing.expect(stats.active_agents == 1);

    const session = agent_manager.getAgentSession("agent-1");
    try testing.expect(session != null);
    try testing.expectEqualSlices(u8, "Test Agent", session.?.name);

    agent_manager.unregisterAgent("agent-1");
    stats = agent_manager.getStats();
    try testing.expect(stats.active_agents == 0);
}

test "file lock management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var mcp_server = try MCPServer.init(allocator, &db);
    defer mcp_server.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var agent_manager = AgentManager.init(allocator, &mcp_server, &ws_server);
    defer agent_manager.deinit();

    // Register agents
    const capabilities = [_][]const u8{ "read_code", "write_code" };
    try agent_manager.registerAgent("agent-1", "Agent 1", &capabilities);
    try agent_manager.registerAgent("agent-2", "Agent 2", &capabilities);

    // Test file lock acquisition
    const lock_acquired = try agent_manager.acquireLock("agent-1", "test.txt", .write, 30);
    try testing.expect(lock_acquired == true);

    // Test conflicting lock
    const conflicting_lock = try agent_manager.acquireLock("agent-2", "test.txt", .write, 30);
    try testing.expect(conflicting_lock == false);

    // Test compatible lock (same agent)
    const same_agent_lock = try agent_manager.acquireLock("agent-1", "test.txt", .read, 30);
    try testing.expect(same_agent_lock == true);

    const stats = agent_manager.getStats();
    try testing.expect(stats.total_file_locks >= 1);

    // Release lock
    agent_manager.releaseLock("agent-1", "test.txt");
}

test "file access checking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    var mcp_server = try MCPServer.init(allocator, &db);
    defer mcp_server.deinit();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    var agent_manager = AgentManager.init(allocator, &mcp_server, &ws_server);
    defer agent_manager.deinit();

    const capabilities = [_][]const u8{ "read_code", "write_code" };
    try agent_manager.registerAgent("agent-1", "Agent 1", &capabilities);

    // Should be able to access file with no locks
    try testing.expect(agent_manager.canAccessFile("agent-1", "test.txt", .read) == true);
    try testing.expect(agent_manager.canAccessFile("agent-1", "test.txt", .write) == true);
}
