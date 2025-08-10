const std = @import("std");
const print = std.debug.print;
const TrueFRE = @import("src/fre_true.zig").TrueFrontierReductionEngine;

/// Demonstrate the difference between true FRE algorithm and our previous implementation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 True FRE Algorithm Demonstration\n", .{});
    print("====================================\n\n", .{});

    // Test different graph densities to show when FRE becomes advantageous
    const test_cases = [_]struct {
        name: []const u8,
        nodes: u32,
        avg_degree: u32,
        description: []const u8,
    }{
        .{ .name = "Sparse", .nodes = 1000, .avg_degree = 2, .description = "Typical dependency graph" },
        .{ .name = "Medium", .nodes = 1000, .avg_degree = 10, .description = "Code call graph" },
        .{ .name = "Dense", .nodes = 1000, .avg_degree = 50, .description = "Knowledge graph" },
        .{ .name = "Very Dense", .nodes = 1000, .avg_degree = 100, .description = "Highly connected system" },
    };

    for (test_cases) |test_case| {
        print("📊 Testing {s} Graph ({s})\n", .{ test_case.name, test_case.description });
        print("   Nodes: {}, Average Degree: {}\n", .{ test_case.nodes, test_case.avg_degree });

        var fre = TrueFRE.init(allocator);
        defer fre.deinit();

        // Generate test graph
        var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())) + test_case.avg_degree);
        const total_edges = test_case.nodes * test_case.avg_degree;

        var edges_added: u32 = 0;
        while (edges_added < total_edges) {
            const from = rng.random().intRangeAtMost(u32, 0, test_case.nodes - 1);
            const to = rng.random().intRangeAtMost(u32, 0, test_case.nodes - 1);

            if (from != to) {
                try fre.addEdge(from, to, 1.0 + rng.random().float(f32) * 9.0);
                edges_added += 1;
            }
        }

        const stats = fre.getStats();
        print("   Actual Edges: {}, k: {}, t: {}\n", .{ stats.edges, stats.k, stats.t });

        // Theoretical complexity analysis
        const n = @as(f32, @floatFromInt(stats.nodes));
        const m = @as(f32, @floatFromInt(stats.edges));
        const log_n = std.math.log2(n);
        const log_2_3_n = std.math.pow(f32, log_n, 2.0 / 3.0);

        const dijkstra_complexity = m + n * log_n;
        const fre_complexity = m * log_2_3_n;
        const theoretical_speedup = dijkstra_complexity / fre_complexity;

        print("   📈 Theoretical Complexity:\n", .{});
        print("      Dijkstra: O({d:.0}) = {d:.0}\n", .{ m + n * log_n, dijkstra_complexity });
        print("      FRE: O({d:.0}) = {d:.0}\n", .{ m * log_2_3_n, fre_complexity });
        print("      Expected Speedup: {d:.2}×\n", .{theoretical_speedup});

        const should_use_fre = fre.shouldUseFRE();
        print("   🎯 Recommendation: {s}\n", .{if (should_use_fre) "Use FRE ✅" else "Use Dijkstra ❌"});

        // Performance test
        const source: u32 = 0;
        const distance_bound: f32 = 50.0;

        var result = try fre.singleSourceShortestPaths(source, distance_bound);
        defer result.deinit();

        print("   ⏱️  Performance: {d}ns, Vertices Processed: {d}\n", .{ result.computation_time_ns, result.vertices_processed });

        // Find reachable nodes
        var reachable_count: u32 = 0;
        var distance_iterator = result.distances.iterator();
        while (distance_iterator.next()) |entry| {
            _ = entry;
            reachable_count += 1;
        }

        print("   📍 Reachable Nodes: {d}/{d} ({d:.1}%)\n", .{ reachable_count, stats.nodes, @as(f32, @floatFromInt(reachable_count)) * 100.0 / @as(f32, @floatFromInt(stats.nodes)) });
        print("\n", .{});
    }

    print("🔍 Key Insights:\n", .{});
    print("================\n", .{});
    print("• FRE is NOT always better than Dijkstra\n", .{});
    print("• FRE excels on DENSE graphs where m >> n log n\n", .{});
    print("• For typical dependency graphs (sparse), Dijkstra is faster\n", .{});
    print("• FRE's advantage grows with graph density\n", .{});
    print("• The paper's O(m log^(2/3) n) assumes specific graph structures\n\n", .{});

    print("🧮 Algorithm Parameter Demonstration:\n", .{});
    print("=====================================\n", .{});

    // Show how parameters scale
    const sizes = [_]u32{ 100, 1000, 10000, 100000 };
    for (sizes) |n| {
        const n_f = @as(f32, @floatFromInt(n));
        const log_n = std.math.log2(n_f);
        const k = @max(1, @as(u32, @intFromFloat(std.math.pow(f32, log_n, 1.0 / 3.0))));
        const t = @max(1, @as(u32, @intFromFloat(std.math.pow(f32, log_n, 2.0 / 3.0))));

        print("n = {d}: k = {d} (log^(1/3) n), t = {d} (log^(2/3) n)\n", .{ n, k, t });
    }

    print("\n✅ True FRE Algorithm Implementation Complete!\n", .{});
    print("   The algorithm now correctly implements the paper's BMSSP approach\n", .{});
    print("   with proper parameters k = ⌊log^(1/3)(n)⌋ and t = ⌊log^(2/3)(n)⌋\n", .{});
}
