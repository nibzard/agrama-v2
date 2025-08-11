# Unit Testing Guide

## Overview

Unit testing in Agrama follows Zig's native testing framework while extending it with comprehensive memory safety validation, performance tracking, and error handling verification. Every unit test is designed to be isolated, fast, and thoroughly validated for memory leaks and performance regressions.

## Test Structure and Organization

### Test File Organization
```
src/
├── primitives.zig              # Core primitive operations
│   └── test "primitive_store_basic"
│   └── test "primitive_retrieve_validation" 
├── database.zig                # Database operations
│   └── test "database_init_cleanup"
│   └── test "temporal_graph_operations"
├── semantic_database.zig       # Semantic search
│   └── test "semantic_embedding_storage"
│   └── test "hnsw_index_operations"
tests/
├── primitive_tests.zig         # Comprehensive primitive tests
├── enhanced_mcp_tests.zig      # MCP server unit tests
└── test_infrastructure.zig    # Test framework itself
```

### Test Naming Convention
- **Pattern**: `<component>_<operation>_<scenario>`
- **Examples**:
  - `primitive_store_basic` - Basic store operation
  - `primitive_store_memory_validation` - Memory safety validation
  - `database_init_cleanup` - Initialization and cleanup
  - `mcp_tool_parameter_validation` - Parameter validation

## Core Testing Patterns

### 1. Basic Unit Test Pattern
```zig
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

test "primitive_store_basic" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    // Setup
    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Test data
    var params_obj = std.json.ObjectMap.init(allocator);
    defer params_obj.deinit();
    try params_obj.put("key", std.json.Value{ .string = "test_key" });
    try params_obj.put("value", std.json.Value{ .string = "test_value" });

    const params = std.json.Value{ .object = params_obj };

    // Execute
    const result = try engine.executePrimitive("store", params, "test_agent");
    defer result.deinit();

    // Validate
    try testing.expect(result.value.object.get("success").?.bool == true);
    try testing.expect(result.value.object.get("stored_count").?.integer == 1);
}
```

### 2. Memory Safety Validation Pattern
```zig
test "primitive_store_memory_validation" {
    const config = MemorySafetyConfig{
        .enable_stack_traces = true,
        .poison_freed_memory = true,
    };

    const test_function = struct {
        fn run(allocator: Allocator) !void {
            var database = Database.init(allocator);
            defer database.deinit();
            
            var semantic_db = try SemanticDatabase.init(allocator, .{});
            defer semantic_db.deinit();
            
            var graph_engine = TripleHybridSearchEngine.init(allocator);
            defer graph_engine.deinit();
            
            var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
            defer engine.deinit();

            // Multiple store operations to test memory patterns
            for (0..100) |i| {
                var params_obj = std.json.ObjectMap.init(allocator);
                defer params_obj.deinit();
                
                const key = try std.fmt.allocPrint(allocator, "test_key_{}", .{i});
                defer allocator.free(key);
                
                try params_obj.put("key", std.json.Value{ .string = key });
                try params_obj.put("value", std.json.Value{ .string = "test_value" });
                
                const params = std.json.Value{ .object = params_obj };
                const result = try engine.executePrimitive("store", params, "test_agent");
                defer result.deinit();
            }
        }
    }.run;

    const result = try validateMemorySafety(testing.allocator, config, test_function);
    defer {
        var mut_result = result;
        mut_result.deinit(testing.allocator);
    }

    // Validate no memory safety issues
    try testing.expect(result.leaked_allocations == 0);
    try testing.expect(result.use_after_free_detected == 0);
    try testing.expect(result.double_free_detected == 0);
}
```

### 3. Error Handling Validation Pattern
```zig
test "primitive_store_error_handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Test cases for various error conditions
    const error_cases = [_]struct {
        params: std.json.Value,
        expected_error: anyerror,
        description: []const u8,
    }{
        .{
            .params = std.json.Value.null,
            .expected_error = error.InvalidParameters,
            .description = "null parameters",
        },
        .{
            .params = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
            .expected_error = error.MissingRequiredParameter,
            .description = "empty parameters",
        },
        // Add more error cases...
    };

    for (error_cases) |case| {
        const result = engine.executePrimitive("store", case.params, "test_agent");
        try testing.expectError(case.expected_error, result);
    }
}
```

### 4. Performance Validation Pattern
```zig
test "primitive_store_performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();

    const config = RegressionDetectionConfig{
        .latency_regression_threshold = 0.1, // 10% regression threshold
    };

    var detector = PerformanceRegressionDetector.init(allocator, config);
    defer detector.deinit();

    var database = Database.init(allocator);
    defer database.deinit();
    
    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();
    
    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();
    
    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    const benchmark_fn = struct {
        var test_engine: *PrimitiveEngine = undefined;
        
        fn run() !void {
            var params_obj = std.json.ObjectMap.init(std.heap.page_allocator);
            defer params_obj.deinit();
            
            try params_obj.put("key", std.json.Value{ .string = "benchmark_key" });
            try params_obj.put("value", std.json.Value{ .string = "benchmark_value" });
            
            const params = std.json.Value{ .object = params_obj };
            const result = try test_engine.executePrimitive("store", params, "benchmark_agent");
            defer result.deinit();
        }
    };
    benchmark_fn.test_engine = &engine;

    const result = try detector.benchmarkWithRegressionDetection("primitive_store_latency", benchmark_fn.run, 1000);

    // Validate performance targets
    try testing.expect(!result.has_regression);
    try testing.expect(result.current_measurement.latency_ms() < 1.0); // <1ms target
}
```

## Test Categories and Coverage

### 1. Core Algorithm Tests
- **Primitive Operations**: store, retrieve, search, link, transform
- **Database Operations**: CRUD, temporal queries, cleanup
- **Semantic Search**: Embedding storage, HNSW index operations
- **Graph Traversal**: FRE algorithm, path finding, dependency analysis

### 2. Data Structure Tests
- **Memory Layout**: Alignment, packing, cache efficiency
- **Serialization**: JSON parsing, binary serialization
- **Collections**: ArrayList, HashMap, custom data structures
- **Error Handling**: Graceful degradation, error propagation

### 3. Resource Management Tests
- **Memory Allocations**: Proper allocation/deallocation patterns
- **File Operations**: File I/O, directory operations
- **Network Resources**: Connection management, cleanup
- **Database Connections**: Connection pooling, transaction handling

### 4. Edge Case Testing
- **Boundary Conditions**: Empty inputs, maximum sizes, overflow
- **Invalid Inputs**: Malformed JSON, null pointers, invalid parameters
- **Resource Exhaustion**: Out of memory, disk space, file handles
- **Concurrent Access**: Thread safety, race conditions

## Memory Safety Testing

### Debug Allocator Usage
```zig
test "memory_safety_comprehensive" {
    // Use GeneralPurposeAllocator for leak detection
    var gpa = std.heap.GeneralPurposeAllocator(.{ 
        .safety = true,
        .never_unmap = true,  // Keep freed memory mapped for use-after-free detection
        .retain_metadata = true,  // Keep allocation metadata for debugging
    }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.panic("Memory leak detected in test");
        }
    }
    const allocator = gpa.allocator();

    // Test implementation
    // ...
}
```

### Arena Allocator Pattern
```zig
test "scoped_operations_memory_safety" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const backing_allocator = gpa.allocator();

    // Use arena for scoped allocations
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit(); // Automatically frees all allocations
    const allocator = arena.allocator();

    // Test operations that create many temporary allocations
    // Arena cleanup ensures no leaks from temporary allocations
}
```

## Performance Testing Integration

### Baseline Management
```zig
test "performance_baseline_management" {
    const detector = PerformanceRegressionDetector.init(testing.allocator, .{});
    defer detector.deinit();

    // Load existing baselines
    detector.loadBaseline("test_baselines.csv") catch {
        // Create new baseline if none exists
        std.debug.print("Creating new performance baseline\n");
    };

    // Run benchmark and detect regressions
    const result = try detector.benchmarkWithRegressionDetection("test_operation", testFunction, 100);
    
    // Save updated baselines
    try detector.saveBaseline("test_baselines.csv");

    try testing.expect(!result.has_regression);
}
```

### Performance Targets
- **Primitive Operations**: <1ms average latency
- **Database Queries**: <10ms for hybrid semantic+graph queries
- **Memory Allocations**: <1MB for typical operations
- **Throughput**: >1000 ops/sec for primitive operations

## Error Testing Patterns

### Comprehensive Error Coverage
```zig
test "error_handling_comprehensive" {
    const ErrorTestCase = struct {
        name: []const u8,
        setup: fn() anyerror!void,
        expected_error: anyerror,
        cleanup: fn() void,
    };

    const test_cases = [_]ErrorTestCase{
        .{
            .name = "out_of_memory",
            .setup = simulateOutOfMemory,
            .expected_error = error.OutOfMemory,
            .cleanup = restoreMemory,
        },
        .{
            .name = "invalid_json",
            .setup = provideInvalidJSON,
            .expected_error = error.InvalidJSON,
            .cleanup = cleanupJSON,
        },
        // Additional error cases...
    };

    for (test_cases) |case| {
        std.debug.print("Testing error case: {s}\n", .{case.name});
        
        try case.setup();
        defer case.cleanup();

        const result = executeOperation();
        try testing.expectError(case.expected_error, result);
    }
}
```

### Recovery Testing
```zig
test "error_recovery_validation" {
    // Test that system recovers gracefully from errors
    var system = try initializeSystem(testing.allocator);
    defer system.deinit();

    // Introduce error condition
    try induceError(&system);

    // Verify system detects error
    const status = system.getStatus();
    try testing.expect(status.hasError());

    // Verify system recovers
    try system.recover();
    const recovered_status = system.getStatus();
    try testing.expect(!recovered_status.hasError());
}
```

## Test Data Management

### Deterministic Test Data
```zig
test "deterministic_data_generation" {
    // Use fixed seed for reproducible test data
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    const test_data = generateTestData(random, 100);
    defer testing.allocator.free(test_data);

    // Test with generated data
    const result = processData(test_data);
    
    // Results should be deterministic with fixed seed
    try testing.expect(result.processed_count == 100);
}
```

### Test Fixtures
```zig
const TestFixtures = struct {
    const valid_primitive_params = 
        \\{
        \\  "key": "test_key",
        \\  "value": "test_value",
        \\  "metadata": {
        \\    "type": "test",
        \\    "timestamp": 1234567890
        \\  }
        \\}
    ;

    const invalid_primitive_params = 
        \\{
        \\  "invalid": "missing required fields"
        \\}
    ;
};
```

## Best Practices

### 1. Test Independence
- Each test is completely independent
- No shared state between tests
- Clean setup and teardown for every test

### 2. Resource Management
- Always use defer for cleanup
- Validate memory safety on every test
- Use appropriate allocators for test scenarios

### 3. Error Coverage
- Test all error paths and edge cases
- Validate error messages and codes
- Ensure graceful degradation

### 4. Performance Awareness
- Include performance validation in unit tests
- Use regression detection for critical paths
- Monitor memory usage patterns

### 5. Documentation
- Clear test names describing what is tested
- Comments explaining complex test scenarios
- Examples of expected behavior

## Debugging Failed Tests

### Memory Leak Investigation
```bash
# Run with detailed memory tracking
zig test --test-filter "failing_test" -fsanitize-thread

# Use memory debugging tools
valgrind --tool=memcheck --leak-check=full zig-out/test/failing_test
```

### Performance Investigation
```bash
# Run with performance profiling
zig test --test-filter "slow_test" -O ReleaseSafe

# Generate performance reports
perf record zig-out/test/performance_test
perf report
```

### Coverage Analysis
```bash
# Generate coverage report
zig test --test-coverage
llvm-cov show zig-out/test/test_binary -format=html > coverage.html
```

## Integration with CI/CD

### Pre-commit Validation
```bash
#!/bin/bash
# pre-commit hook script
zig fmt --check . || exit 1
zig build || exit 1
zig build test || exit 1
echo "✓ All tests passed - ready to commit"
```

### Continuous Testing
- All unit tests run on every commit
- Memory safety validation on all tests
- Performance regression detection
- Test coverage reporting
- Failure notification and analysis

## Conclusion

Unit testing in Agrama ensures comprehensive validation of individual components while maintaining high performance and memory safety standards. The multi-layered approach combining functional testing, memory safety validation, performance monitoring, and error handling provides confidence in code quality and system reliability.