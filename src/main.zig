//! Agrama CodeGraph MCP Server - Main Entry Point
//! Provides the `agrama serve` command for starting the MCP server

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("agrama_lib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "mcp")) {
        try mcpCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "test-db")) {
        try testDatabaseCommand(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        try printVersion();
    } else {
        std.log.err("Unknown command: {s}", .{command});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Agrama CodeGraph MCP Server - CONSOLIDATED PRIMITIVE ARCHITECTURE
        \\
        \\USAGE:
        \\    agrama [COMMAND] [OPTIONS]
        \\
        \\COMMANDS:
        \\    mcp         Start primitive-based MCP server (RECOMMENDED)
        \\    test-db     Test database functionality
        \\    version     Show version information
        \\
        \\MCP OPTIONS:
        \\    --dimensions <DIM>      HNSW vector dimensions (default: 768)
        \\    --no-semantic           Disable semantic database
        \\    --no-graph              Disable graph engine
        \\    --legacy                Use legacy enhanced MCP server (deprecated)
        \\    --help                  Show detailed MCP help
        \\
        \\PRIMITIVE-BASED ARCHITECTURE (DEFAULT):
        \\    The primitive-based server exposes 5 core operations
        \\    that enable composition and sub-1ms performance:
        \\
        \\    store       Universal storage with rich metadata and provenance
        \\    retrieve    Data access with history and context
        \\    search      Unified search (semantic/lexical/graph/temporal/hybrid)
        \\    link        Knowledge graph relationships with metadata
        \\    transform   Extensible operation registry for data transformation
        \\
        \\EXAMPLES:
        \\    agrama mcp                      # Start primitive server (recommended)
        \\    agrama mcp --dimensions 1024    # Custom embedding dimensions
        \\    agrama mcp --legacy             # Use legacy enhanced server
        \\    agrama test-db                  # Test database operations
        \\
        \\PERFORMANCE TARGETS:
        \\    Response Time:    <1ms P50 for primitive operations
        \\    Throughput:       1000+ primitive ops/second
        \\    Memory Usage:     Fixed allocation <10GB for 1M entities
        \\
    , .{});
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Agrama CodeGraph MCP Server v0.3.0-Primitive-Consolidated\n", .{});
}

fn serveCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var port: u16 = 8080;
    var enable_auth: bool = true;
    var dev_mode: bool = false;

    // Parse serve command arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 >= args.len) {
                std.log.err("--port requires a value", .{});
                std.process.exit(1);
            }
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch |err| {
                std.log.err("Invalid port number: {s} ({any})", .{ args[i], err });
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--no-auth")) {
            enable_auth = false;
        } else if (std.mem.eql(u8, arg, "--dev-mode")) {
            dev_mode = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage();
            return;
        } else {
            std.log.err("Unknown serve option: {s}", .{arg});
            try printUsage();
            std.process.exit(1);
        }
        i += 1;
    }

    std.log.info("Initializing Agrama CodeGraph Server on port {d}...", .{port});

    // Initialize the complete server
    var server = lib.AgramaCodeGraphServer.init(allocator, port) catch |err| {
        std.log.err("Failed to initialize server: {any}", .{err});
        std.process.exit(1);
    };
    defer server.deinit();

    // Register some example AI agents for demonstration
    try server.registerAgent("claude-code", "Claude Code", &[_][]const u8{ "read_code", "write_code", "get_context" });
    try server.registerAgent("cursor", "Cursor AI", &[_][]const u8{ "read_code", "write_code" });

    // Start the server
    server.start() catch |err| {
        std.log.err("Failed to start server: {any}", .{err});
        std.process.exit(1);
    };

    std.log.info("🚀 Agrama CodeGraph MCP Server is running!", .{});
    std.log.info("📊 WebSocket Observatory: ws://localhost:{d}", .{port});
    std.log.info("🤖 MCP Tools: read_code, write_code, get_context", .{});
    std.log.info("📈 Real-time agent collaboration enabled", .{});
    std.log.info("", .{});
    std.log.info("Press Ctrl+C to stop the server", .{});

    // Setup signal handling for graceful shutdown
    var signal_received = false;

    // Main server loop
    while (!signal_received) {
        // Perform periodic maintenance
        server.agent_manager.performMaintenance();
        server.websocket_server.cleanupConnections();

        // Print stats periodically
        const stats = server.getServerStats();
        std.log.debug("📊 Stats - MCP: {d} agents, {d} requests | WS: {d} connections | AM: {d} file locks", .{
            stats.mcp.agents,
            stats.mcp.requests,
            stats.websocket.active_connections,
            stats.agent_manager.total_file_locks,
        });

        // Sleep for 10 seconds between maintenance cycles
        std.time.sleep(10 * std.time.ns_per_s);

        // Check if we should shutdown (simple approach)
        // In production, would use proper signal handling
        if (checkShutdownSignal()) {
            signal_received = true;
        }
    }

    // Signal handlers would be restored here in production

    std.log.info("🛑 Shutting down Agrama CodeGraph Server...", .{});
    const final_stats = server.getServerStats();
    std.log.info("📊 Final Stats - Total Requests: {d}, Avg Response: {d:.2}ms", .{ final_stats.mcp.requests, final_stats.mcp.avg_response_ms });
}

fn mcpCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var hnsw_dimensions: u32 = 768;
    var enable_semantic = true;
    var enable_graph = true;
    var use_legacy = false;

    // Parse MCP command arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(
                \\Primitive-Based MCP Server (CONSOLIDATED ARCHITECTURE)
                \\
                \\MCP server exposing 5 core primitives instead of complex tools.
                \\Enables LLMs to compose their own memory architectures and analysis pipelines.
                \\
                \\USAGE:
                \\    agrama mcp [OPTIONS]
                \\
                \\OPTIONS:
                \\    --dimensions <DIM>      HNSW vector dimensions (default: 768)
                \\    --no-semantic           Disable semantic database
                \\    --no-graph              Disable graph engine
                \\    --legacy                Use legacy enhanced MCP server (deprecated)
                \\    --help                  Show this help message
                \\
                \\CORE PRIMITIVES (Default Mode):
                \\    store                   Universal storage with rich metadata and provenance
                \\    retrieve                Data access with history and context
                \\    search                  Unified search (semantic/lexical/graph/temporal/hybrid)
                \\    link                    Knowledge graph relationships with metadata
                \\    transform               Extensible operation registry for data transformation
                \\
                \\PERFORMANCE TARGETS:
                \\    Response Time:          <1ms P50 latency for primitive operations
                \\    Throughput:             1000+ primitive ops/second
                \\    Memory Usage:           Fixed allocation <10GB for 1M entities
                \\    Storage Efficiency:     5× reduction through anchor+delta compression
                \\
                \\EXAMPLE USAGE:
                \\    agrama mcp                      # Start with full primitive capabilities (recommended)
                \\    agrama mcp --dimensions 1024    # Custom embedding dimensions
                \\    agrama mcp --legacy             # Use deprecated enhanced server
                \\
            );
            return;
        } else if (std.mem.eql(u8, arg, "--dimensions")) {
            if (i + 1 >= args.len) {
                std.log.err("--dimensions requires a value", .{});
                std.process.exit(1);
            }
            i += 1;
            hnsw_dimensions = std.fmt.parseInt(u32, args[i], 10) catch |err| {
                std.log.err("Invalid dimensions: {s} ({any})", .{ args[i], err });
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--no-semantic")) {
            enable_semantic = false;
        } else if (std.mem.eql(u8, arg, "--no-graph")) {
            enable_graph = false;
        } else if (std.mem.eql(u8, arg, "--legacy")) {
            use_legacy = true;
        } else {
            std.log.err("Unknown mcp option: {s}", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    // MCP stdio transport: stdout is reserved for JSON-RPC protocol only
    // Suppressing all non-error startup messages for MCP compliance

    if (use_legacy) {
        std.log.warn("Using deprecated legacy enhanced server. Consider migrating to primitive architecture.", .{});
        try runLegacyEnhancedServer(allocator, hnsw_dimensions);
    } else {
        // DEFAULT: Use primitive-based server (recommended)
        try runPrimitiveServer(allocator, hnsw_dimensions, enable_semantic, enable_graph);
    }

    // MCP stdio transport: no shutdown logging to maintain protocol compliance
}

fn runPrimitiveServer(allocator: std.mem.Allocator, hnsw_dimensions: u32, enable_semantic: bool, enable_graph: bool) !void {
    // Initialize database
    var database = lib.Database.init(allocator);
    defer database.deinit();

    // Initialize semantic database if enabled
    var semantic_db_instance: ?lib.SemanticDatabase = null;
    var semantic_db: ?*lib.SemanticDatabase = null;
    if (enable_semantic) {
        const semantic_config = lib.SemanticDatabase.HNSWConfig{
            .vector_dimensions = hnsw_dimensions,
            .max_connections = 16,
            .ef_construction = 200,
            .matryoshka_dims = &[_]u32{ 64, 256, 768, 1024 },
        };

        semantic_db_instance = lib.SemanticDatabase.init(allocator, semantic_config) catch |err| {
            std.log.err("Failed to initialize semantic database: {any}", .{err});
            std.process.exit(1);
        };
        semantic_db = &semantic_db_instance.?;
    } else {
        // Create minimal semantic database instance for interface compatibility
        semantic_db_instance = lib.SemanticDatabase.init(allocator, .{}) catch |err| {
            std.log.err("Failed to initialize minimal semantic database: {any}", .{err});
            std.process.exit(1);
        };
        semantic_db = &semantic_db_instance.?;
    }
    defer if (semantic_db_instance) |*sdb| sdb.deinit();

    // Initialize graph engine if enabled
    var graph_engine_instance: ?lib.TripleHybridSearchEngine = null;
    var graph_engine: ?*lib.TripleHybridSearchEngine = null;
    if (enable_graph) {
        graph_engine_instance = lib.TripleHybridSearchEngine.init(allocator);
        graph_engine = &graph_engine_instance.?;
    } else {
        // Create minimal graph engine instance for interface compatibility
        graph_engine_instance = lib.TripleHybridSearchEngine.init(allocator);
        graph_engine = &graph_engine_instance.?;
    }
    defer if (graph_engine_instance) |*ge| ge.deinit();

    // Initialize primitive MCP server
    var primitive_server = lib.PrimitiveMCPServer.init(allocator, &database, semantic_db.?, graph_engine.?) catch |err| {
        std.log.err("Failed to initialize Primitive MCP server: {any}", .{err});
        std.process.exit(1);
    };
    defer primitive_server.deinit();

    // Run the primitive server (blocks until stdin closes)
    primitive_server.run() catch |err| {
        std.log.err("Primitive MCP server error: {any}", .{err});
        std.process.exit(1);
    };
}

fn runLegacyEnhancedServer(allocator: std.mem.Allocator, hnsw_dimensions: u32) !void {
    _ = allocator;
    _ = hnsw_dimensions;
    // Legacy enhanced server moved to archive - use 'mcp' command instead
    std.log.err("Enhanced server moved to archive. Use 'agrama mcp' for MCP primitive server.", .{});
    std.process.exit(1);
}

fn primitiveCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var hnsw_dimensions: u32 = 768;
    var enable_semantic = true;
    var enable_graph = true;

    // Parse primitive command arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(
                \\Primitive-Based MCP Server
                \\
                \\MCP server exposing 5 core primitives instead of complex tools.
                \\Enables LLMs to compose their own memory architectures and analysis pipelines.
                \\
                \\USAGE:
                \\    agrama primitive [OPTIONS]
                \\
                \\OPTIONS:
                \\    --dimensions <DIM>      HNSW vector dimensions (default: 768)
                \\    --no-semantic           Disable semantic database
                \\    --no-graph              Disable graph engine
                \\    --help                  Show this help message
                \\
                \\CORE PRIMITIVES:
                \\    store                   Universal storage with rich metadata and provenance
                \\    retrieve                Data access with history and context
                \\    search                  Unified search (semantic/lexical/graph/temporal/hybrid)
                \\    link                    Knowledge graph relationships with metadata
                \\    transform               Extensible operation registry for data transformation
                \\
                \\PERFORMANCE TARGETS:
                \\    Response Time:          <1ms P50 latency for primitive operations
                \\    Throughput:             1000+ primitive ops/second
                \\    Memory Usage:           Fixed allocation <10GB for 1M entities
                \\    Storage Efficiency:     5× reduction through anchor+delta compression
                \\
                \\COMPOSITION EXAMPLES:
                \\    # Store concept with metadata
                \\    store('concept_v1', idea_text, {'confidence': 0.7, 'source': 'brainstorm'})
                \\
                \\    # Retrieve with history
                \\    retrieve('concept_v1', {'include_history': true})
                \\
                \\    # Hybrid search across all indices
                \\    search('authentication code', 'hybrid', {'weights': {'semantic': 0.6, 'lexical': 0.4}})
                \\
                \\    # Create knowledge graph relationships
                \\    link('module_a', 'module_b', 'depends_on', {'strength': 0.8})
                \\
                \\    # Transform data with extensible operations
                \\    transform('parse_functions', code_content, {'language': 'zig'})
                \\
                \\EXAMPLE USAGE:
                \\    agrama primitive                    # Start with full capabilities (recommended)
                \\    agrama primitive --dimensions 1024  # Custom embedding dimensions
                \\    agrama primitive --no-graph         # Disable graph features for basic usage
                \\
            );
            return;
        } else if (std.mem.eql(u8, arg, "--dimensions")) {
            if (i + 1 >= args.len) {
                std.log.err("--dimensions requires a value", .{});
                std.process.exit(1);
            }
            i += 1;
            hnsw_dimensions = std.fmt.parseInt(u32, args[i], 10) catch |err| {
                std.log.err("Invalid dimensions: {s} ({any})", .{ args[i], err });
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--no-semantic")) {
            enable_semantic = false;
        } else if (std.mem.eql(u8, arg, "--no-graph")) {
            enable_graph = false;
        } else {
            std.log.err("Unknown primitive option: {s}", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    // MCP stdio transport: stdout is reserved for JSON-RPC protocol only
    // Suppressing all non-error startup messages for MCP compliance

    // Initialize database
    var database = lib.Database.init(allocator);
    defer database.deinit();

    // Initialize semantic database if enabled
    var semantic_db_instance: ?lib.SemanticDatabase = null;
    var semantic_db: ?*lib.SemanticDatabase = null;
    if (enable_semantic) {
        const semantic_config = lib.SemanticDatabase.HNSWConfig{
            .vector_dimensions = hnsw_dimensions,
            .max_connections = 16,
            .ef_construction = 200,
            .matryoshka_dims = &[_]u32{ 64, 256, 768, 1024 },
        };

        semantic_db_instance = lib.SemanticDatabase.init(allocator, semantic_config) catch |err| {
            std.log.err("Failed to initialize semantic database: {any}", .{err});
            std.process.exit(1);
        };
        semantic_db = &semantic_db_instance.?;
    } else {
        // Create minimal semantic database instance for interface compatibility
        semantic_db_instance = lib.SemanticDatabase.init(allocator, .{}) catch |err| {
            std.log.err("Failed to initialize minimal semantic database: {any}", .{err});
            std.process.exit(1);
        };
        semantic_db = &semantic_db_instance.?;
    }
    defer if (semantic_db_instance) |*sdb| sdb.deinit();

    // Initialize graph engine if enabled
    var graph_engine_instance: ?lib.TripleHybridSearchEngine = null;
    var graph_engine: ?*lib.TripleHybridSearchEngine = null;
    if (enable_graph) {
        graph_engine_instance = lib.TripleHybridSearchEngine.init(allocator);
        graph_engine = &graph_engine_instance.?;
    } else {
        // Create minimal graph engine instance for interface compatibility
        graph_engine_instance = lib.TripleHybridSearchEngine.init(allocator);
        graph_engine = &graph_engine_instance.?;
    }
    defer if (graph_engine_instance) |*ge| ge.deinit();

    // Initialize primitive MCP server
    var primitive_server = lib.PrimitiveMCPServer.init(allocator, &database, semantic_db.?, graph_engine.?) catch |err| {
        std.log.err("Failed to initialize Primitive MCP server: {any}", .{err});
        std.process.exit(1);
    };
    defer primitive_server.deinit();

    // Run the primitive server (blocks until stdin closes)
    primitive_server.run() catch |err| {
        std.log.err("Primitive MCP server error: {any}", .{err});
        std.process.exit(1);
    };

    // MCP stdio transport: no shutdown logging to maintain protocol compliance
}

fn checkShutdownSignal() bool {
    // In production, this would check for actual signal handling
    // For now, we'll rely on manual termination
    return false;
}

fn testDatabaseCommand(allocator: std.mem.Allocator) !void {
    std.log.info("Testing Agrama Database functionality...", .{});

    var db = lib.Database.init(allocator);
    defer db.deinit();

    // Test basic file operations
    std.log.info("✅ Testing file save/load...", .{});
    try db.saveFile("tests/example.txt", "Hello, Agrama Database!");

    const content = try db.getFile("tests/example.txt");
    if (!std.mem.eql(u8, content, "Hello, Agrama Database!")) {
        std.log.err("❌ Content mismatch", .{});
        return;
    }
    std.log.info("✅ File content matches", .{});

    // Test history functionality
    std.log.info("✅ Testing file history...", .{});
    try db.saveFile("tests/example.txt", "Version 2");
    try db.saveFile("tests/example.txt", "Version 3");

    const history = try db.getHistory("tests/example.txt", 3);
    defer allocator.free(history);

    if (history.len != 3) {
        std.log.err("❌ Expected 3 history entries, got {d}", .{history.len});
        return;
    }

    // History should be in reverse chronological order
    if (!std.mem.eql(u8, history[0].content, "Version 3")) {
        std.log.err("❌ Latest version mismatch", .{});
        return;
    }

    std.log.info("✅ History tracking works correctly", .{});

    // Test MCP server integration
    std.log.info("✅ Testing MCP Server initialization...", .{});
    
    // Initialize required components for MCP server
    const hnsw_config = lib.SemanticDatabase.HNSWConfig{
        .vector_dimensions = 768,
        .max_connections = 16,
        .ef_construction = 200,
    };
    var semantic_db = try lib.SemanticDatabase.init(allocator, hnsw_config);
    defer semantic_db.deinit();
    
    var graph_engine = lib.TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var mcp_server = try lib.MCPPrimitiveServer.init(allocator, &db, &semantic_db, &graph_engine);
    defer mcp_server.deinit();

    std.log.info("✅ MCP Server initialized successfully", .{});

    std.log.info("🎉 All tests passed! Database is ready for AI agent collaboration.", .{});
}

// RE-ENABLED: Memory corruption issue FIXED in AgentManager
test "MCP server integration test - MEMORY FIXED" {
    // Test that we can access and use the MCP server from main
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in MCP server integration test", .{});
        }
    }
    const base_allocator = gpa.allocator();

    // Use arena allocator for the entire test to handle complex memory ownership
    var test_arena = std.heap.ArenaAllocator.init(base_allocator);
    defer test_arena.deinit();
    const allocator = test_arena.allocator();

    var server = try lib.AgramaServer.init(allocator, .{
        .enable_mcp = true,
        .enable_websocket = true,
        .websocket_port = 8080,
    });
    defer server.deinit();

    // Test participant registration with owned strings
    const test_participant_id = try allocator.dupe(u8, "test-agent");
    defer allocator.free(test_participant_id);

    try server.registerParticipant(test_participant_id, .AIAgent, .MCP);

    const stats = server.getStats();
    try std.testing.expect(stats.core.active_participants == 1);
}

test "database integration from main" {
    // Test that we can access the database from main executable
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in database integration test", .{});
        }
    }
    const allocator = gpa.allocator();

    var db = lib.Database.init(allocator);
    defer db.deinit();

    // Simple test to verify the database works in main context
    try db.saveFile("main-test.txt", "Hello from main executable!");
    const content = try db.getFile("main-test.txt");
    try std.testing.expectEqualSlices(u8, "Hello from main executable!", content);
}
