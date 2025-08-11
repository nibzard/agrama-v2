//! Authenticated WebSocket Server with Role-Based Access Control
//! Extends the base WebSocket server with authentication and authorization

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const net = std.net;

const WebSocketServer = @import("websocket.zig").WebSocketServer;
const WebSocketConnection = @import("websocket.zig").WebSocketConnection;
const auth = @import("auth.zig");

/// Authenticated WebSocket connection with user context
pub const AuthenticatedConnection = struct {
    base_connection: WebSocketConnection,
    auth_context: auth.AuthContext,
    permissions: ConnectionPermissions,
    last_activity: i64,
    message_count: u64,

    pub const ConnectionPermissions = struct {
        can_receive_all_events: bool,
        can_receive_agent_events: bool,
        can_receive_file_events: bool,
        can_receive_metrics: bool,
        can_send_commands: bool,
        max_message_rate_per_minute: u32,
    };

    pub fn init(allocator: Allocator, id: []const u8, socket: net.Stream, auth_context: auth.AuthContext) !AuthenticatedConnection {
        const base = try WebSocketConnection.init(allocator, id, socket);
        const permissions = permissionsForRole(auth_context.role);

        return AuthenticatedConnection{
            .base_connection = base,
            .auth_context = auth_context,
            .permissions = permissions,
            .last_activity = std.time.timestamp(),
            .message_count = 0,
        };
    }

    pub fn deinit(self: *AuthenticatedConnection, allocator: Allocator) void {
        self.base_connection.deinit(allocator);
    }

    /// Get permissions based on user role
    fn permissionsForRole(role: auth.Role) ConnectionPermissions {
        return switch (role) {
            .admin => ConnectionPermissions{
                .can_receive_all_events = true,
                .can_receive_agent_events = true,
                .can_receive_file_events = true,
                .can_receive_metrics = true,
                .can_send_commands = true,
                .max_message_rate_per_minute = 1000,
            },
            .developer => ConnectionPermissions{
                .can_receive_all_events = true,
                .can_receive_agent_events = true,
                .can_receive_file_events = true,
                .can_receive_metrics = true,
                .can_send_commands = true,
                .max_message_rate_per_minute = 200,
            },
            .read_only => ConnectionPermissions{
                .can_receive_all_events = false,
                .can_receive_agent_events = true,
                .can_receive_file_events = false,
                .can_receive_metrics = true,
                .can_send_commands = false,
                .max_message_rate_per_minute = 100,
            },
            .restricted => ConnectionPermissions{
                .can_receive_all_events = false,
                .can_receive_agent_events = false,
                .can_receive_file_events = false,
                .can_receive_metrics = false,
                .can_send_commands = false,
                .max_message_rate_per_minute = 50,
            },
        };
    }

    /// Check if connection can receive a specific event type
    pub fn canReceiveEvent(self: *AuthenticatedConnection, event_type: []const u8) bool {
        // Admin can receive all events
        if (self.permissions.can_receive_all_events) return true;

        // Check specific event type permissions
        if (std.mem.eql(u8, event_type, "agent_activity") or
            std.mem.eql(u8, event_type, "agent_registered") or
            std.mem.eql(u8, event_type, "agent_unregistered"))
        {
            return self.permissions.can_receive_agent_events;
        }

        if (std.mem.eql(u8, event_type, "file_change") or
            std.mem.eql(u8, event_type, "file_lock_acquired") or
            std.mem.eql(u8, event_type, "file_lock_released"))
        {
            return self.permissions.can_receive_file_events;
        }

        if (std.mem.eql(u8, event_type, "metrics") or
            std.mem.eql(u8, event_type, "stats"))
        {
            return self.permissions.can_receive_metrics;
        }

        // Default deny for unknown event types
        return false;
    }

    /// Send message with rate limiting check
    pub fn sendMessage(self: *AuthenticatedConnection, message: []const u8) !void {
        // Check rate limiting (simplified implementation)
        const current_time = std.time.timestamp();
        const time_window = 60; // 1 minute

        // Reset message count if new minute
        if (current_time - self.last_activity >= time_window) {
            self.message_count = 0;
            self.last_activity = current_time;
        }

        // Check rate limit
        if (self.message_count >= self.permissions.max_message_rate_per_minute) {
            std.log.warn("Rate limit exceeded for WebSocket connection: {s} (user: {s})", .{ self.base_connection.id, self.auth_context.user_id });
            return error.RateLimitExceeded;
        }

        try self.base_connection.sendMessage(message);
        self.message_count += 1;
        self.last_activity = current_time;
    }

    /// Ping connection
    pub fn ping(self: *AuthenticatedConnection) !bool {
        return self.base_connection.ping();
    }
};

/// Authentication event types for WebSocket connections
pub const WebSocketAuthEvent = enum {
    connection_authenticated,
    connection_rejected,
    permission_denied,
    rate_limit_exceeded,
    connection_upgraded,
    connection_downgraded,
};

/// Authenticated WebSocket server
pub const AuthenticatedWebSocketServer = struct {
    allocator: Allocator,
    base_server: WebSocketServer,
    auth_system: *auth.AuthSystem,
    authenticated_connections: ArrayList(AuthenticatedConnection),
    connection_attempts: HashMap([]const u8, ConnectionAttempts, StringContext, std.hash_map.default_max_load_percentage),
    auth_events: ArrayList(WebSocketAuthEventRecord),
    mutex: Mutex,

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

    const ConnectionAttempts = struct {
        count: u32,
        last_attempt: i64,
        blocked_until: ?i64 = null,
    };

    const WebSocketAuthEventRecord = struct {
        timestamp: i64,
        event_type: WebSocketAuthEvent,
        user_id: []const u8,
        source_ip: ?[]const u8,
        connection_id: ?[]const u8,
        success: bool,

        pub fn deinit(self: *WebSocketAuthEventRecord, allocator: Allocator) void {
            allocator.free(self.user_id);
            if (self.source_ip) |ip| allocator.free(ip);
            if (self.connection_id) |id| allocator.free(id);
        }
    };

    /// Initialize authenticated WebSocket server
    pub fn init(allocator: Allocator, port: u16, auth_system: *auth.AuthSystem) AuthenticatedWebSocketServer {
        return AuthenticatedWebSocketServer{
            .allocator = allocator,
            .base_server = WebSocketServer.init(allocator, port),
            .auth_system = auth_system,
            .authenticated_connections = ArrayList(AuthenticatedConnection).init(allocator),
            .connection_attempts = HashMap([]const u8, ConnectionAttempts, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .auth_events = ArrayList(WebSocketAuthEventRecord).init(allocator),
            .mutex = Mutex{},
        };
    }

    /// Clean up server
    pub fn deinit(self: *AuthenticatedWebSocketServer) void {
        self.base_server.deinit();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up authenticated connections
        for (self.authenticated_connections.items) |*conn| {
            conn.deinit(self.allocator);
        }
        self.authenticated_connections.deinit();

        // Clean up connection attempts
        self.connection_attempts.deinit();

        // Clean up auth events
        for (self.auth_events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.auth_events.deinit();
    }

    /// Start authenticated WebSocket server
    pub fn start(self: *AuthenticatedWebSocketServer) !void {
        try self.base_server.start();
        std.log.info("Authenticated WebSocket server started on port {}", .{self.base_server.port});
    }

    /// Stop server
    pub fn stop(self: *AuthenticatedWebSocketServer) void {
        self.base_server.stop();
        std.log.info("Authenticated WebSocket server stopped");
    }

    /// Handle new WebSocket connection with authentication
    pub fn handleAuthenticatedConnection(self: *AuthenticatedWebSocketServer, connection: net.Server.Connection, headers: std.StringHashMap([]const u8)) !void {
        const source_ip = self.extractSourceIP(connection.address) catch "unknown";

        // Check connection rate limiting per IP
        try self.checkConnectionRateLimit(source_ip);

        // Authenticate connection
        const auth_context = self.auth_system.authenticate(headers, source_ip) catch |err| {
            try self.logAuthEvent(.connection_rejected, "anonymous", source_ip, null, false);
            connection.stream.close();

            std.log.warn("WebSocket connection rejected from {s}: authentication failed ({})", .{ source_ip, err });
            return err;
        };

        // Generate connection ID
        const connection_id = try std.fmt.allocPrint(self.allocator, "auth-ws-{d}-{s}", .{ std.time.timestamp(), auth_context.user_id[0..@min(auth_context.user_id.len, 8)] });
        defer self.allocator.free(connection_id);

        // Create authenticated connection
        var auth_connection = try AuthenticatedConnection.init(self.allocator, connection_id, connection.stream, auth_context);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.authenticated_connections.append(auth_connection);

        try self.logAuthEvent(.connection_authenticated, auth_context.user_id, source_ip, connection_id, true);

        std.log.info("Authenticated WebSocket connection: id={s} user={s} role={s} ip={s}", .{ connection_id, auth_context.user_id, auth_context.role.toString(), source_ip });

        // Send authentication success message
        const auth_message = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"auth_success\",\"connection_id\":\"{s}\",\"user_id\":\"{s}\",\"role\":\"{s}\",\"permissions\":{{\"can_send_commands\":{any},\"can_receive_metrics\":{any}}}}}", .{ connection_id, auth_context.user_id, auth_context.role.toString(), auth_connection.permissions.can_send_commands, auth_connection.permissions.can_receive_metrics });
        defer self.allocator.free(auth_message);

        // Get mutable reference for send
        var mutable_connection = &self.authenticated_connections.items[self.authenticated_connections.items.len - 1];
        mutable_connection.sendMessage(auth_message) catch |err| {
            std.log.warn("Failed to send auth success message: {}", .{err});
        };
    }

    /// Extract source IP from connection address
    fn extractSourceIP(self: *AuthenticatedWebSocketServer, address: net.Address) ![]const u8 {
        _ = self;
        switch (address.any.family) {
            std.posix.AF.INET => {
                const ip_bytes = std.mem.asBytes(&address.in.sa.addr);
                return try std.fmt.allocPrint(self.allocator, "{any}.{any}.{any}.{any}", .{ ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3] });
            },
            else => return try self.allocator.dupe(u8, "unknown"),
        }
    }

    /// Check connection rate limiting per IP
    fn checkConnectionRateLimit(self: *AuthenticatedWebSocketServer, source_ip: []const u8) !void {
        const current_time = std.time.timestamp();
        const rate_limit_window = 60; // 1 minute
        const max_attempts_per_minute = 10;

        self.mutex.lock();
        defer self.mutex.unlock();

        const gop = try self.connection_attempts.getOrPut(source_ip);

        if (gop.found_existing) {
            const attempts = gop.value_ptr;

            // Check if currently blocked
            if (attempts.blocked_until) |blocked_until| {
                if (current_time < blocked_until) {
                    std.log.warn("Connection blocked from IP {s} until {}", .{ source_ip, blocked_until });
                    return error.ConnectionBlocked;
                } else {
                    // Unblock and reset
                    attempts.blocked_until = null;
                    attempts.count = 0;
                    attempts.last_attempt = current_time;
                }
            }

            // Reset counter if new time window
            if (current_time - attempts.last_attempt > rate_limit_window) {
                attempts.count = 1;
                attempts.last_attempt = current_time;
            } else {
                attempts.count += 1;
                attempts.last_attempt = current_time;

                // Block if too many attempts
                if (attempts.count > max_attempts_per_minute) {
                    attempts.blocked_until = current_time + (15 * 60); // Block for 15 minutes
                    std.log.warn("IP {s} blocked for 15 minutes due to too many connection attempts", .{source_ip});
                    return error.ConnectionRateLimited;
                }
            }
        } else {
            gop.value_ptr.* = ConnectionAttempts{
                .count = 1,
                .last_attempt = current_time,
            };
        }
    }

    /// Broadcast message to connections with appropriate permissions
    pub fn broadcastWithPermissions(self: *AuthenticatedWebSocketServer, message: []const u8, event_type: []const u8, min_role: ?auth.Role) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.authenticated_connections.items.len) {
            var connection = &self.authenticated_connections.items[i];

            // Check role requirement
            if (min_role) |required_role| {
                if (@intFromEnum(connection.auth_context.role) < @intFromEnum(required_role)) {
                    i += 1;
                    continue;
                }
            }

            // Check event-specific permissions
            if (!connection.canReceiveEvent(event_type)) {
                try self.logAuthEvent(.permission_denied, connection.auth_context.user_id, null, connection.base_connection.id, false);
                i += 1;
                continue;
            }

            // Send message
            connection.sendMessage(message) catch |err| {
                if (err == error.RateLimitExceeded) {
                    try self.logAuthEvent(.rate_limit_exceeded, connection.auth_context.user_id, null, connection.base_connection.id, false);
                    i += 1;
                    continue;
                }

                std.log.warn("Failed to send message to WebSocket connection {s}: {}", .{ connection.base_connection.id, err });

                // Remove dead connection
                connection.deinit(self.allocator);
                _ = self.authenticated_connections.swapRemove(i);
                continue; // Don't increment i since we removed an item
            };

            i += 1;
        }
    }

    /// Broadcast to all authenticated connections (no filtering)
    pub fn broadcast(self: *AuthenticatedWebSocketServer, message: []const u8) void {
        self.broadcastWithPermissions(message, "general", null);
    }

    /// Send message to specific authenticated user
    pub fn sendToUser(self: *AuthenticatedWebSocketServer, user_id: []const u8, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.authenticated_connections.items) |*connection| {
            if (std.mem.eql(u8, connection.auth_context.user_id, user_id)) {
                try connection.sendMessage(message);
                return;
            }
        }

        return error.UserNotFound;
    }

    /// Get authenticated connection statistics
    pub fn getAuthStats(self: *AuthenticatedWebSocketServer) AuthenticatedWebSocketStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var role_counts = std.EnumMap(auth.Role, u32).init(.{});
        var total_messages: u64 = 0;

        for (self.authenticated_connections.items) |connection| {
            const current_count = role_counts.get(connection.auth_context.role) orelse 0;
            role_counts.put(connection.auth_context.role, current_count + 1);
            total_messages += connection.message_count;
        }

        return AuthenticatedWebSocketStats{
            .total_authenticated_connections = @as(u32, @intCast(self.authenticated_connections.items.len)),
            .admin_connections = role_counts.get(.admin) orelse 0,
            .developer_connections = role_counts.get(.developer) orelse 0,
            .read_only_connections = role_counts.get(.read_only) orelse 0,
            .restricted_connections = role_counts.get(.restricted) orelse 0,
            .total_messages_sent = total_messages,
            .blocked_ips = @as(u32, @intCast(self.connection_attempts.count())),
            .auth_events = @as(u32, @intCast(self.auth_events.items.len)),
        };
    }

    /// Clean up dead connections and expired blocks
    pub fn performMaintenance(self: *AuthenticatedWebSocketServer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up dead connections
        var i: usize = 0;
        var removed_count: u32 = 0;

        while (i < self.authenticated_connections.items.len) {
            var connection = &self.authenticated_connections.items[i];

            const is_alive = connection.ping() catch false;
            if (!is_alive) {
                std.log.info("Removing dead authenticated WebSocket connection: {s} (user: {s})", .{ connection.base_connection.id, connection.auth_context.user_id });
                connection.deinit(self.allocator);
                _ = self.authenticated_connections.swapRemove(i);
                removed_count += 1;
                continue; // Don't increment i since we removed an item
            }

            i += 1;
        }

        // Clean up expired connection attempts
        const current_time = std.time.timestamp();
        var attempts_to_remove = ArrayList([]const u8).init(self.allocator);
        defer attempts_to_remove.deinit();

        var attempts_iterator = self.connection_attempts.iterator();
        while (attempts_iterator.next()) |entry| {
            const attempts = entry.value_ptr;

            // Remove if blocked time has passed and no recent activity
            if (attempts.blocked_until) |blocked_until| {
                if (current_time > blocked_until + 3600) { // 1 hour after unblock
                    attempts_to_remove.append(entry.key_ptr.*) catch continue;
                }
            } else if (current_time - attempts.last_attempt > 3600) { // 1 hour since last attempt
                attempts_to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (attempts_to_remove.items) |ip| {
            _ = self.connection_attempts.remove(ip);
        }

        if (removed_count > 0 or attempts_to_remove.items.len > 0) {
            std.log.info("WebSocket maintenance: removed {} dead connections, {} expired IP blocks", .{ removed_count, attempts_to_remove.items.len });
        }
    }

    /// Log authentication event
    fn logAuthEvent(self: *AuthenticatedWebSocketServer, event_type: WebSocketAuthEvent, user_id: []const u8, source_ip: ?[]const u8, connection_id: ?[]const u8, success: bool) !void {
        var event = WebSocketAuthEventRecord{
            .timestamp = std.time.timestamp(),
            .event_type = event_type,
            .user_id = try self.allocator.dupe(u8, user_id),
            .source_ip = if (source_ip) |ip| try self.allocator.dupe(u8, ip) else null,
            .connection_id = if (connection_id) |id| try self.allocator.dupe(u8, id) else null,
            .success = success,
        };

        try self.auth_events.append(event);

        // Keep only last 500 events
        if (self.auth_events.items.len > 500) {
            var old_event = self.auth_events.orderedRemove(0);
            old_event.deinit(self.allocator);
        }
    }
};

/// Statistics for authenticated WebSocket connections
pub const AuthenticatedWebSocketStats = struct {
    total_authenticated_connections: u32,
    admin_connections: u32,
    developer_connections: u32,
    read_only_connections: u32,
    restricted_connections: u32,
    total_messages_sent: u64,
    blocked_ips: u32,
    auth_events: u32,
};

// Unit Tests
test "AuthenticatedConnection permissions for roles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const admin_context = auth.AuthContext{
        .authenticated = true,
        .user_id = "admin",
        .role = .admin,
        .auth_method = .api_key,
        .allowed_tools = null,
    };

    const readonly_context = auth.AuthContext{
        .authenticated = true,
        .user_id = "readonly",
        .role = .read_only,
        .auth_method = .api_key,
        .allowed_tools = null,
    };

    // Test admin permissions
    const admin_perms = AuthenticatedConnection.permissionsForRole(.admin);
    try testing.expect(admin_perms.can_receive_all_events == true);
    try testing.expect(admin_perms.can_send_commands == true);
    try testing.expect(admin_perms.max_message_rate_per_minute == 1000);

    // Test read-only permissions
    const readonly_perms = AuthenticatedConnection.permissionsForRole(.read_only);
    try testing.expect(readonly_perms.can_receive_all_events == false);
    try testing.expect(readonly_perms.can_send_commands == false);
    try testing.expect(readonly_perms.can_receive_metrics == true);

    _ = admin_context;
    _ = readonly_context;
}

test "Event permission checking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a mock socket for testing (this is a simplified approach)
    // In a real test, you would need to create a proper network connection
    const mock_socket = std.net.Stream{ .handle = 0 };

    const readonly_context = auth.AuthContext{
        .authenticated = true,
        .user_id = "readonly",
        .role = .read_only,
        .auth_method = .api_key,
        .allowed_tools = null,
    };

    var connection = try AuthenticatedConnection.init(allocator, "test-conn", mock_socket, readonly_context);
    defer connection.deinit(allocator);

    // Test event permissions
    try testing.expect(connection.canReceiveEvent("agent_activity") == true);
    try testing.expect(connection.canReceiveEvent("file_change") == false);
    try testing.expect(connection.canReceiveEvent("metrics") == true);
}

test "AuthenticatedWebSocketServer initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const auth_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
    };

    var auth_system = auth.AuthSystem.init(allocator, auth_config);
    defer auth_system.deinit();

    var server = AuthenticatedWebSocketServer.init(allocator, 8080, &auth_system);
    defer server.deinit();

    const stats = server.getAuthStats();
    try testing.expect(stats.total_authenticated_connections == 0);
    try testing.expect(stats.admin_connections == 0);
}
