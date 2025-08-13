//! Orchestration Context - Managing collaborative participants in the Orchestrated Mind
//!
//! This module implements the vision of "a thousand AI agents working on a single codebase"
//! where humans and AI agents are equal participants sharing a continuous memory through
//! the temporal knowledge graph.
//!
//! Core concepts:
//! - Participants: Both humans and AI agents connected to the system
//! - Shared Context: All participants access the same evolving knowledge graph
//! - Collaborative State: Real-time tracking of what each participant is working on
//! - Orchestration: Coordination without central control - emergent collaboration

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const testing = std.testing;

/// Type of participant in the orchestrated system
pub const ParticipantType = enum {
    Human, // Human developers providing strategic direction
    AIAgent, // AI agents executing tasks and reasoning
    Hybrid, // Future: Human-AI hybrid interfaces
};

/// Connection method for participant
pub const ConnectionType = enum {
    WebSocket, // Real-time WebSocket connection (Observatory)
    MCP, // Model Context Protocol connection
    Direct, // Direct API connection
    Internal, // Internal system participant
};

/// Participant in the orchestrated collaborative system
pub const Participant = struct {
    id: []const u8, // Unique identifier
    type: ParticipantType, // Human or AI agent
    connection: ConnectionType, // How they're connected
    session_start: i64, // When they joined
    contributions: u32, // Operations performed
    current_context: []const u8, // What they're working on
    last_activity: i64, // Last activity timestamp

    /// Initialize a new participant
    pub fn init(allocator: Allocator, id: []const u8, participant_type: ParticipantType, connection: ConnectionType) !Participant {
        const owned_id = try allocator.dupe(u8, id);
        const timestamp = std.time.timestamp();

        return Participant{
            .id = owned_id,
            .type = participant_type,
            .connection = connection,
            .session_start = timestamp,
            .contributions = 0,
            .current_context = try allocator.dupe(u8, "initializing"),
            .last_activity = timestamp,
        };
    }

    /// Clean up participant resources
    pub fn deinit(self: *Participant, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.current_context);
    }

    /// Update participant's current working context
    pub fn updateContext(self: *Participant, allocator: Allocator, new_context: []const u8) !void {
        allocator.free(self.current_context);
        self.current_context = try allocator.dupe(u8, new_context);
        self.last_activity = std.time.timestamp();
    }

    /// Record a contribution from this participant
    pub fn recordContribution(self: *Participant) void {
        self.contributions += 1;
        self.last_activity = std.time.timestamp();
    }
};

/// Collaborative event types for the orchestrated system
pub const CollaborativeEvent = enum {
    ParticipantJoined, // New participant connected
    ParticipantLeft, // Participant disconnected
    ContextShared, // Shared knowledge/insight
    PatternDiscovered, // New pattern identified in knowledge graph
    ConsensusReached, // Multiple participants agree on approach
    ConflictResolved, // CRDT or decision conflict resolved
    MemoryEvolved, // Knowledge graph structure evolved
};

/// Orchestration context managing all participants
pub const OrchestrationContext = struct {
    allocator: Allocator,
    participants: HashMap([]const u8, Participant, StringContext, std.hash_map.default_max_load_percentage),
    active_count: u32,
    total_contributions: u64,
    session_start: i64,

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

    /// Initialize orchestration context
    pub fn init(allocator: Allocator) OrchestrationContext {
        return OrchestrationContext{
            .allocator = allocator,
            .participants = HashMap([]const u8, Participant, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .active_count = 0,
            .total_contributions = 0,
            .session_start = std.time.timestamp(),
        };
    }

    /// Clean up orchestration context
    pub fn deinit(self: *OrchestrationContext) void {
        var iterator = self.participants.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var participant = entry.value_ptr.*;
            participant.deinit(self.allocator);
        }
        self.participants.deinit();
    }

    /// Add a new participant to the orchestrated system
    pub fn addParticipant(self: *OrchestrationContext, id: []const u8, participant_type: ParticipantType, connection: ConnectionType) !void {
        const owned_id = try self.allocator.dupe(u8, id);
        const participant = try Participant.init(self.allocator, id, participant_type, connection);

        try self.participants.put(owned_id, participant);
        self.active_count += 1;

        std.log.info("Participant joined: {s} ({s}) via {s}", .{ id, @tagName(participant_type), @tagName(connection) });
    }

    /// Remove a participant from the system
    pub fn removeParticipant(self: *OrchestrationContext, id: []const u8) void {
        if (self.participants.fetchRemove(id)) |entry| {
            self.allocator.free(entry.key);
            var participant = entry.value;
            participant.deinit(self.allocator);
            self.active_count -= 1;

            std.log.info("Participant left: {s}", .{id});
        }
    }

    /// Update participant context
    pub fn updateParticipantContext(self: *OrchestrationContext, id: []const u8, context: []const u8) !void {
        if (self.participants.getPtr(id)) |participant| {
            try participant.updateContext(self.allocator, context);
        }
    }

    /// Record a contribution from a participant
    pub fn recordContribution(self: *OrchestrationContext, id: []const u8) void {
        if (self.participants.getPtr(id)) |participant| {
            participant.recordContribution();
            self.total_contributions += 1;
        }
    }

    /// Get statistics about the orchestrated system
    pub fn getStats(self: *OrchestrationContext) struct {
        active_participants: u32,
        human_count: u32,
        ai_agent_count: u32,
        total_contributions: u64,
        avg_contributions_per_participant: f64,
        session_duration_seconds: i64,
    } {
        var human_count: u32 = 0;
        var ai_agent_count: u32 = 0;

        var iterator = self.participants.iterator();
        while (iterator.next()) |entry| {
            switch (entry.value_ptr.type) {
                .Human => human_count += 1,
                .AIAgent => ai_agent_count += 1,
                .Hybrid => {},
            }
        }

        const avg_contributions = if (self.active_count > 0)
            @as(f64, @floatFromInt(self.total_contributions)) / @as(f64, @floatFromInt(self.active_count))
        else
            0.0;

        return .{
            .active_participants = self.active_count,
            .human_count = human_count,
            .ai_agent_count = ai_agent_count,
            .total_contributions = self.total_contributions,
            .avg_contributions_per_participant = avg_contributions,
            .session_duration_seconds = std.time.timestamp() - self.session_start,
        };
    }

    /// Get active participants list
    pub fn getActiveParticipants(self: *OrchestrationContext, allocator: Allocator) ![]Participant {
        var participants = try allocator.alloc(Participant, self.participants.count());
        var idx: usize = 0;

        var iterator = self.participants.iterator();
        while (iterator.next()) |entry| {
            participants[idx] = entry.value_ptr.*;
            idx += 1;
        }

        return participants;
    }
};

// Tests
test "Participant initialization and lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var participant = try Participant.init(allocator, "test_agent", .AIAgent, .MCP);
    defer participant.deinit(allocator);

    try testing.expect(std.mem.eql(u8, participant.id, "test_agent"));
    try testing.expect(participant.type == .AIAgent);
    try testing.expect(participant.connection == .MCP);
    try testing.expect(participant.contributions == 0);
}

test "OrchestrationContext participant management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = OrchestrationContext.init(allocator);
    defer context.deinit();

    // Add participants
    try context.addParticipant("claude", .AIAgent, .MCP);
    try context.addParticipant("human_dev", .Human, .WebSocket);

    try testing.expect(context.active_count == 2);

    // Record contributions
    context.recordContribution("claude");
    context.recordContribution("claude");
    context.recordContribution("human_dev");

    try testing.expect(context.total_contributions == 3);

    // Get stats
    const stats = context.getStats();
    try testing.expect(stats.active_participants == 2);
    try testing.expect(stats.human_count == 1);
    try testing.expect(stats.ai_agent_count == 1);
    try testing.expect(stats.total_contributions == 3);

    // Remove participant
    context.removeParticipant("claude");
    try testing.expect(context.active_count == 1);
}

test "OrchestrationContext context updates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = OrchestrationContext.init(allocator);
    defer context.deinit();

    try context.addParticipant("agent1", .AIAgent, .MCP);
    try context.updateParticipantContext("agent1", "analyzing code patterns");

    const participant = context.participants.get("agent1").?;
    try testing.expect(std.mem.eql(u8, participant.current_context, "analyzing code patterns"));
}
