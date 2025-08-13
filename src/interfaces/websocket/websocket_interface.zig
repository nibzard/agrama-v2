//! WebSocket Interface Adapter for Agrama
//!
//! This module provides the WebSocket interface to Agrama's temporal knowledge graph.
//! It's designed for real-time communication with web-based Observatory clients and
//! other systems that need push-based event streaming.
//!
//! The WebSocket interface enables:
//! - Real-time event broadcasting
//! - Live collaboration monitoring
//! - Observatory visualization updates
//! - Human-AI interaction through web clients
//!
//! This is NOT the core of Agrama - it's just an adapter layer.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import core Agrama components
const Database = @import("../../database.zig").Database;
const OrchestrationContext = @import("../../orchestration_context.zig").OrchestrationContext;
const EventBroadcaster = @import("../../websocket.zig").EventBroadcaster;
const WebSocketServer = @import("../../websocket.zig").WebSocketServer;

/// WebSocket Interface - Real-time event streaming adapter for Agrama
pub const WebSocketInterface = struct {
    allocator: Allocator,

    /// Core Agrama components (references, not owned)
    database: *Database,
    orchestration: *OrchestrationContext,

    /// WebSocket components
    websocket_server: WebSocketServer,
    event_broadcaster: EventBroadcaster,

    /// Configuration
    port: u16,
    enabled: bool,

    /// Interface statistics
    stats: InterfaceStats,

    const InterfaceStats = struct {
        total_events_broadcast: u64 = 0,
        total_connections: u32 = 0,
        active_connections: u32 = 0,
    };

    /// Initialize the WebSocket interface adapter
    pub fn init(
        allocator: Allocator,
        database: *Database,
        orchestration: *OrchestrationContext,
        port: u16,
    ) WebSocketInterface {
        var websocket_server = WebSocketServer.init(allocator, port);
        const event_broadcaster = EventBroadcaster.init(allocator, &websocket_server);

        return WebSocketInterface{
            .allocator = allocator,
            .database = database,
            .orchestration = orchestration,
            .websocket_server = websocket_server,
            .event_broadcaster = event_broadcaster,
            .port = port,
            .enabled = false,
            .stats = InterfaceStats{},
        };
    }

    /// Clean up the WebSocket interface
    pub fn deinit(self: *WebSocketInterface) void {
        if (self.enabled) {
            self.disable();
        }
        self.websocket_server.deinit();
    }

    /// Enable the WebSocket interface
    pub fn enable(self: *WebSocketInterface) !void {
        if (self.enabled) return;

        try self.websocket_server.start();
        self.enabled = true;

        std.log.info("WebSocket interface enabled on port {d} - Observatory and real-time clients can connect", .{self.port});

        // Register as a participant in the orchestration
        try self.orchestration.addParticipant("websocket_interface", .Human, .WebSocket);
    }

    /// Disable the WebSocket interface
    pub fn disable(self: *WebSocketInterface) void {
        if (!self.enabled) return;

        self.websocket_server.stop();
        self.enabled = false;

        std.log.info("WebSocket interface disabled", .{});

        // Remove from orchestration
        self.orchestration.removeParticipant("websocket_interface");
    }

    /// Broadcast an event to all connected clients
    pub fn broadcastEvent(self: *WebSocketInterface, event_type: []const u8, data: anytype) !void {
        if (!self.enabled) {
            return error.InterfaceNotEnabled;
        }

        const event = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"{s}\",\"timestamp\":{d},\"data\":{any}}}", .{ event_type, std.time.timestamp(), data });
        defer self.allocator.free(event);

        try self.websocket_server.broadcast(event);
        self.stats.total_events_broadcast += 1;
    }

    /// Broadcast participant activity
    pub fn broadcastParticipantActivity(self: *WebSocketInterface, participant_id: []const u8, activity: []const u8, details: []const u8) !void {
        if (!self.enabled) return;

        try self.event_broadcaster.broadcastAgentActivity(participant_id, activity, details);
        self.stats.total_events_broadcast += 1;

        // Update orchestration context
        try self.orchestration.updateParticipantContext(participant_id, activity);
    }

    /// Broadcast file change event
    pub fn broadcastFileChange(self: *WebSocketInterface, path: []const u8, participant_id: []const u8, change_type: []const u8) !void {
        if (!self.enabled) return;

        try self.event_broadcaster.broadcastFileChange(path, participant_id, change_type);
        self.stats.total_events_broadcast += 1;
    }

    /// Get interface statistics
    pub fn getStats(self: *WebSocketInterface) struct {
        enabled: bool,
        port: u16,
        active_connections: u32,
        total_events_broadcast: u64,
    } {
        const ws_stats = self.websocket_server.getStats();

        return .{
            .enabled = self.enabled,
            .port = self.port,
            .active_connections = ws_stats.active_connections,
            .total_events_broadcast = self.stats.total_events_broadcast,
        };
    }

    /// Get interface description
    pub fn getDescription() []const u8 {
        return 
        \\WebSocket Interface
        \\
        \\Provides real-time bidirectional communication for:
        \\- Observatory web clients
        \\- Live collaboration monitoring
        \\- Event streaming
        \\- Human-AI interaction dashboards
        \\
        \\Broadcasts all participant activities, file changes, and
        \\system events to connected clients in real-time.
        \\
        \\This is one of several interfaces available for Agrama.
        ;
    }
};
