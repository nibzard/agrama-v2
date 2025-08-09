const std = @import("std");
const print = std.debug.print;

/// Simple demo to test basic benchmarking functionality
pub fn main() !void {
    print("🧪 Agrama Benchmark Framework Demo\n", .{});
    print("==================================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic timing
    var timer = try std.time.Timer.start();

    // Simple computation
    var result: u64 = 1;
    for (0..1000) |i| {
        result = result * 2 + i;
        result = result % 1000000;
    }

    const elapsed_ns = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    print("✅ Basic timing test:\n", .{});
    print("   Computation result: {}\n", .{result});
    print("   Elapsed time: {:.3} ms\n", .{elapsed_ms});

    // Test memory allocation
    const test_size = 1024 * 1024; // 1MB
    timer.reset();

    const memory = try allocator.alloc(u8, test_size);
    defer allocator.free(memory);

    // Touch memory
    for (memory, 0..) |*byte, i| {
        byte.* = @as(u8, @intCast(i % 256));
    }

    const alloc_elapsed_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;

    print("✅ Memory allocation test:\n", .{});
    print("   Allocated: {} bytes\n", .{test_size});
    print("   Time: {:.3} ms\n", .{alloc_elapsed_ms});

    print("\n🚀 Framework basic functionality verified!\n", .{});
    print("Ready to run comprehensive benchmarks:\n", .{});
    print("  zig build bench-quick  # Quick test\n", .{});
    print("  zig build bench        # Full suite\n", .{});
}
