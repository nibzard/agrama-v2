//! Agrama Server - Core Temporal Knowledge Graph System
//!
//! This is the main server for Agrama, a temporal knowledge graph database designed
//! for AI-human collaboration. The server provides the core functionality and can
//! expose multiple interfaces for different types of clients.
//!
//! Core Components:
//! - Temporal Database: Track changes over time with anchor+delta compression
//! - Semantic Search: HNSW-based vector search with multi-scale embeddings
//! - Graph Engine: FRE-powered graph traversal with O(m log^(2/3) n) complexity
//! - Orchestration: Coordinate multiple participants (humans and AI agents)
//!
//! Available Interfaces:
//! - MCP: Model Context Protocol for AI agents (Claude, etc.)
//! - WebSocket: Real-time event streaming for Observatory clients
//! - HTTP REST: (planned) Traditional REST API
//! - gRPC: (planned) High-performance RPC interface
//!
//! The server architecture clearly separates core functionality from interface
//! protocols, making it easy to add new ways to interact with Agrama.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Core Agrama components
const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
const OrchestrationContext = @import("orchestration_context.zig").OrchestrationContext;
const PrimitiveEngine = @import("primitive_engine.zig").PrimitiveEngine;

// Interface adapters
const MCPInterface = @import("interfaces/mcp/mcp_interface.zig").MCPInterface;
const WebSocketInterface = @import("interfaces/websocket/websocket_interface.zig").WebSocketInterface;

/// Core Agrama Server with multiple interface support
pub const AgramaServer = struct {
    allocator: Allocator,

    /// Core components - the heart of Agrama
    core: struct {
        database: Database,
        semantic_db: SemanticDatabase,
        graph_engine: TripleHybridSearchEngine,
        primitive_engine: PrimitiveEngine,
        orchestration: OrchestrationContext,
    },

    /// Available interfaces - different ways to interact with Agrama
    interfaces: struct {
        mcp: ?MCPInterface,
        websocket: ?WebSocketInterface,
        // Future interfaces can be added here:
        // http_rest: ?HTTPInterface,
        // grpc: ?GRPCInterface,
    },

    /// Server configuration
    config: ServerConfig,

    /// Server statistics
    stats: InternalStats,

    pub const ServerConfig = struct {
        /// Enable MCP interface for AI agents
        enable_mcp: bool = true,

        /// Enable WebSocket interface for real-time clients
        enable_websocket: bool = true,
        websocket_port: u16 = 8080,

        /// Semantic database configuration
        hnsw_dimensions: u32 = 768,
        hnsw_max_connections: u32 = 16,
        hnsw_ef_construction: u32 = 200,

        /// Performance tuning
        use_memory_pools: bool = true,
        max_concurrent_participants: u32 = 100,
    };

    pub const ServerStats = struct {
        uptime_seconds: i64,
        total_operations: u64,
        core: struct {
            database_files: u32,
            semantic_vectors: u32,
            graph_nodes: u32,
            active_participants: u32,
        },
        interfaces: struct {
            mcp: ?MCPInterfaceStats,
            websocket: ?WebSocketInterfaceStats,
        },
    };

    const MCPInterfaceStats = struct {
        enabled: bool,
        requests_handled: u64,
        avg_response_ms: f64,
    };

    const WebSocketInterfaceStats = struct {
        enabled: bool,
        port: u16,
        active_connections: u32,
        events_broadcast: u64,
    };

    const InternalStats = struct {
        start_time: i64,
        total_operations: u64 = 0,

        pub fn getUptimeSeconds(self: InternalStats) i64 {
            return std.time.timestamp() - self.start_time;
        }
    };

    /// Initialize the Agrama server with specified configuration
    pub fn init(allocator: Allocator, config: ServerConfig) !AgramaServer {
        std.log.info("Initializing Agrama Server - Temporal Knowledge Graph System", .{});

        // Initialize core components
        var database = Database.init(allocator);

        const hnsw_config = SemanticDatabase.HNSWConfig{
            .vector_dimensions = config.hnsw_dimensions,
            .max_connections = config.hnsw_max_connections,
            .ef_construction = config.hnsw_ef_construction,
        };
        var semantic_db = try SemanticDatabase.init(allocator, hnsw_config);
        var graph_engine = TripleHybridSearchEngine.init(allocator);
        const primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
        var orchestration = OrchestrationContext.init(allocator);

        // Initialize interfaces (optional based on config)
        var mcp_interface: ?MCPInterface = null;
        if (config.enable_mcp) {
            mcp_interface = try MCPInterface.init(
                allocator,
                &database,
                &semantic_db,
                &graph_engine,
                &orchestration,
            );
            std.log.info("MCP interface initialized (Model Context Protocol for AI agents)", .{});
        }

        var websocket_interface: ?WebSocketInterface = null;
        if (config.enable_websocket) {
            websocket_interface = WebSocketInterface.init(
                allocator,
                &database,
                &orchestration,
                config.websocket_port,
            );
            std.log.info("WebSocket interface initialized (Real-time event streaming)", .{});
        }

        return AgramaServer{
            .allocator = allocator,
            .core = .{
                .database = database,
                .semantic_db = semantic_db,
                .graph_engine = graph_engine,
                .primitive_engine = primitive_engine,
                .orchestration = orchestration,
            },
            .interfaces = .{
                .mcp = mcp_interface,
                .websocket = websocket_interface,
            },
            .config = config,
            .stats = InternalStats{
                .start_time = std.time.timestamp(),
            },
        };
    }

    /// Clean up all server resources
    pub fn deinit(self: *AgramaServer) void {
        std.log.info("Shutting down Agrama Server...", .{});

        // Clean up interfaces
        if (self.interfaces.mcp) |*mcp| {
            mcp.deinit();
        }
        if (self.interfaces.websocket) |*ws| {
            ws.deinit();
        }

        // Clean up core components
        self.core.primitive_engine.deinit();
        self.core.orchestration.deinit();
        self.core.graph_engine.deinit();
        self.core.semantic_db.deinit();
        self.core.database.deinit();

        std.log.info("Agrama Server shutdown complete", .{});
    }

    /// Start the server with enabled interfaces
    pub fn start(self: *AgramaServer) !void {
        std.log.info("Starting Agrama Server...", .{});

        // Enable configured interfaces
        if (self.interfaces.mcp) |*mcp| {
            try mcp.enable();
        }

        if (self.interfaces.websocket) |*ws| {
            try ws.enable();
        }

        const uptime = self.stats.getUptimeSeconds();
        std.log.info("Agrama Server started successfully (uptime: {d}s)", .{uptime});

        // If MCP is enabled and we're in MCP mode, start the blocking MCP server
        if (self.interfaces.mcp) |*mcp| {
            if (self.config.enable_mcp and !self.config.enable_websocket) {
                // MCP-only mode - start blocking server
                try mcp.start();
            }
        }
    }

    /// Stop all server interfaces
    pub fn stop(self: *AgramaServer) void {
        std.log.info("Stopping Agrama Server interfaces...", .{});

        if (self.interfaces.mcp) |*mcp| {
            mcp.disable();
        }

        if (self.interfaces.websocket) |*ws| {
            ws.disable();
        }
    }

    /// Execute a primitive operation directly (bypassing interfaces)
    pub fn executePrimitive(self: *AgramaServer, primitive_name: []const u8, params: std.json.Value, participant_id: []const u8) !std.json.Value {
        self.stats.total_operations += 1;
        self.core.orchestration.recordContribution(participant_id);
        return self.core.primitive_engine.executePrimitive(primitive_name, params, participant_id);
    }

    /// Register a participant in the orchestration system
    pub fn registerParticipant(self: *AgramaServer, id: []const u8, participant_type: @import("orchestration_context.zig").ParticipantType, connection: @import("orchestration_context.zig").ConnectionType) !void {
        try self.core.orchestration.addParticipant(id, participant_type, connection);

        // Broadcast to WebSocket clients if enabled
        if (self.interfaces.websocket) |*ws| {
            const event_type = if (participant_type == .Human) "participant_joined" else "agent_joined";
            try ws.broadcastParticipantActivity(id, event_type, "Joined the collaborative session");
        }
    }

    /// Get comprehensive server statistics
    pub fn getStats(self: *AgramaServer) ServerStats {
        const orch_stats = self.core.orchestration.getStats();

        var mcp_stats: ?MCPInterfaceStats = null;
        if (self.interfaces.mcp) |*mcp| {
            const stats = mcp.getStats();
            mcp_stats = .{
                .enabled = stats.enabled,
                .requests_handled = stats.requests_handled,
                .avg_response_ms = stats.avg_response_ms,
            };
        }

        var ws_stats: ?WebSocketInterfaceStats = null;
        if (self.interfaces.websocket) |*ws| {
            const stats = ws.getStats();
            ws_stats = .{
                .enabled = stats.enabled,
                .port = stats.port,
                .active_connections = stats.active_connections,
                .events_broadcast = stats.total_events_broadcast,
            };
        }

        return .{
            .uptime_seconds = self.stats.getUptimeSeconds(),
            .total_operations = self.stats.total_operations,
            .core = .{
                .database_files = 0, // TODO: Get from database
                .semantic_vectors = 0, // TODO: Get from semantic_db
                .graph_nodes = 0, // TODO: Get from graph_engine
                .active_participants = orch_stats.active_participants,
            },
            .interfaces = .{
                .mcp = mcp_stats,
                .websocket = ws_stats,
            },
        };
    }

    /// Get server description and capabilities
    pub fn getDescription() []const u8 {
        return 
        \\Agrama Server - Temporal Knowledge Graph System
        \\
        \\Core Capabilities:
        \\- Temporal database with anchor+delta compression
        \\- Semantic search with HNSW vector indices
        \\- Graph traversal with FRE algorithm
        \\- Multi-participant orchestration
        \\- 5 core primitives: store, retrieve, search, link, transform
        \\
        \\Available Interfaces:
        \\- MCP: AI agent protocol (Claude, etc.)
        \\- WebSocket: Real-time event streaming
        \\- HTTP REST: Traditional API (planned)
        \\- gRPC: High-performance RPC (planned)
        \\
        \\Performance Targets:
        \\- <1ms P50 latency for primitives
        \\- 1000+ ops/second throughput
        \\- <10GB memory for 1M entities
        ;
    }
};
