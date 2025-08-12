//! Agrama - Temporal Knowledge Graph Database
//!
//! A powerful temporal knowledge graph system with multiple interface options.
//! At its core, Agrama provides temporal data storage, semantic search, and
//! advanced graph algorithms. Various interfaces (MCP, WebSocket, etc.) allow
//! different types of clients to interact with the system.
//!
//! See ARCHITECTURE.md for detailed system design and interface documentation.

const std = @import("std");
const testing = std.testing;

// ============================================================================
// CORE AGRAMA SYSTEM
// These are the fundamental components that power Agrama
// ============================================================================

// Core Database - Temporal storage with anchor+delta compression
pub const Database = @import("database.zig").Database;
pub const Change = @import("database.zig").Change;

// Semantic Search - HNSW vector indices for O(log n) search
pub const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;

// Graph Engine - Triple hybrid search with FRE traversal
pub const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;

// Primitive Engine - 5 core operations all interfaces use
pub const PrimitiveEngine = @import("primitive_engine.zig").PrimitiveEngine;
pub const primitives = @import("primitives.zig");

// Orchestration - Manage participants (humans and AI agents)
pub const OrchestrationContext = @import("orchestration_context.zig").OrchestrationContext;
pub const Participant = @import("orchestration_context.zig").Participant;
pub const ParticipantType = @import("orchestration_context.zig").ParticipantType;
pub const ConnectionType = @import("orchestration_context.zig").ConnectionType;
pub const CollaborativeEvent = @import("orchestration_context.zig").CollaborativeEvent;

// ============================================================================
// MAIN SERVER
// The orchestrator that brings everything together
// ============================================================================

// Main Agrama Server
pub const AgramaServer = @import("agrama_server.zig").AgramaServer;

// ============================================================================
// INTERFACE ADAPTERS
// Different ways to interact with Agrama - MCP is just one option!
// ============================================================================

pub const interfaces = struct {
    // MCP Interface - For AI agents like Claude
    pub const MCP = struct {
        pub const Interface = @import("interfaces/mcp/mcp_interface.zig").MCPInterface;
        
        // Protocol implementation details (usually not needed directly)
        pub const PrimitiveMCPServer = @import("mcp_primitive_server.zig").PrimitiveMCPServer;
        pub const Request = @import("mcp_primitive_server.zig").MCPRequest;
        pub const Response = @import("mcp_primitive_server.zig").MCPResponse;
        pub const ToolDefinition = @import("mcp_primitive_server.zig").MCPToolDefinition;
        pub const Content = @import("mcp_primitive_server.zig").MCPContent;
        pub const ToolResponse = @import("mcp_primitive_server.zig").MCPToolResponse;
    };
    
    // WebSocket Interface - For real-time web clients
    pub const WebSocket = struct {
        pub const Interface = @import("interfaces/websocket/websocket_interface.zig").WebSocketInterface;
        
        // Protocol implementation details
        pub const Server = @import("websocket.zig").WebSocketServer;
        pub const Connection = @import("websocket.zig").WebSocketConnection;
        pub const EventBroadcaster = @import("websocket.zig").EventBroadcaster;
    };
    
    // Future interfaces will be added here:
    // pub const HTTP = struct { ... };
    // pub const gRPC = struct { ... };
};


// Export Frontier Reduction Engine components (using paper-compliant implementation)
pub const TrueFrontierReductionEngine = @import("fre_true.zig").TrueFrontierReductionEngine;
pub const FREPathResult = @import("fre_true.zig").PathResult;
pub const FREWeight = @import("fre_true.zig").Weight;
pub const FREEdge = @import("fre_true.zig").Edge;

// Compatibility aliases for transition period
pub const FrontierReductionEngine = TrueFrontierReductionEngine;

// Simple compatibility types for gradual migration
pub const TraversalDirection = enum {
    forward,
    reverse, 
    bidirectional,
};

// Export HNSW components
pub const HNSWIndex = @import("hnsw.zig").HNSWIndex;
pub const Vector = @import("hnsw.zig").Vector;
pub const MatryoshkaEmbedding = @import("hnsw.zig").MatryoshkaEmbedding;
pub const SearchResult = @import("hnsw.zig").SearchResult;
pub const HNSWSearchParams = @import("hnsw.zig").HNSWSearchParams;
pub const NodeID = @import("hnsw.zig").NodeID;

// Export Semantic Database components (additional types)
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

// Enhanced components moved to archive - using primitives instead

// Export Triple Hybrid Search components (additional types)
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

// Export PrimitiveMCPServer at top level for backward compatibility
pub const PrimitiveMCPServer = @import("mcp_primitive_server.zig").PrimitiveMCPServer;

// Export Primitive Engine components (additional types)
pub const PrimitiveEngineStats = @import("primitive_engine.zig").PrimitiveEngineStats;


// Re-export for convenience
pub const TemporalGraphDB = Database;


test "Database module exports" {
    // Verify that our main exports are accessible
    const db_type_info = @typeInfo(Database);
    try testing.expect(db_type_info == .@"struct");

    const change_type_info = @typeInfo(Change);
    try testing.expect(change_type_info == .@"struct");
}

test "Interface exports" {
    // Verify MCP interface types are accessible
    const mcp_interface_type_info = @typeInfo(interfaces.MCP.Interface);
    try testing.expect(mcp_interface_type_info == .@"struct");

    const mcp_request_type_info = @typeInfo(interfaces.MCP.Request);
    try testing.expect(mcp_request_type_info == .@"struct");
    
    // Verify WebSocket interface types are accessible
    const ws_interface_type_info = @typeInfo(interfaces.WebSocket.Interface);
    try testing.expect(ws_interface_type_info == .@"struct");
}

test "AgramaServer initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try AgramaServer.init(allocator, .{
        .enable_mcp = true,
        .enable_websocket = true,
        .websocket_port = 8080,
    });
    defer server.deinit();

    const stats = server.getStats();
    try testing.expect(stats.total_operations == 0);
    try testing.expect(stats.core.active_participants == 0);
}

test "FRE module exports" {
    // Verify FRE types are accessible
    const fre_type_info = @typeInfo(FrontierReductionEngine);
    try testing.expect(fre_type_info == .@"struct");

    // TemporalNode moved to archive - test removed

    // TemporalEdge also moved to archive

    // NodeType also moved to archive

    // RelationType also moved to archive
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
