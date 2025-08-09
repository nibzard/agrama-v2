//! Agrama CodeGraph MCP Server - Main Entry Point
//! Provides the `agrama serve` command for starting the MCP server

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("agrama_v2_lib");

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

    if (std.mem.eql(u8, command, "serve")) {
        try serveCommand(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "mcp")) {
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
        \\Agrama CodeGraph MCP Server
        \\
        \\USAGE:
        \\    agrama [COMMAND] [OPTIONS]
        \\
        \\COMMANDS:
        \\    serve       Start the MCP server with WebSocket support (legacy)
        \\    mcp         Start MCP compliant server with stdio transport
        \\    test-db     Test database functionality
        \\    version     Show version information
        \\
        \\SERVE OPTIONS:
        \\    --port <PORT>     WebSocket server port (default: 8080)
        \\    --help           Show this help message
        \\
        \\EXAMPLES:
        \\    agrama serve                 # Start WebSocket server on default port 8080
        \\    agrama mcp                   # Start MCP compliant server (stdio transport)
        \\    agrama serve --port 9000     # Start WebSocket server on port 9000
        \\    agrama test-db               # Test database operations
        \\
    , .{});
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Agrama CodeGraph MCP Server v0.2.0-Phase2\n", .{});
}

fn serveCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var port: u16 = 8080;

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
                std.log.err("Invalid port number: {s} ({})", .{ args[i], err });
                std.process.exit(1);
            };
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
        std.log.err("Failed to initialize server: {}", .{err});
        std.process.exit(1);
    };
    defer server.deinit();

    // Register some example AI agents for demonstration
    try server.registerAgent("claude-code", "Claude Code", &[_][]const u8{ "read_code", "write_code", "get_context" });
    try server.registerAgent("cursor", "Cursor AI", &[_][]const u8{ "read_code", "write_code" });

    // Start the server
    server.start() catch |err| {
        std.log.err("Failed to start server: {}", .{err});
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
    // Parse MCP command arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(
                \\MCP Compliant Server
                \\
                \\Starts an MCP compliant server using stdio transport.
                \\This server follows the official Model Context Protocol specification.
                \\
                \\USAGE:
                \\    agrama mcp
                \\
                \\The server will read JSON-RPC messages from stdin and write responses to stdout.
                \\
                \\TOOLS AVAILABLE:
                \\    read_code    - Read file with optional history
                \\    write_code   - Write or modify files with provenance tracking  
                \\    get_context  - Get comprehensive contextual information
                \\
                \\EXAMPLE CLIENT USAGE:
                \\    echo 'JSON message' | agrama mcp
                \\
                );
            return;
        } else {
            std.log.err("Unknown mcp option: {s}", .{arg});
            std.process.exit(1);
        }
        i += 1;
    }

    std.log.info("Starting MCP Compliant Server (stdio transport)...", .{});

    // Initialize database
    var db = lib.Database.init(allocator);
    defer db.deinit();

    // Initialize MCP compliant server
    var mcp_server = lib.MCPCompliantServer.init(allocator, &db) catch |err| {
        std.log.err("Failed to initialize MCP server: {}", .{err});
        std.process.exit(1);
    };
    defer mcp_server.deinit();

    // Run the server (blocks until stdin closes)
    mcp_server.run() catch |err| {
        std.log.err("MCP server error: {}", .{err});
        std.process.exit(1);
    };

    std.log.info("MCP Compliant Server shutdown complete", .{});
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
    try db.saveFile("test/example.txt", "Hello, Agrama Database!");

    const content = try db.getFile("test/example.txt");
    if (!std.mem.eql(u8, content, "Hello, Agrama Database!")) {
        std.log.err("❌ Content mismatch", .{});
        return;
    }
    std.log.info("✅ File content matches", .{});

    // Test history functionality
    std.log.info("✅ Testing file history...", .{});
    try db.saveFile("test/example.txt", "Version 2");
    try db.saveFile("test/example.txt", "Version 3");

    const history = try db.getHistory("test/example.txt", 3);
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
    std.log.info("✅ Testing MCP Server integration...", .{});
    var mcp_server = lib.MCPServer.init(allocator, &db);
    defer mcp_server.deinit();

    try mcp_server.registerAgent("test-agent", "Test Agent");
    const stats = mcp_server.getStats();
    if (stats.agents != 1) {
        std.log.err("❌ Expected 1 agent, got {d}", .{stats.agents});
        return;
    }

    std.log.info("✅ MCP Server integration working", .{});

    std.log.info("🎉 All tests passed! Database is ready for AI agent collaboration.", .{});
}

test "MCP server integration test" {
    // Test that we can access and use the MCP server from main
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try lib.AgramaCodeGraphServer.init(allocator, 8080);
    defer server.deinit();

    // Test agent registration
    try server.registerAgent("test-agent", "Test Agent", &[_][]const u8{ "read_code", "write_code" });

    const stats = server.getServerStats();
    try std.testing.expect(stats.mcp.agents >= 1);
    try std.testing.expect(stats.websocket.active_connections == 0);
}

test "database integration from main" {
    // Test that we can access the database from main executable
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = lib.Database.init(allocator);
    defer db.deinit();

    // Simple test to verify the database works in main context
    try db.saveFile("main-test.txt", "Hello from main executable!");
    const content = try db.getFile("main-test.txt");
    try std.testing.expectEqualSlices(u8, "Hello from main executable!", content);
}
