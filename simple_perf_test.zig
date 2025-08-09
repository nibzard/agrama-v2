const std = @import("std");
const lib = @import("src/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🧪 Agrama Phase 2 Simple Performance Test", .{});

    // Test Database Performance
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

    std.log.info("📈 Database Performance Results:", .{});
    std.log.info("  - Save {d} files: {d}ms ({d:.2}ms/file)", .{ file_count, save_time, @as(f64, @floatFromInt(save_time)) / @as(f64, @floatFromInt(file_count)) });
    std.log.info("  - Read {d} files: {d}ms ({d:.2}ms/file)", .{ file_count, read_time, @as(f64, @floatFromInt(read_time)) / @as(f64, @floatFromInt(file_count)) });

    // Test history performance
    const history_start = std.time.milliTimestamp();
    const history = try db.getHistory("test/file_0.txt", 10);
    defer allocator.free(history);
    const history_time = std.time.milliTimestamp() - history_start;

    std.log.info("  - Get file history: {d}ms", .{history_time});
    std.log.info("  - History entries: {d}", .{history.len});

    // Test MCP Server initialization
    var server = lib.MCPServer.init(allocator, &db);
    defer server.deinit();

    try server.registerAgent("test-agent", "Test Agent");
    const stats = server.getStats();

    std.log.info("🤖 MCP Server Performance:", .{});
    std.log.info("  - Registered agents: {d}", .{stats.agents});
    std.log.info("  - Server initialization: ✅ Success", .{});

    std.log.info("✅ All performance tests completed!", .{});
}
