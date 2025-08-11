//! Agrama Temporal Knowledge Graph Database
//! Phase 2: MCP Server with AI Agent Collaboration
const std = @import("std");
const testing = std.testing;

// Export the core Database module
pub const Database = @import("database.zig").Database;
pub const Change = @import("database.zig").Change;

// Export MCP Server components
pub const MCPServer = @import("mcp_server.zig").MCPServer;
pub const MCPRequest = @import("mcp_server.zig").MCPRequest;
pub const MCPResponse = @import("mcp_server.zig").MCPResponse;
pub const AgentInfo = @import("mcp_server.zig").AgentInfo;
pub const MCPMetrics = @import("mcp_server.zig").MCPMetrics;

// Export MCP Compliant Server components
pub const MCPCompliantServer = @import("mcp_compliant_server.zig").MCPCompliantServer;
pub const MCPToolDefinition = @import("mcp_compliant_server.zig").MCPToolDefinition;
pub const MCPContent = @import("mcp_compliant_server.zig").MCPContent;
pub const MCPToolResponse = @import("mcp_compliant_server.zig").MCPToolResponse;

// Export WebSocket components
pub const WebSocketServer = @import("websocket.zig").WebSocketServer;
pub const WebSocketConnection = @import("websocket.zig").WebSocketConnection;
pub const EventBroadcaster = @import("websocket.zig").EventBroadcaster;

// Export Agent Manager components
pub const AgentManager = @import("agent_manager.zig").AgentManager;
pub const AgentSession = @import("agent_manager.zig").AgentSession;
pub const FileLock = @import("agent_manager.zig").FileLock;

// Export Frontier Reduction Engine components
pub const FrontierReductionEngine = @import("fre.zig").FrontierReductionEngine;
pub const TemporalNode = @import("fre.zig").TemporalNode;
pub const TemporalEdge = @import("fre.zig").TemporalEdge;
pub const PathResult = @import("fre.zig").PathResult;
pub const ImpactAnalysis = @import("fre.zig").ImpactAnalysis;
pub const DependencyGraph = @import("fre.zig").DependencyGraph;
pub const TraversalDirection = @import("fre.zig").TraversalDirection;
pub const NodeType = @import("fre.zig").NodeType;
pub const RelationType = @import("fre.zig").RelationType;
pub const TimeRange = @import("fre.zig").TimeRange;

// Export HNSW components
pub const HNSWIndex = @import("hnsw.zig").HNSWIndex;
pub const Vector = @import("hnsw.zig").Vector;
pub const MatryoshkaEmbedding = @import("hnsw.zig").MatryoshkaEmbedding;
pub const SearchResult = @import("hnsw.zig").SearchResult;
pub const HNSWSearchParams = @import("hnsw.zig").HNSWSearchParams;
pub const NodeID = @import("hnsw.zig").NodeID;

// Export Semantic Database components
pub const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
pub const SemanticSearchResult = @import("semantic_database.zig").SemanticSearchResult;
pub const SemanticHybridQuery = @import("semantic_database.zig").HybridQuery;
pub const SemanticDatabaseStats = @import("semantic_database.zig").SemanticDatabaseStats;

// Export CRDT components
pub const VectorClock = @import("crdt.zig").VectorClock;
pub const Position = @import("crdt.zig").Position;
pub const OperationType = @import("crdt.zig").OperationType;
pub const CRDTOperation = @import("crdt.zig").CRDTOperation;
pub const ConflictEvent = @import("crdt.zig").ConflictEvent;
pub const AgentCursor = @import("crdt.zig").AgentCursor;
pub const CRDTDocument = @import("crdt.zig").CRDTDocument;

// Export CRDT Manager components
pub const CRDTManager = @import("crdt_manager.zig").CRDTManager;
pub const AgentCRDTSession = @import("crdt_manager.zig").AgentCRDTSession;
pub const CollaborativeContext = @import("crdt_manager.zig").CollaborativeContext;
pub const CRDTStats = @import("crdt_manager.zig").CRDTStats;

// Export CRDT MCP Tools
pub const MCPCRDTContext = @import("mcp_crdt_tools.zig").MCPCRDTContext;
pub const ReadCodeCRDTTool = @import("mcp_crdt_tools.zig").ReadCodeCRDTTool;
pub const WriteCodeCRDTTool = @import("mcp_crdt_tools.zig").WriteCodeCRDTTool;
pub const UpdateCursorTool = @import("mcp_crdt_tools.zig").UpdateCursorTool;
pub const GetCollaborativeContextTool = @import("mcp_crdt_tools.zig").GetCollaborativeContextTool;

// Export Enhanced Database components
pub const EnhancedDatabase = @import("enhanced_database.zig").EnhancedDatabase;
pub const EnhancedDatabaseConfig = @import("enhanced_database.zig").EnhancedDatabaseConfig;
pub const EnhancedFileResult = @import("enhanced_database.zig").EnhancedFileResult;
pub const EnhancedSearchQuery = @import("enhanced_database.zig").EnhancedSearchQuery;
pub const EnhancedSearchResult = @import("enhanced_database.zig").EnhancedSearchResult;
pub const DatabaseStats = @import("enhanced_database.zig").DatabaseStats;
pub const DatabaseMetrics = @import("enhanced_database.zig").DatabaseMetrics;

// Export Enhanced MCP Tools
pub const EnhancedMCPTools = @import("enhanced_mcp_tools.zig").EnhancedMCPTools;

// Export Enhanced MCP Server
pub const EnhancedMCPServer = @import("enhanced_mcp_server.zig").EnhancedMCPServer;

// Export Triple Hybrid Search components
pub const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
pub const TripleHybridQuery = @import("triple_hybrid_search.zig").HybridQuery;
pub const TripleHybridResult = @import("triple_hybrid_search.zig").TripleHybridResult;
pub const HybridSearchStats = @import("triple_hybrid_search.zig").HybridSearchStats;

// Export Primitive System components
pub const Primitive = @import("primitives.zig").Primitive;
pub const PrimitiveContext = @import("primitives.zig").PrimitiveContext;
pub const PrimitiveMetadata = @import("primitives.zig").PrimitiveMetadata;
pub const StorePrimitive = @import("primitives.zig").StorePrimitive;
pub const RetrievePrimitive = @import("primitives.zig").RetrievePrimitive;
pub const SearchPrimitive = @import("primitives.zig").SearchPrimitive;
pub const LinkPrimitive = @import("primitives.zig").LinkPrimitive;
pub const TransformPrimitive = @import("primitives.zig").TransformPrimitive;

// Export Primitive Engine components
pub const PrimitiveEngine = @import("primitive_engine.zig").PrimitiveEngine;
pub const PrimitiveEngineStats = @import("primitive_engine.zig").PrimitiveEngineStats;

// Export Primitive MCP Server components
pub const PrimitiveMCPServer = @import("mcp_primitive_server.zig").PrimitiveMCPServer;
pub const MCPPrimitiveDefinition = @import("mcp_primitive_server.zig").MCPPrimitiveDefinition;

// Re-export for convenience
pub const TemporalGraphDB = Database;

// Agrama CodeGraph Server - Main integration structure
pub const AgramaCodeGraphServer = struct {
    allocator: std.mem.Allocator,
    database: Database,
    mcp_server: MCPServer,
    websocket_server: WebSocketServer,
    agent_manager: AgentManager,
    event_broadcaster: EventBroadcaster,

    /// Initialize complete Agrama CodeGraph server
    pub fn init(allocator: std.mem.Allocator, websocket_port: u16) !AgramaCodeGraphServer {
        var database = Database.init(allocator);
        var websocket_server = WebSocketServer.init(allocator, websocket_port);
        var mcp_server = try MCPServer.init(allocator, &database);
        const agent_manager = AgentManager.init(allocator, &mcp_server, &websocket_server);
        const event_broadcaster = EventBroadcaster.init(allocator, &websocket_server);

        return AgramaCodeGraphServer{
            .allocator = allocator,
            .database = database,
            .mcp_server = mcp_server,
            .websocket_server = websocket_server,
            .agent_manager = agent_manager,
            .event_broadcaster = event_broadcaster,
        };
    }

    /// Start all server components
    pub fn start(self: *AgramaCodeGraphServer) !void {
        std.log.info("Starting Agrama CodeGraph Server...", .{});

        // Start WebSocket server
        try self.websocket_server.start();
        std.log.info("WebSocket server started on port {d}", .{self.websocket_server.port});

        // Add event callback for MCP server
        // Note: This is a simplified approach - production would need proper callback management

        std.log.info("Agrama CodeGraph Server started successfully", .{});
        std.log.info("Ready for AI agent connections via MCP", .{});
    }

    /// Stop all server components
    pub fn stop(self: *AgramaCodeGraphServer) void {
        std.log.info("Stopping Agrama CodeGraph Server...", .{});
        self.websocket_server.stop();
        std.log.info("Agrama CodeGraph Server stopped", .{});
    }

    /// Clean up all resources
    pub fn deinit(self: *AgramaCodeGraphServer) void {
        self.stop();
        self.agent_manager.deinit();
        self.mcp_server.deinit();
        self.websocket_server.deinit();
        self.database.deinit();
    }

    /// Handle MCP tool request from any agent
    pub fn handleMCPRequest(self: *AgramaCodeGraphServer, request: MCPRequest, agent_id: []const u8) !MCPResponse {
        return self.mcp_server.handleRequest(request, agent_id);
    }

    /// Register new AI agent
    pub fn registerAgent(self: *AgramaCodeGraphServer, agent_id: []const u8, agent_name: []const u8, capabilities: []const []const u8) !void {
        try self.agent_manager.registerAgent(agent_id, agent_name, capabilities);
    }

    /// Get comprehensive server statistics
    pub fn getServerStats(self: *AgramaCodeGraphServer) struct {
        mcp: struct { agents: u32, requests: u64, avg_response_ms: f64 },
        websocket: struct { active_connections: u32, total_messages_sent: u64 },
        agent_manager: struct { active_agents: u32, total_file_locks: u32, total_requests_handled: u64 },
    } {
        // MCP server stats not available in new implementation - using defaults
        const mcp_stats = struct { agents: u32, requests: u64, avg_response_ms: f64 }{
            .agents = 0,
            .requests = 0,
            .avg_response_ms = 0.0,
        };
        const ws_stats = self.websocket_server.getStats();
        const am_stats = self.agent_manager.getStats();

        return .{
            .mcp = .{
                .agents = mcp_stats.agents,
                .requests = mcp_stats.requests,
                .avg_response_ms = mcp_stats.avg_response_ms,
            },
            .websocket = .{
                .active_connections = ws_stats.active_connections,
                .total_messages_sent = ws_stats.total_messages_sent,
            },
            .agent_manager = .{
                .active_agents = am_stats.active_agents,
                .total_file_locks = am_stats.total_file_locks,
                .total_requests_handled = am_stats.total_requests_handled,
            },
        };
    }
};

test "Database module exports" {
    // Verify that our main exports are accessible
    const db_type_info = @typeInfo(Database);
    try testing.expect(db_type_info == .@"struct");

    const change_type_info = @typeInfo(Change);
    try testing.expect(change_type_info == .@"struct");
}

test "MCP Server module exports" {
    // Verify MCP server types are accessible
    const mcp_server_type_info = @typeInfo(MCPServer);
    try testing.expect(mcp_server_type_info == .@"struct");

    const mcp_request_type_info = @typeInfo(MCPRequest);
    try testing.expect(mcp_request_type_info == .@"struct");
}

test "AgramaCodeGraphServer initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try AgramaCodeGraphServer.init(allocator, 8080);
    defer server.deinit();

    const stats = server.getServerStats();
    try testing.expect(stats.mcp.agents == 0);
    try testing.expect(stats.websocket.active_connections == 0);
    try testing.expect(stats.agent_manager.active_agents == 0);
}

test "FRE module exports" {
    // Verify FRE types are accessible
    const fre_type_info = @typeInfo(FrontierReductionEngine);
    try testing.expect(fre_type_info == .@"struct");

    const node_type_info = @typeInfo(TemporalNode);
    try testing.expect(node_type_info == .@"struct");

    const edge_type_info = @typeInfo(TemporalEdge);
    try testing.expect(edge_type_info == .@"struct");

    // Test enum types
    const node_type_enum_info = @typeInfo(NodeType);
    try testing.expect(node_type_enum_info == .@"enum");

    const relation_type_enum_info = @typeInfo(RelationType);
    try testing.expect(relation_type_enum_info == .@"enum");
}

test "HNSW module exports" {
    // Verify HNSW types are accessible
    const hnsw_index_type_info = @typeInfo(HNSWIndex);
    try testing.expect(hnsw_index_type_info == .@"struct");

    const vector_type_info = @typeInfo(Vector);
    try testing.expect(vector_type_info == .@"struct");

    const matryoshka_type_info = @typeInfo(MatryoshkaEmbedding);
    try testing.expect(matryoshka_type_info == .@"struct");
}

test "SemanticDatabase module exports" {
    // Verify Semantic Database types are accessible
    const semantic_db_type_info = @typeInfo(SemanticDatabase);
    try testing.expect(semantic_db_type_info == .@"struct");

    const semantic_result_type_info = @typeInfo(SemanticSearchResult);
    try testing.expect(semantic_result_type_info == .@"struct");
}
