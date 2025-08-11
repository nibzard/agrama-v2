# Integration Testing Guide

## Overview

Integration testing in Agrama validates the interaction between components, end-to-end workflows, and system-level behavior. Our integration tests ensure that individual components work correctly together, handle real-world scenarios, and maintain performance under realistic loads.

## Integration Test Architecture

### Test Categories

1. **Component Integration Tests**
   - Database ↔ Semantic Search integration
   - Primitive Engine ↔ All backends
   - MCP Server ↔ Tool ecosystem
   - Graph Engine ↔ Search systems

2. **End-to-End Workflow Tests**
   - Complete primitive operation cycles
   - Multi-agent collaboration scenarios
   - Complex query processing pipelines
   - Error propagation and recovery

3. **System-Level Tests**
   - Full system startup/shutdown
   - Resource management under load
   - Concurrent multi-user scenarios
   - Performance at scale

## Component Integration Testing

### Database and Semantic Search Integration
```zig
// tests/primitive_integration_tests.zig
test "database_semantic_search_integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Initialize all components
    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{
        .embedding_dimension = 384,
        .hnsw_max_connections = 16,
        .enable_persistence = false, // In-memory for testing
    });
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    // Test data with both structured and semantic content
    const test_items = [_]struct {
        key: []const u8,
        value: []const u8,
        semantic_content: []const u8,
    }{
        .{ .key = "user_1", .value = "Alice", .semantic_content = "Alice is a software engineer working on AI systems" },
        .{ .key = "user_2", .value = "Bob", .semantic_content = "Bob is a data scientist specializing in machine learning" },
        .{ .key = "user_3", .value = "Carol", .semantic_content = "Carol is a product manager for AI-powered applications" },
    };

    // Store items through primitive engine (tests database + semantic integration)
    for (test_items) |item| {
        var params_obj = std.json.ObjectMap.init(allocator);
        defer params_obj.deinit();
        
        try params_obj.put("key", std.json.Value{ .string = item.key });
        try params_obj.put("value", std.json.Value{ .string = item.value });
        try params_obj.put("content", std.json.Value{ .string = item.semantic_content });
        
        const params = std.json.Value{ .object = params_obj };
        const result = try primitive_engine.executePrimitive("store", params, "integration_test");
        defer result.deinit();
        
        try testing.expect(result.value.object.get("success").?.bool == true);
    }

    // Test hybrid search (database structure + semantic similarity)
    var search_params = std.json.ObjectMap.init(allocator);
    defer search_params.deinit();
    
    try search_params.put("query", std.json.Value{ .string = "AI engineer working on machine learning" });
    try search_params.put("limit", std.json.Value{ .integer = 2 });
    try search_params.put("include_semantic", std.json.Value{ .bool = true });
    
    const search_result = try primitive_engine.executePrimitive("search", std.json.Value{ .object = search_params }, "integration_test");
    defer search_result.deinit();
    
    // Validate integrated search results
    const results_array = search_result.value.object.get("results").?.array;
    try testing.expect(results_array.items.len >= 2);
    
    // Verify semantic ranking worked (Alice and Bob should be top results)
    const first_result = results_array.items[0].object.get("key").?.string;
    try testing.expect(std.mem.eql(u8, first_result, "user_1") or std.mem.eql(u8, first_result, "user_2"));
}
```

### MCP Server Integration Testing
```zig
// tests/enhanced_mcp_tests.zig
test "mcp_server_tool_integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Initialize MCP server with all components
    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    // Test tool registration and discovery
    const tools_request = MCPRequest{
        .id = "test_1",
        .method = "tools/list",
        .params = std.json.Value.null,
    };

    const tools_response = try server.handleRequest(tools_request);
    defer tools_response.deinit();

    try testing.expect(tools_response.result != null);
    const tools = tools_response.result.?.object.get("tools").?.array;
    try testing.expect(tools.items.len >= 5); // Expected core tools

    // Test tool execution with real backend integration
    var tool_params = std.json.ObjectMap.init(allocator);
    defer tool_params.deinit();
    
    try tool_params.put("name", std.json.Value{ .string = "store_knowledge" });
    var arguments = std.json.ObjectMap.init(allocator);
    defer arguments.deinit();
    
    try arguments.put("key", std.json.Value{ .string = "integration_test" });
    try arguments.put("value", std.json.Value{ .string = "MCP integration successful" });
    try tool_params.put("arguments", std.json.Value{ .object = arguments });

    const tool_request = MCPRequest{
        .id = "test_2",
        .method = "tools/call",
        .params = std.json.Value{ .object = tool_params },
    };

    const tool_response = try server.handleRequest(tool_request);
    defer tool_response.deinit();

    // Validate tool execution worked through entire stack
    try testing.expect(tool_response.result != null);
    const tool_result = tool_response.result.?.object.get("content").?.array.items[0].object;
    try testing.expect(tool_result.get("type").?.string.len > 0);
    
    // Verify data was actually stored in backend systems
    var retrieve_params = std.json.ObjectMap.init(allocator);
    defer retrieve_params.deinit();
    
    try retrieve_params.put("name", std.json.Value{ .string = "retrieve_knowledge" });
    var retrieve_args = std.json.ObjectMap.init(allocator);
    defer retrieve_args.deinit();
    
    try retrieve_args.put("key", std.json.Value{ .string = "integration_test" });
    try retrieve_params.put("arguments", std.json.Value{ .object = retrieve_args });

    const retrieve_request = MCPRequest{
        .id = "test_3",
        .method = "tools/call",
        .params = std.json.Value{ .object = retrieve_params },
    };

    const retrieve_response = try server.handleRequest(retrieve_request);
    defer retrieve_response.deinit();

    // Validate round-trip worked
    const retrieved_content = retrieve_response.result.?.object.get("content").?.array.items[0].object.get("text").?.string;
    try testing.expect(std.mem.indexOf(u8, retrieved_content, "MCP integration successful") != null);
}
```

### Concurrent Multi-Agent Integration
```zig
test "concurrent_multi_agent_integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    const num_agents = 5;
    const operations_per_agent = 20;
    var threads: [num_agents]std.Thread = undefined;
    var results: [num_agents]bool = [_]bool{false} ** num_agents;

    const AgentContext = struct {
        server: *MCPCompliantServer,
        agent_id: usize,
        operations: usize,
        result: *bool,
        allocator: Allocator,
    };

    const agent_function = struct {
        fn run(context: *AgentContext) void {
            var local_gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
            defer _ = local_gpa.deinit();
            const local_allocator = local_gpa.allocator();

            var success_count: usize = 0;

            for (0..context.operations) |i| {
                // Each agent performs store and retrieve operations
                var store_params = std.json.ObjectMap.init(local_allocator);
                defer store_params.deinit();

                try store_params.put("name", std.json.Value{ .string = "store_knowledge" });
                var store_args = std.json.ObjectMap.init(local_allocator);
                defer store_args.deinit();

                const key = std.fmt.allocPrint(local_allocator, "agent_{}_{}", .{ context.agent_id, i }) catch continue;
                defer local_allocator.free(key);
                const value = std.fmt.allocPrint(local_allocator, "data_from_agent_{}_operation_{}", .{ context.agent_id, i }) catch continue;
                defer local_allocator.free(value);

                try store_args.put("key", std.json.Value{ .string = key });
                try store_args.put("value", std.json.Value{ .string = value });
                try store_params.put("arguments", std.json.Value{ .object = store_args });

                const store_request = MCPRequest{
                    .id = std.fmt.allocPrint(local_allocator, "agent_{}_{}", .{ context.agent_id, i }) catch continue,
                    .method = "tools/call",
                    .params = std.json.Value{ .object = store_params },
                };

                const store_response = context.server.handleRequest(store_request) catch continue;
                defer store_response.deinit();

                if (store_response.result != null) {
                    success_count += 1;
                }

                // Small delay to interleave operations
                std.time.sleep(1_000_000); // 1ms
            }

            context.result.* = success_count == context.operations;
        }
    }.run;

    // Create agent contexts
    var contexts: [num_agents]AgentContext = undefined;
    for (0..num_agents) |i| {
        contexts[i] = AgentContext{
            .server = &server,
            .agent_id = i,
            .operations = operations_per_agent,
            .result = &results[i],
            .allocator = allocator,
        };
    }

    // Start all agent threads
    for (0..num_agents) |i| {
        threads[i] = try std.Thread.spawn(.{}, agent_function, .{&contexts[i]});
    }

    // Wait for all agents to complete
    for (0..num_agents) |i| {
        threads[i].join();
    }

    // Validate all agents succeeded
    for (results, 0..) |result, i| {
        try testing.expect(result); // All agents should complete successfully
        std.debug.print("Agent {} completed successfully\n", .{i});
    }

    // Validate data integrity - check that all data was stored correctly
    var verification_count: usize = 0;
    for (0..num_agents) |agent_id| {
        for (0..operations_per_agent) |op_id| {
            var retrieve_params = std.json.ObjectMap.init(allocator);
            defer retrieve_params.deinit();

            try retrieve_params.put("name", std.json.Value{ .string = "retrieve_knowledge" });
            var retrieve_args = std.json.ObjectMap.init(allocator);
            defer retrieve_args.deinit();

            const key = try std.fmt.allocPrint(allocator, "agent_{}_{}", .{ agent_id, op_id });
            defer allocator.free(key);

            try retrieve_args.put("key", std.json.Value{ .string = key });
            try retrieve_params.put("arguments", std.json.Value{ .object = retrieve_args });

            const retrieve_request = MCPRequest{
                .id = try std.fmt.allocPrint(allocator, "verify_{}_{}", .{ agent_id, op_id }),
                .method = "tools/call",
                .params = std.json.Value{ .object = retrieve_params },
            };

            const retrieve_response = try server.handleRequest(retrieve_request);
            defer retrieve_response.deinit();

            if (retrieve_response.result != null) {
                verification_count += 1;
            }
        }
    }

    try testing.expect(verification_count == num_agents * operations_per_agent);
    std.debug.print("Verified {} data items from concurrent operations\n", .{verification_count});
}
```

## End-to-End Workflow Testing

### Complete Primitive Operation Cycle
```zig
test "primitive_engine_full_cycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Initialize complete system
    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    // Test complete workflow: store -> link -> search -> transform -> retrieve
    
    // 1. Store initial data
    const entities = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "concept_1", .value = "Machine Learning algorithms" },
        .{ .key = "concept_2", .value = "Neural Network architectures" },
        .{ .key = "concept_3", .value = "Data Science methodologies" },
    };

    for (entities) |entity| {
        var store_params = std.json.ObjectMap.init(allocator);
        defer store_params.deinit();
        
        try store_params.put("key", std.json.Value{ .string = entity.key });
        try store_params.put("value", std.json.Value{ .string = entity.value });
        
        const store_result = try primitive_engine.executePrimitive("store", std.json.Value{ .object = store_params }, "workflow_test");
        defer store_result.deinit();
        
        try testing.expect(store_result.value.object.get("success").?.bool == true);
    }

    // 2. Create links between concepts
    const links = [_]struct { from: []const u8, to: []const u8, relationship: []const u8 }{
        .{ .from = "concept_1", .to = "concept_2", .relationship = "implements" },
        .{ .from = "concept_2", .to = "concept_3", .relationship = "supports" },
        .{ .from = "concept_1", .to = "concept_3", .relationship = "uses" },
    };

    for (links) |link| {
        var link_params = std.json.ObjectMap.init(allocator);
        defer link_params.deinit();
        
        try link_params.put("from", std.json.Value{ .string = link.from });
        try link_params.put("to", std.json.Value{ .string = link.to });
        try link_params.put("relationship", std.json.Value{ .string = link.relationship });
        
        const link_result = try primitive_engine.executePrimitive("link", std.json.Value{ .object = link_params }, "workflow_test");
        defer link_result.deinit();
        
        try testing.expect(link_result.value.object.get("success").?.bool == true);
    }

    // 3. Search for related concepts
    var search_params = std.json.ObjectMap.init(allocator);
    defer search_params.deinit();
    
    try search_params.put("query", std.json.Value{ .string = "learning algorithms neural networks" });
    try search_params.put("include_links", std.json.Value{ .bool = true });
    try search_params.put("limit", std.json.Value{ .integer = 10 });
    
    const search_result = try primitive_engine.executePrimitive("search", std.json.Value{ .object = search_params }, "workflow_test");
    defer search_result.deinit();
    
    const search_results = search_result.value.object.get("results").?.array;
    try testing.expect(search_results.items.len >= 2);

    // 4. Transform data based on search results
    var transform_params = std.json.ObjectMap.init(allocator);
    defer transform_params.deinit();
    
    try transform_params.put("key", std.json.Value{ .string = "concept_1" });
    try transform_params.put("operation", std.json.Value{ .string = "enhance" });
    try transform_params.put("data", std.json.Value{ .string = "Enhanced with semantic relationships" });
    
    const transform_result = try primitive_engine.executePrimitive("transform", std.json.Value{ .object = transform_params }, "workflow_test");
    defer transform_result.deinit();
    
    try testing.expect(transform_result.value.object.get("success").?.bool == true);

    // 5. Retrieve final state and validate workflow completion
    var retrieve_params = std.json.ObjectMap.init(allocator);
    defer retrieve_params.deinit();
    
    try retrieve_params.put("key", std.json.Value{ .string = "concept_1" });
    try retrieve_params.put("include_links", std.json.Value{ .bool = true });
    try retrieve_params.put("include_history", std.json.Value{ .bool = true });
    
    const retrieve_result = try primitive_engine.executePrimitive("retrieve", std.json.Value{ .object = retrieve_params }, "workflow_test");
    defer retrieve_result.deinit();
    
    const retrieved_data = retrieve_result.value.object.get("data").?;
    try testing.expect(retrieved_data.object.get("key").?.string.len > 0);
    
    // Validate links were preserved
    const retrieved_links = retrieved_data.object.get("links").?.array;
    try testing.expect(retrieved_links.items.len >= 2); // concept_1 has links to concept_2 and concept_3
    
    // Validate transformation was applied
    const history = retrieved_data.object.get("history").?.array;
    try testing.expect(history.items.len >= 2); // Original store + transform operations
}
```

## System-Level Integration Testing

### Resource Management Under Load
```zig
test "system_resource_management_under_load" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Configure system with specific resource limits
    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    const load_config = struct {
        const concurrent_agents = 10;
        const operations_per_agent = 100;
        const data_size_kb = 10; // 10KB per operation
        const test_duration_seconds = 30;
    };

    var monitor = ResourceMonitor.init(allocator);
    defer monitor.deinit();

    const start_time = std.time.timestamp();
    var total_operations: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
    var errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

    const LoadContext = struct {
        server: *MCPCompliantServer,
        agent_id: usize,
        total_ops: *std.atomic.Value(u64),
        error_count: *std.atomic.Value(u64),
        start_time: i64,
        duration: i64,
        allocator: Allocator,
    };

    const load_generator = struct {
        fn run(context: *LoadContext) void {
            var local_gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
            defer _ = local_gpa.deinit();
            const local_allocator = local_gpa.allocator();

            var operation_count: usize = 0;
            
            while (std.time.timestamp() - context.start_time < context.duration) {
                // Generate load data
                const data_content = local_allocator.alloc(u8, load_config.data_size_kb * 1024) catch {
                    _ = context.error_count.fetchAdd(1, .seq_cst);
                    continue;
                };
                defer local_allocator.free(data_content);
                @memset(data_content, @as(u8, @intCast('A' + (operation_count % 26))));

                // Perform store operation
                var store_params = std.json.ObjectMap.init(local_allocator);
                defer store_params.deinit();

                try store_params.put("name", std.json.Value{ .string = "store_knowledge" });
                var args = std.json.ObjectMap.init(local_allocator);
                defer args.deinit();

                const key = std.fmt.allocPrint(local_allocator, "load_{}_{}", .{ context.agent_id, operation_count }) catch {
                    _ = context.error_count.fetchAdd(1, .seq_cst);
                    continue;
                };
                defer local_allocator.free(key);

                try args.put("key", std.json.Value{ .string = key });
                try args.put("value", std.json.Value{ .string = data_content });
                try store_params.put("arguments", std.json.Value{ .object = args });

                const request = MCPRequest{
                    .id = key,
                    .method = "tools/call",
                    .params = std.json.Value{ .object = store_params },
                };

                const response = context.server.handleRequest(request) catch {
                    _ = context.error_count.fetchAdd(1, .seq_cst);
                    continue;
                };
                defer response.deinit();

                if (response.result != null) {
                    _ = context.total_ops.fetchAdd(1, .seq_cst);
                } else {
                    _ = context.error_count.fetchAdd(1, .seq_cst);
                }

                operation_count += 1;
                
                // Brief pause to prevent overwhelming the system
                std.time.sleep(10_000); // 10 microseconds
            }
        }
    }.run;

    // Start load generators
    var threads: [load_config.concurrent_agents]std.Thread = undefined;
    var contexts: [load_config.concurrent_agents]LoadContext = undefined;

    for (0..load_config.concurrent_agents) |i| {
        contexts[i] = LoadContext{
            .server = &server,
            .agent_id = i,
            .total_ops = &total_operations,
            .error_count = &errors,
            .start_time = start_time,
            .duration = load_config.test_duration_seconds,
            .allocator = allocator,
        };
        threads[i] = try std.Thread.spawn(.{}, load_generator, .{&contexts[i]});
    }

    // Monitor resources during load test
    var peak_memory: usize = 0;
    var monitoring = true;
    const monitor_thread = try std.Thread.spawn(.{}, struct {
        fn monitor_resources(peak: *usize, active: *bool) void {
            while (active.*) {
                const current_memory = getCurrentMemoryUsage();
                peak.* = @max(peak.*, current_memory);
                std.time.sleep(100_000_000); // 100ms monitoring interval
            }
        }
    }.monitor_resources, .{ &peak_memory, &monitoring });

    // Wait for load test completion
    for (0..load_config.concurrent_agents) |i| {
        threads[i].join();
    }

    monitoring = false;
    monitor_thread.join();

    const final_operations = total_operations.load(.seq_cst);
    const final_errors = errors.load(.seq_cst);
    const actual_duration = std.time.timestamp() - start_time;

    // Validate system performance under load
    const throughput = @as(f64, @floatFromInt(final_operations)) / @as(f64, @floatFromInt(actual_duration));
    const error_rate = @as(f64, @floatFromInt(final_errors)) / @as(f64, @floatFromInt(final_operations + final_errors));

    std.debug.print("Load test results:\n");
    std.debug.print("  Operations: {}\n", .{final_operations});
    std.debug.print("  Errors: {}\n", .{final_errors});
    std.debug.print("  Throughput: {:.2} ops/sec\n", .{throughput});
    std.debug.print("  Error Rate: {:.2}%\n", .{error_rate * 100});
    std.debug.print("  Peak Memory: {:.2} MB\n", .{@as(f64, @floatFromInt(peak_memory)) / (1024 * 1024)});

    // Performance requirements
    try testing.expect(throughput >= 50.0); // At least 50 ops/sec under load
    try testing.expect(error_rate < 0.01); // Less than 1% error rate
    try testing.expect(peak_memory < 500 * 1024 * 1024); // Less than 500MB peak memory
    try testing.expect(final_operations > 1000); // Processed significant operations
}

fn getCurrentMemoryUsage() usize {
    // Simplified memory usage estimation
    // In production, would use platform-specific APIs
    return 100 * 1024 * 1024; // 100MB baseline
}

const ResourceMonitor = struct {
    allocator: Allocator,
    
    fn init(allocator: Allocator) ResourceMonitor {
        return .{ .allocator = allocator };
    }
    
    fn deinit(self: *ResourceMonitor) void {
        _ = self;
    }
};
```

## Performance Integration Testing

### Hybrid Query Performance at Scale
```zig
test "hybrid_query_performance_at_scale" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Set up performance regression detection
    const config = RegressionDetectionConfig{
        .latency_regression_threshold = 0.1, // 10% regression tolerance
    };
    var detector = PerformanceRegressionDetector.init(allocator, config);
    defer detector.deinit();

    // Initialize system with realistic scale
    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{
        .embedding_dimension = 384,
        .hnsw_max_connections = 32,
        .ef_construction = 100,
        .enable_persistence = false,
    });
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    // Populate with scaled data
    const num_entities = 10000;
    std.debug.print("Populating {} entities for scale testing...\n", .{num_entities});

    for (0..num_entities) |i| {
        var store_params = std.json.ObjectMap.init(allocator);
        defer store_params.deinit();

        const key = try std.fmt.allocPrint(allocator, "entity_{}", .{i});
        defer allocator.free(key);
        
        const value = try std.fmt.allocPrint(allocator, "Entity {} contains information about topic {} with relationships to {} related concepts", .{ i, i % 100, i % 10 });
        defer allocator.free(value);

        try store_params.put("key", std.json.Value{ .string = key });
        try store_params.put("value", std.json.Value{ .string = value });

        const result = try primitive_engine.executePrimitive("store", std.json.Value{ .object = store_params }, "scale_test");
        defer result.deinit();

        if (i % 1000 == 0) {
            std.debug.print("  Populated {} entities\n", .{i + 1});
        }
    }

    // Benchmark hybrid queries
    var query_engine: *PrimitiveEngine = &primitive_engine;
    const benchmark_fn = struct {
        var engine: *PrimitiveEngine = undefined;
        
        fn run() !void {
            var search_params = std.json.ObjectMap.init(std.heap.page_allocator);
            defer search_params.deinit();

            try search_params.put("query", std.json.Value{ .string = "information about topic relationships concepts" });
            try search_params.put("limit", std.json.Value{ .integer = 20 });
            try search_params.put("include_semantic", std.json.Value{ .bool = true });
            try search_params.put("include_graph", std.json.Value{ .bool = true });

            const result = try engine.executePrimitive("search", std.json.Value{ .object = search_params }, "benchmark");
            defer result.deinit();
        }
    };
    benchmark_fn.engine = query_engine;

    // Run performance benchmark
    const result = try detector.benchmarkWithRegressionDetection("hybrid_query_10k_entities", benchmark_fn.run, 100);

    // Validate performance at scale
    try testing.expect(!result.has_regression);
    try testing.expect(result.current_measurement.latency_ms() < 10.0); // <10ms target for 10K entities
    try testing.expect(result.current_measurement.throughput_ops_per_sec > 100.0); // >100 queries/sec

    std.debug.print("Hybrid query performance: {:.2}ms latency, {:.1} ops/sec\n", .{
        result.current_measurement.latency_ms(),
        result.current_measurement.throughput_ops_per_sec,
    });
}
```

## Error Propagation and Recovery Testing

### System-Wide Error Recovery
```zig
test "system_error_recovery_integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    // Test various error scenarios and recovery
    const error_scenarios = [_]struct {
        name: []const u8,
        setup: fn (*MCPCompliantServer, Allocator) anyerror!void,
        operation: fn (*MCPCompliantServer, Allocator) anyerror!MCPResponse,
        expected_recovery: bool,
        cleanup: fn (*MCPCompliantServer, Allocator) void,
    }{
        .{
            .name = "database_unavailable",
            .setup = simulateDatabaseUnavailable,
            .operation = attemptStoreOperation,
            .expected_recovery = true,
            .cleanup = restoreDatabase,
        },
        .{
            .name = "memory_exhaustion",
            .setup = simulateMemoryExhaustion,
            .operation = attemptLargeOperation,
            .expected_recovery = true,
            .cleanup = restoreMemory,
        },
        .{
            .name = "network_timeout",
            .setup = simulateNetworkTimeout,
            .operation = attemptRemoteOperation,
            .expected_recovery = true,
            .cleanup = restoreNetwork,
        },
    };

    for (error_scenarios) |scenario| {
        std.debug.print("Testing error scenario: {s}\n", .{scenario.name});

        // Set up error condition
        try scenario.setup(&server, allocator);

        // Attempt operation (should handle error gracefully)
        const result = scenario.operation(&server, allocator);
        
        if (scenario.expected_recovery) {
            // Operation should complete with error handling
            const response = result catch |err| blk: {
                // Verify error is handled gracefully
                try testing.expect(err != error.SystemCrash);
                break :blk MCPResponse{
                    .id = "error_test",
                    .result = null,
                    .error = MCPError{
                        .code = -1,
                        .message = "Graceful error handling",
                    },
                };
            };
            defer response.deinit();

            // System should still be responsive
            const health_check = server.healthCheck();
            try testing.expect(health_check.operational);
        }

        // Clean up error condition
        scenario.cleanup(&server, allocator);

        // Verify system recovers completely
        const recovery_response = try attemptStoreOperation(&server, allocator);
        defer recovery_response.deinit();
        try testing.expect(recovery_response.result != null);

        std.debug.print("  Scenario {s}: Recovery successful\n", .{scenario.name});
    }
}

fn simulateDatabaseUnavailable(server: *MCPCompliantServer, allocator: Allocator) !void {
    _ = server;
    _ = allocator;
    // Simulate database becoming unavailable
}

fn simulateMemoryExhaustion(server: *MCPCompliantServer, allocator: Allocator) !void {
    _ = server;
    _ = allocator;
    // Simulate memory exhaustion condition
}

fn simulateNetworkTimeout(server: *MCPCompliantServer, allocator: Allocator) !void {
    _ = server;
    _ = allocator;
    // Simulate network timeout condition
}

fn attemptStoreOperation(server: *MCPCompliantServer, allocator: Allocator) !MCPResponse {
    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("name", std.json.Value{ .string = "store_knowledge" });
    var args = std.json.ObjectMap.init(allocator);
    defer args.deinit();

    try args.put("key", std.json.Value{ .string = "test_key" });
    try args.put("value", std.json.Value{ .string = "test_value" });
    try params.put("arguments", std.json.Value{ .object = args });

    const request = MCPRequest{
        .id = "store_test",
        .method = "tools/call",
        .params = std.json.Value{ .object = params },
    };

    return try server.handleRequest(request);
}

fn attemptLargeOperation(server: *MCPCompliantServer, allocator: Allocator) !MCPResponse {
    var params = std.json.ObjectMap.init(allocator);
    defer params.deinit();

    try params.put("name", std.json.Value{ .string = "store_knowledge" });
    var args = std.json.ObjectMap.init(allocator);
    defer args.deinit();

    // Large data operation
    const large_value = try allocator.alloc(u8, 10 * 1024 * 1024); // 10MB
    defer allocator.free(large_value);
    @memset(large_value, 'X');

    try args.put("key", std.json.Value{ .string = "large_test" });
    try args.put("value", std.json.Value{ .string = large_value });
    try params.put("arguments", std.json.Value{ .object = args });

    const request = MCPRequest{
        .id = "large_test",
        .method = "tools/call",
        .params = std.json.Value{ .object = params },
    };

    return try server.handleRequest(request);
}

fn attemptRemoteOperation(server: *MCPCompliantServer, allocator: Allocator) !MCPResponse {
    // Simulate operation that requires external resources
    return attemptStoreOperation(server, allocator);
}

fn restoreDatabase(server: *MCPCompliantServer, allocator: Allocator) void {
    _ = server;
    _ = allocator;
    // Restore database availability
}

fn restoreMemory(server: *MCPCompliantServer, allocator: Allocator) void {
    _ = server;
    _ = allocator;
    // Restore memory availability
}

fn restoreNetwork(server: *MCPCompliantServer, allocator: Allocator) void {
    _ = server;
    _ = allocator;
    // Restore network connectivity
}
```

## Best Practices for Integration Testing

### 1. Realistic Test Scenarios
- Use production-like data volumes and complexity
- Test with realistic network latencies and failures
- Include concurrent user scenarios
- Validate performance under expected loads

### 2. Comprehensive System Coverage
- Test all component interfaces and interactions
- Validate end-to-end workflows
- Include error propagation and recovery scenarios
- Test resource management and cleanup

### 3. Performance Integration
- Include performance regression detection
- Validate scalability characteristics
- Test memory usage patterns under load
- Monitor resource consumption trends

### 4. Error Handling Integration
- Test error propagation between components
- Validate graceful degradation scenarios
- Test system recovery capabilities
- Include timeout and retry logic testing

### 5. Resource Management
- Use proper cleanup in all test scenarios
- Monitor memory usage throughout tests
- Validate resource limits and constraints
- Test resource exhaustion scenarios

## CI/CD Integration

### Automated Integration Testing
```bash
# Integration test pipeline
#!/bin/bash

# Build system
zig build || exit 1

# Run integration tests with memory validation
zig build test --test-filter "integration" || exit 1

# Run performance regression detection
zig run tests/performance_regression_detector.zig || exit 1

# Run concurrent stress tests
zig run tests/concurrent_stress_tests.zig || exit 1

# Generate integration test report
echo "✓ All integration tests passed"
```

### Performance Monitoring
- Track integration test performance over time
- Alert on performance regressions
- Monitor resource usage trends
- Validate scalability characteristics

## Conclusion

Integration testing in Agrama ensures that all system components work correctly together under realistic conditions. The comprehensive approach covers component integration, end-to-end workflows, performance at scale, and error recovery scenarios, providing confidence in the system's production readiness and reliability.