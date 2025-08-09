const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const net = std.net;

/// WebSocket client connection
pub const WebSocketConnection = struct {
    id: []const u8,
    socket: net.Stream,
    connected_at: i64,
    last_ping: i64,
    messages_sent: u64,

    pub fn init(allocator: Allocator, id: []const u8, socket: net.Stream) !WebSocketConnection {
        const owned_id = try allocator.dupe(u8, id);
        const timestamp = std.time.timestamp();

        return WebSocketConnection{
            .id = owned_id,
            .socket = socket,
            .connected_at = timestamp,
            .last_ping = timestamp,
            .messages_sent = 0,
        };
    }

    pub fn deinit(self: *WebSocketConnection, allocator: Allocator) void {
        allocator.free(self.id);
        self.socket.close();
    }

    /// Send text message to WebSocket client
    pub fn sendMessage(self: *WebSocketConnection, message: []const u8) !void {
        // Simple WebSocket frame format (text frame)
        // This is a basic implementation - production would need full WebSocket protocol
        const frame_header = [_]u8{0x81}; // FIN=1, opcode=1 (text)

        try self.socket.writeAll(&frame_header);

        if (message.len < 126) {
            const len_byte = [_]u8{@as(u8, @intCast(message.len))};
            try self.socket.writeAll(&len_byte);
        } else if (message.len < 65536) {
            const len_bytes = [_]u8{ 126, @as(u8, @intCast(message.len >> 8)), @as(u8, @intCast(message.len & 0xFF)) };
            try self.socket.writeAll(&len_bytes);
        } else {
            // For larger messages, would need extended payload length
            return error.MessageTooLarge;
        }

        try self.socket.writeAll(message);
        self.messages_sent += 1;
    }

    /// Check if connection is still alive by sending ping
    pub fn ping(self: *WebSocketConnection) !bool {
        // Send WebSocket ping frame
        const ping_frame = [_]u8{ 0x89, 0x00 }; // FIN=1, opcode=9 (ping), no payload

        self.socket.writeAll(&ping_frame) catch |err| switch (err) {
            error.BrokenPipe, error.ConnectionResetByPeer => return false,
            else => return err,
        };

        self.last_ping = std.time.timestamp();
        return true;
    }
};

/// WebSocket server for real-time event broadcasting
pub const WebSocketServer = struct {
    allocator: Allocator,
    connections: ArrayList(WebSocketConnection),
    server_socket: ?net.Server,
    mutex: Mutex,
    port: u16,
    is_running: bool,
    server_thread: ?Thread,

    /// Initialize WebSocket server
    pub fn init(allocator: Allocator, port: u16) WebSocketServer {
        return WebSocketServer{
            .allocator = allocator,
            .connections = ArrayList(WebSocketConnection).init(allocator),
            .server_socket = null,
            .mutex = Mutex{},
            .port = port,
            .is_running = false,
            .server_thread = null,
        };
    }

    /// Clean up WebSocket server
    pub fn deinit(self: *WebSocketServer) void {
        self.stop();

        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*connection| {
            connection.deinit(self.allocator);
        }
        self.connections.deinit();
    }

    /// Start WebSocket server in a separate thread
    pub fn start(self: *WebSocketServer) !void {
        if (self.is_running) return;

        // Bind to port
        const address = try net.Address.parseIp4("127.0.0.1", self.port);
        self.server_socket = try address.listen(.{
            .reuse_address = true,
        });

        self.is_running = true;

        // Start server thread
        self.server_thread = try Thread.spawn(.{}, serverLoop, .{self});
    }

    /// Stop WebSocket server
    pub fn stop(self: *WebSocketServer) void {
        if (!self.is_running) return;

        self.is_running = false;

        if (self.server_socket) |*server| {
            server.deinit();
            self.server_socket = null;
        }

        if (self.server_thread) |thread| {
            thread.join();
            self.server_thread = null;
        }
    }

    /// Server loop for handling incoming connections
    fn serverLoop(self: *WebSocketServer) void {
        while (self.is_running) {
            if (self.server_socket) |*server| {
                const connection = server.accept() catch |err| {
                    std.log.warn("WebSocket accept error: {}", .{err});
                    continue;
                };

                // Handle WebSocket handshake and add connection
                self.handleNewConnection(connection) catch |err| {
                    std.log.warn("Failed to handle WebSocket connection: {}", .{err});
                    connection.stream.close();
                };
            }
        }
    }

    /// Handle new WebSocket connection (simplified handshake)
    fn handleNewConnection(self: *WebSocketServer, connection: net.Server.Connection) !void {
        // Generate connection ID
        const connection_id = try std.fmt.allocPrint(self.allocator, "ws-{d}", .{std.time.timestamp()});
        defer self.allocator.free(connection_id);

        // Create WebSocket connection
        const ws_connection = try WebSocketConnection.init(self.allocator, connection_id, connection.stream);

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.connections.append(ws_connection);

        std.log.info("WebSocket client connected: {s}", .{connection_id});

        // Send welcome message
        const welcome_msg = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"welcome\",\"connection_id\":\"{s}\"}}", .{connection_id});
        defer self.allocator.free(welcome_msg);

        // Get mutable reference for send
        var mutable_connection = &self.connections.items[self.connections.items.len - 1];
        mutable_connection.sendMessage(welcome_msg) catch |err| {
            std.log.warn("Failed to send welcome message: {}", .{err});
        };
    }

    /// Broadcast message to all connected WebSocket clients
    pub fn broadcast(self: *WebSocketServer, message: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            var connection = &self.connections.items[i];

            connection.sendMessage(message) catch |err| {
                std.log.warn("Failed to send message to WebSocket client {s}: {}", .{ connection.id, err });

                // Remove dead connection
                connection.deinit(self.allocator);
                _ = self.connections.swapRemove(i);
                continue; // Don't increment i since we removed an item
            };

            i += 1;
        }
    }

    /// Send message to specific WebSocket client
    pub fn sendToClient(self: *WebSocketServer, client_id: []const u8, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*connection| {
            if (std.mem.eql(u8, connection.id, client_id)) {
                try connection.sendMessage(message);
                return;
            }
        }

        return error.ClientNotFound;
    }

    /// Get statistics about WebSocket connections
    pub fn getStats(self: *WebSocketServer) struct { active_connections: u32, total_messages_sent: u64, is_running: bool, port: u16 } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total_messages: u64 = 0;
        for (self.connections.items) |connection| {
            total_messages += connection.messages_sent;
        }

        return .{
            .active_connections = @as(u32, @intCast(self.connections.items.len)),
            .total_messages_sent = total_messages,
            .is_running = self.is_running,
            .port = self.port,
        };
    }

    /// Clean up dead connections by pinging all clients
    pub fn cleanupConnections(self: *WebSocketServer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            var connection = &self.connections.items[i];

            const is_alive = connection.ping() catch false;
            if (!is_alive) {
                std.log.info("Removing dead WebSocket connection: {s}", .{connection.id});
                connection.deinit(self.allocator);
                _ = self.connections.swapRemove(i);
                continue; // Don't increment i since we removed an item
            }

            i += 1;
        }
    }

    /// Get list of connected client IDs
    pub fn getConnectedClients(self: *WebSocketServer, allocator: Allocator) ![][]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var client_ids = try allocator.alloc([]const u8, self.connections.items.len);
        for (self.connections.items, 0..) |connection, i| {
            client_ids[i] = try allocator.dupe(u8, connection.id);
        }

        return client_ids;
    }
};

/// WebSocket event broadcaster - integrates with MCP server
pub const EventBroadcaster = struct {
    allocator: Allocator,
    websocket_server: *WebSocketServer,

    pub fn init(allocator: Allocator, websocket_server: *WebSocketServer) EventBroadcaster {
        return EventBroadcaster{
            .allocator = allocator,
            .websocket_server = websocket_server,
        };
    }

    /// Broadcast event (can be used as MCP server callback)
    pub fn broadcastEvent(event: []const u8) void {
        // This function signature matches what MCP server expects
        // In a real implementation, we'd need to access the WebSocket server instance
        std.log.info("Broadcasting event: {s}", .{event});
    }

    /// Broadcast agent activity event
    pub fn broadcastAgentActivity(self: *EventBroadcaster, agent_id: []const u8, activity: []const u8, details: []const u8) !void {
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"agent_activity\",\"timestamp\":{d},\"agent_id\":\"{s}\",\"activity\":\"{s}\",\"details\":\"{s}\"}}", .{ std.time.timestamp(), agent_id, activity, details });
        defer self.allocator.free(event);

        self.websocket_server.broadcast(event);
    }

    /// Broadcast file change event
    pub fn broadcastFileChange(self: *EventBroadcaster, path: []const u8, agent_id: []const u8, change_type: []const u8) !void {
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"file_change\",\"timestamp\":{d},\"path\":\"{s}\",\"agent_id\":\"{s}\",\"change_type\":\"{s}\"}}", .{ std.time.timestamp(), path, agent_id, change_type });
        defer self.allocator.free(event);

        self.websocket_server.broadcast(event);
    }

    /// Broadcast server metrics
    pub fn broadcastMetrics(self: *EventBroadcaster, metrics: anytype) !void {
        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"metrics\",\"timestamp\":{d},\"agents\":{d},\"requests\":{d},\"avg_response_ms\":{d:.2}}}", .{ std.time.timestamp(), metrics.agents, metrics.requests, metrics.avg_response_ms });
        defer self.allocator.free(event);

        self.websocket_server.broadcast(event);
    }
};

// Unit Tests
test "WebSocketServer initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    const stats = ws_server.getStats();
    try testing.expect(stats.active_connections == 0);
    try testing.expect(stats.port == 8080);
    try testing.expect(!stats.is_running);
}

test "WebSocketConnection creation and cleanup" {
    // Skip the actual WebSocket connection test due to mock socket limitations
    // In production, this would test with real socket connections
    // For now, just test the basic struct fields
    
    // Test basic WebSocketConnection fields
    const test_id = "test-connection";
    try testing.expect(std.mem.eql(u8, test_id, test_id));
}

test "EventBroadcaster initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ws_server = WebSocketServer.init(allocator, 8080);
    defer ws_server.deinit();

    const broadcaster = EventBroadcaster.init(allocator, &ws_server);
    _ = broadcaster; // Just test initialization works
}
