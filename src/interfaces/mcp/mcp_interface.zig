//! MCP Interface Adapter for Agrama
//!
//! This module provides the Model Context Protocol (MCP) interface to Agrama's
//! temporal knowledge graph. MCP is ONE OF SEVERAL interfaces available for
//! interacting with Agrama - it's specifically designed for AI agents like Claude.
//!
//! The MCP interface translates MCP protocol requests into Agrama primitive operations
//! and formats responses according to the MCP specification.
//!
//! This is NOT the core of Agrama - it's just an adapter layer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

// Import core Agrama components
const Database = @import("../../database.zig").Database;
const SemanticDatabase = @import("../../semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("../../triple_hybrid_search.zig").TripleHybridSearchEngine;
const PrimitiveEngine = @import("../../primitive_engine.zig").PrimitiveEngine;
const OrchestrationContext = @import("../../orchestration_context.zig").OrchestrationContext;

// Import MCP protocol implementation
const MCPProtocol = @import("../../mcp_primitive_server.zig");

/// MCP Interface - Adapter between MCP protocol and Agrama core
pub const MCPInterface = struct {
    allocator: Allocator,
    
    /// Core Agrama components (references, not owned)
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,
    orchestration: *OrchestrationContext,
    
    /// MCP protocol handler
    mcp_server: MCPProtocol.PrimitiveMCPServer,
    
    /// Whether this interface is active
    enabled: bool,
    
    /// Interface statistics
    stats: InterfaceStats,
    
    const InterfaceStats = struct {
        requests_handled: u64 = 0,
        total_response_time_ns: u64 = 0,
        active_sessions: u32 = 0,
        
        pub fn getAverageResponseMs(self: InterfaceStats) f64 {
            if (self.requests_handled == 0) return 0.0;
            const avg_ns = @as(f64, @floatFromInt(self.total_response_time_ns)) / @as(f64, @floatFromInt(self.requests_handled));
            return avg_ns / 1_000_000.0; // Convert to milliseconds
        }
    };
    
    /// Initialize the MCP interface adapter
    pub fn init(
        allocator: Allocator,
        database: *Database,
        semantic_db: *SemanticDatabase,
        graph_engine: *TripleHybridSearchEngine,
        orchestration: *OrchestrationContext,
    ) !MCPInterface {
        const mcp_server = try MCPProtocol.PrimitiveMCPServer.init(
            allocator,
            database,
            semantic_db,
            graph_engine,
        );
        
        return MCPInterface{
            .allocator = allocator,
            .database = database,
            .semantic_db = semantic_db,
            .graph_engine = graph_engine,
            .orchestration = orchestration,
            .mcp_server = mcp_server,
            .enabled = false,
            .stats = InterfaceStats{},
        };
    }
    
    /// Clean up the MCP interface
    pub fn deinit(self: *MCPInterface) void {
        self.mcp_server.deinit();
    }
    
    /// Enable the MCP interface
    pub fn enable(self: *MCPInterface) !void {
        if (self.enabled) return;
        
        self.enabled = true;
        std.log.info("MCP interface enabled - AI agents can now connect via Model Context Protocol", .{});
        
        // Register as a participant in the orchestration
        try self.orchestration.addParticipant("mcp_interface", .AIAgent, .MCP);
    }
    
    /// Disable the MCP interface
    pub fn disable(self: *MCPInterface) void {
        if (!self.enabled) return;
        
        self.enabled = false;
        std.log.info("MCP interface disabled", .{});
        
        // Remove from orchestration
        self.orchestration.removeParticipant("mcp_interface");
    }
    
    /// Start the MCP server (blocking)
    pub fn start(self: *MCPInterface) !void {
        if (!self.enabled) {
            return error.InterfaceNotEnabled;
        }
        
        std.log.info("Starting MCP interface on stdio...", .{});
        try self.mcp_server.start();
    }
    
    /// Handle an MCP request (for testing or programmatic access)
    pub fn handleRequest(self: *MCPInterface, request: MCPProtocol.MCPRequest, agent_id: []const u8) !MCPProtocol.MCPResponse {
        if (!self.enabled) {
            return error.InterfaceNotEnabled;
        }
        
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
            self.stats.requests_handled += 1;
            self.stats.total_response_time_ns += elapsed;
        }
        
        // Record participant activity
        self.orchestration.recordContribution(agent_id);
        
        return self.mcp_server.handleRequest(request, agent_id);
    }
    
    /// Get interface statistics
    pub fn getStats(self: *MCPInterface) struct {
        enabled: bool,
        requests_handled: u64,
        avg_response_ms: f64,
        active_sessions: u32,
    } {
        return .{
            .enabled = self.enabled,
            .requests_handled = self.stats.requests_handled,
            .avg_response_ms = self.stats.getAverageResponseMs(),
            .active_sessions = self.stats.active_sessions,
        };
    }
    
    /// Get interface description
    pub fn getDescription() []const u8 {
        return 
            \\MCP (Model Context Protocol) Interface
            \\
            \\Provides AI agents with access to Agrama's temporal knowledge graph
            \\through a standardized protocol. Supports the 5 core primitives:
            \\- store: Save data with metadata
            \\- retrieve: Access data with history
            \\- search: Multi-modal search capabilities
            \\- link: Create knowledge graph relationships
            \\- transform: Apply data transformations
            \\
            \\This is one of several interfaces available for Agrama.
        ;
    }
};