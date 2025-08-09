const std = @import("std");
const lib = @import("src/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🧪 Starting Agrama Phase 2 Performance Tests...", .{});

    // Test Database Performance
    try testDatabasePerformance(allocator);

    // Test MCP Server Performance
    try testMCPServerPerformance(allocator);

    std.log.info("✅ Performance tests completed!", .{});
}

fn testDatabasePerformance(allocator: std.mem.Allocator) !void {
    std.log.info("📊 Testing Database Performance...", .{});

    var db = lib.Database.init(allocator);
    defer db.deinit();

    const file_count = 1000;
    const start_time = std.time.milliTimestamp();

    // Test file save performance
    for (0..file_count) |i| {
        const path = try std.fmt.allocPrint(allocator, "test/file_{d}.txt", .{i});
        defer allocator.free(path);

        const content = try std.fmt.allocPrint(allocator, "Content for file {d}", .{i});
        defer allocator.free(content);

        try db.saveFile(path, content);
    }

    const save_time = std.time.milliTimestamp() - start_time;

    // Test file read performance
    const read_start = std.time.milliTimestamp();

    for (0..file_count) |i| {
        const path = try std.fmt.allocPrint(allocator, "test/file_{d}.txt", .{i});
        defer allocator.free(path);

        _ = try db.getFile(path);
    }

    const read_time = std.time.milliTimestamp() - read_start;

    std.log.info("📈 Database Results:", .{});
    std.log.info("  - Save {d} files: {d}ms ({d:.2}ms/file)", .{ file_count, save_time, @as(f64, @floatFromInt(save_time)) / @as(f64, @floatFromInt(file_count)) });
    std.log.info("  - Read {d} files: {d}ms ({d:.2}ms/file)", .{ file_count, read_time, @as(f64, @floatFromInt(read_time)) / @as(f64, @floatFromInt(file_count)) });
}

fn testMCPServerPerformance(allocator: std.mem.Allocator) !void {
    std.log.info("🤖 Testing MCP Server Performance...", .{});

    var db = lib.Database.init(allocator);
    defer db.deinit();

    var server = lib.MCPServer.init(allocator, &db);
    defer server.deinit();

    // Register agent for testing
    try server.registerAgent("perf-agent", "Performance Test Agent");

    // Save test file
    try db.saveFile("performance_test.txt", "Hello, performance testing!");

    const request_count = 500;
    const start_time = std.time.milliTimestamp();

    // Test MCP request handling performance using the public API
    for (0..request_count) |i| {
        const request_id = try std.fmt.allocPrint(allocator, "req-{d}", .{i});
        defer allocator.free(request_id);

        var params_obj = std.json.ObjectMap.init(allocator);
        defer params_obj.deinit();
        try params_obj.put("path", std.json.Value{ .string = "performance_test.txt" });

        var mcp_request = lib.MCPRequest{
            .id = try allocator.dupe(u8, request_id),
            .method = try allocator.dupe(u8, "tools/call"),
            .params = .{
                .name = try allocator.dupe(u8, "read_code"),
                .arguments = std.json.Value{ .object = params_obj },
            },
        };
        defer mcp_request.deinit(allocator);

        var response = try server.handleRequest(mcp_request, "perf-agent");
        defer response.deinit(allocator);
    }

    const mcp_time = std.time.milliTimestamp() - start_time;
    const avg_response_time = @as(f64, @floatFromInt(mcp_time)) / @as(f64, @floatFromInt(request_count));

    std.log.info("⚡ MCP Server Results:", .{});
    std.log.info("  - {d} MCP requests: {d}ms", .{ request_count, mcp_time });
    std.log.info("  - Average response time: {d:.2}ms", .{avg_response_time});

    // Check if we meet the <100ms target
    if (avg_response_time < 100.0) {
        std.log.info("  ✅ PASS: Response time under 100ms target", .{});
    } else {
        std.log.warn("  ⚠️  WARN: Response time exceeds 100ms target", .{});
    }
}
