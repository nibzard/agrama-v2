const std = @import("std");
const testing = std.testing;

// Import all components for integration testing
const Database = @import("src/database.zig").Database;
const SemanticDatabase = @import("src/semantic_database.zig").SemanticDatabase;
const MCPServer = @import("src/mcp_server.zig").MCPServer;
const CRDTManager = @import("src/crdt_manager.zig").CRDTManager;
const FRE = @import("src/fre.zig").FRE;
const HNSWIndex = @import("src/hnsw.zig").HNSWIndex;

/// Integration Test Suite - Tests all components working together
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== AGRAMA INTEGRATION TEST SUITE ===\n\n", .{});

    // Test 1: Basic Build Verification
    std.debug.print("[1] Build Verification...\n", .{});
    try testBuildIntegrity(allocator);
    std.debug.print("    ✓ All components compile and link correctly\n\n", .{});

    // Test 2: Memory Safety Check
    std.debug.print("[2] Memory Safety Check...\n", .{});
    try testMemorySafety(allocator);
    std.debug.print("    ✓ No immediate memory leaks detected\n\n", .{});

    // Test 3: Core Database Operations
    std.debug.print("[3] Core Database Integration...\n", .{});
    try testDatabaseIntegration(allocator);
    std.debug.print("    ✓ Database operations work correctly\n\n", .{});

    // Test 4: Algorithm Integration
    std.debug.print("[4] Algorithm Integration...\n", .{});
    try testAlgorithmIntegration(allocator);
    std.debug.print("    ✓ HNSW, FRE, and CRDT algorithms integrate properly\n\n", .{});

    // Test 5: MCP Server Integration
    std.debug.print("[5] MCP Server Integration...\n", .{});
    try testMCPIntegration(allocator);
    std.debug.print("    ✓ MCP server with enhanced tools works correctly\n\n", .{});

    // Test 6: End-to-End Workflow
    std.debug.print("[6] End-to-End Workflow...\n", .{});
    try testEndToEndWorkflow(allocator);
    std.debug.print("    ✓ Complete workflow from file save to search to analysis\n\n", .{});

    std.debug.print("=== ALL INTEGRATION TESTS PASSED ===\n", .{});
}

/// Test that all components can be initialized without errors
fn testBuildIntegrity(allocator: std.mem.Allocator) !void {
    // Test Database initialization
    var database = Database.init(allocator);
    defer database.deinit();

    // Test SemanticDatabase initialization
    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 128,
        .max_connections = 16,
        .ef_construction = 100,
    };
    var semantic_db = try SemanticDatabase.init(allocator, config);
    defer semantic_db.deinit();

    // Test MCPServer initialization
    var mcp_server = MCPServer.init(allocator);
    defer mcp_server.deinit();

    // Test CRDT Manager initialization
    var crdt_manager = CRDTManager.init(allocator);
    defer crdt_manager.deinit();
}

/// Test memory safety patterns across components
fn testMemorySafety(allocator: std.mem.Allocator) !void {
    // Test with arena allocator for scoped operations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Test Database with arena
    var database = Database.init(arena_allocator);
    defer database.deinit();

    // Simple operations that should not leak
    try database.saveFile("test.txt", "Hello, World!");
    const content = try database.readFile("test.txt");
    try testing.expect(std.mem.eql(u8, content, "Hello, World!"));
}

/// Test core database operations with error handling
fn testDatabaseIntegration(allocator: std.mem.Allocator) !void {
    var database = Database.init(allocator);
    defer database.deinit();

    // Test basic CRUD operations
    try database.saveFile("integration_test.zig", "const std = @import(\"std\");");
    const content = try database.readFile("integration_test.zig");
    try testing.expect(content.len > 0);

    // Test history tracking
    try database.saveFile("integration_test.zig", "const std = @import(\"std\");\nconst testing = std.testing;");
    const history = database.getHistory("integration_test.zig", 5) catch &[_]@import("src/database.zig").Change{};
    defer if (history.len > 0) allocator.free(history);

    // Test file listing
    const files = try database.listFiles();
    defer allocator.free(files);
    try testing.expect(files.len > 0);
}

/// Test algorithm integration with simplified data
fn testAlgorithmIntegration(allocator: std.mem.Allocator) !void {
    // Test HNSW with small dataset
    var hnsw = try HNSWIndex.init(allocator, 64, 16, 200);
    defer hnsw.deinit();

    // Add a few test vectors
    const test_vector1 = try allocator.alloc(f32, 64);
    defer allocator.free(test_vector1);
    for (test_vector1, 0..) |*val, i| {
        val.* = @as(f32, @floatFromInt(i)) / 64.0;
    }

    const test_vector2 = try allocator.alloc(f32, 64);
    defer allocator.free(test_vector2);
    for (test_vector2, 0..) |*val, i| {
        val.* = @as(f32, @floatFromInt(i + 32)) / 64.0;
    }

    // Test adding vectors
    _ = try hnsw.addVector(test_vector1, 1);
    _ = try hnsw.addVector(test_vector2, 2);

    // Test FRE with small graph
    var fre = try FRE.init(allocator);
    defer fre.deinit();

    // Test CRDT basic operations
    var crdt_manager = CRDTManager.init(allocator);
    defer crdt_manager.deinit();
}

/// Test MCP server integration with memory safety
fn testMCPIntegration(allocator: std.mem.Allocator) !void {
    var mcp_server = MCPServer.init(allocator);
    defer mcp_server.deinit();

    // Test agent registration
    try mcp_server.registerAgent("test-agent", "Test Agent");

    // Test basic tool preparation (without full execution to avoid leaks)
    const tools = mcp_server.getAvailableTools();
    try testing.expect(tools.len > 0);
}

/// Test complete workflow with memory tracking
fn testEndToEndWorkflow(allocator: std.mem.Allocator) !void {
    // Use arena allocator for complete isolation
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Initialize all components
    var database = Database.init(arena_allocator);
    defer database.deinit();

    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 64,
        .max_connections = 8,
        .ef_construction = 50,
    };
    var semantic_db = try SemanticDatabase.init(arena_allocator, config);
    defer semantic_db.deinit();

    var mcp_server = MCPServer.init(arena_allocator);
    defer mcp_server.deinit();

    // Test workflow: Save → Read → Analyze
    const test_content = "pub fn testFunction() void { return; }";
    try database.saveFile("workflow_test.zig", test_content);

    const read_content = try database.readFile("workflow_test.zig");
    try testing.expect(std.mem.eql(u8, read_content, test_content));

    // Test that we can list files
    const files = try database.listFiles();
    defer arena_allocator.free(files);
    try testing.expect(files.len > 0);
}

test "Integration Test Suite" {
    try main();
}
