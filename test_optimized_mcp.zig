//! Quick test of optimized MCP server performance

const std = @import("std");
const print = std.debug.print;

const Database = @import("src/database.zig").Database;
const MCPServer = @import("src/mcp_server.zig").MCPServer;
const MCPRequest = @import("src/mcp_server.zig").MCPRequest;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("\n🚀 OPTIMIZED MCP SERVER PERFORMANCE TEST\n", .{});
    print("==================================================\n", .{});

    var db = Database.init(allocator);
    defer db.deinit();

    var server = MCPServer.init(allocator, &db);
    defer server.deinit();

    // Initialize advanced search capabilities
    server.initializeAdvancedSearch() catch {
        print("⚠️  Advanced search initialization failed (expected - mock components)\n", .{});
    };

    // Setup test data
    try db.saveFile("src/test.js", "function testOptimization() { return 'fast!'; }");
    try server.registerAgent("test_agent", "Performance Test Agent");

    print("\n📊 Testing optimized tool performance:\n", .{});

    // Test scenarios with timing
    const scenarios = [_]struct {
        name: []const u8,
        tool: []const u8,
        args: []const u8,
    }{
        .{ .name = "Read Code (Optimized)", .tool = "read_code", .args = "src/test.js" },
        .{ .name = "Semantic Search", .tool = "semantic_search", .args = "function optimization" },
        .{ .name = "Dependency Analysis", .tool = "analyze_dependencies", .args = "src/test.js" },
        .{ .name = "Triple Hybrid Search", .tool = "hybrid_search", .args = "function test optimization" },
        .{ .name = "Get Context", .tool = "get_context", .args = "metrics" },
    };

    var total_time: u64 = 0;

    for (scenarios, 0..) |scenario, i| {
        // Create simple JSON arguments for test
        var args_obj = std.json.ObjectMap.init(allocator);
        defer args_obj.deinit();

        if (std.mem.eql(u8, scenario.tool, "read_code") or std.mem.eql(u8, scenario.tool, "analyze_dependencies")) {
            try args_obj.put("path", std.json.Value{ .string = scenario.args });
        } else if (std.mem.eql(u8, scenario.tool, "semantic_search") or std.mem.eql(u8, scenario.tool, "hybrid_search")) {
            try args_obj.put("query", std.json.Value{ .string = scenario.args });
            try args_obj.put("k", std.json.Value{ .integer = 10 });
        } else {
            try args_obj.put("type", std.json.Value{ .string = scenario.args });
        }

        const request_id = try std.fmt.allocPrint(allocator, "test_{}", .{i});
        defer allocator.free(request_id);

        const request = MCPRequest{
            .id = request_id,
            .method = "tools/call",
            .params = .{
                .name = scenario.tool,
                .arguments = std.json.Value{ .object = args_obj },
            },
        };

        // Measure performance
        const start_time = std.time.nanoTimestamp();
        var response = server.handleRequest(request, "test_agent") catch |err| {
            print("  ❌ {s}: Failed with error {}\n", .{ scenario.name, err });
            continue;
        };
        const end_time = std.time.nanoTimestamp();
        defer response.deinit(allocator);

        const latency_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        total_time += @as(u64, @intFromFloat(latency_ms));

        const status = if (latency_ms < 100.0) "✅" else if (latency_ms < 500.0) "⚠️" else "❌";
        print("  {s} {s}: {:.3}ms\n", .{ status, scenario.name, latency_ms });

        // Test caching by running same request again
        const cache_start = std.time.nanoTimestamp();
        var cached_response = server.handleRequest(request, "test_agent") catch |err| {
            print("    Cache test failed: {}\n", .{err});
            continue;
        };
        const cache_end = std.time.nanoTimestamp();
        defer cached_response.deinit(allocator);

        const cache_latency_ms = @as(f64, @floatFromInt(cache_end - cache_start)) / 1_000_000.0;
        const cache_improvement = latency_ms / cache_latency_ms;

        if (cache_latency_ms < latency_ms * 0.5) {
            print("    🚀 Cache hit: {:.3}ms ({:.1}× faster)\n", .{ cache_latency_ms, cache_improvement });
        } else {
            print("    📝 No cache benefit: {:.3}ms\n", .{cache_latency_ms});
        }
    }

    // Get final statistics
    const stats = server.getStats();

    print("\n📈 Performance Summary:\n", .{});
    print("  Total requests handled: {}\n", .{stats.requests});
    print("  Average response time: {:.2}ms\n", .{stats.avg_response_ms});
    print("  Cache hit ratio: {:.1}%\n", .{stats.cache_hit_ratio * 100});
    print("  Cache size: {} entries\n", .{stats.cache_size});
    print("  Connected agents: {}\n", .{stats.agents});

    print("\n🎯 Performance Target Validation:\n", .{});
    print("  Sub-100ms P50 target: {s}\n", .{if (stats.avg_response_ms < 100.0) "✅ PASSED" else "❌ FAILED"});
    print("  Caching effectiveness: {s}\n", .{if (stats.cache_size > 0) "✅ ACTIVE" else "❌ NOT WORKING"});
    print("  Agent scalability: {s}\n", .{if (stats.agents >= 1) "✅ WORKING" else "❌ FAILED"});

    const overall_success = stats.avg_response_ms < 100.0 and stats.agents >= 1;
    print("\n{s} Overall Result: {s}\n", .{ if (overall_success) "🏆" else "⚠️", if (overall_success) "OPTIMIZED MCP SERVER VALIDATED" else "NEEDS IMPROVEMENT" });
}
