# Test Categories

## Testing Hierarchy

Agrama's comprehensive testing system is organized into distinct categories, each targeting specific aspects of system functionality, performance, and reliability.

## Unit Tests

### Algorithm and Data Structure Tests

**Purpose**: Validate correctness of core algorithms and data structures

**Coverage Areas:**
- **Primitive Operations**: STORE, RETRIEVE, SEARCH, LINK, TRANSFORM
- **Temporal Storage**: Anchor+delta compression and time-based queries
- **CRDT Operations**: Conflict-free collaborative editing logic
- **Graph Algorithms**: FRE traversal and HNSW vector operations
- **Memory Pool Management**: TigerBeetle-inspired allocation optimization

**Example Test Structure:**
```zig
test "store_primitive_basic_functionality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var context = try TestContext.init(allocator);
    defer context.deinit();
    
    // Test basic store operation
    const params = try createTestJSON(allocator, .{
        .key = "test_key",
        .value = "test_value",
        .metadata = .{ .timestamp = 1234567890 }
    });
    defer params.deinit();
    
    const result = try context.primitive_engine.executePrimitive("store", params, "test_agent");
    
    // Validate successful storage
    try testing.expect(result.success == true);
    try testing.expectEqualStrings("stored", result.operation);
}
```

**Test Files:**
- `tests/primitive_tests.zig` - Core primitive operation validation
- `tests/database_tests.zig` - Temporal storage and retrieval
- `tests/semantic_tests.zig` - HNSW and embedding operations
- `tests/graph_tests.zig` - FRE algorithm correctness

### Input Validation and Security Tests

**Purpose**: Ensure robust handling of malformed and malicious inputs

**Security Test Areas:**
- **JSON Parsing Robustness**: Malformed JSON, oversized inputs, nested structures
- **Parameter Validation**: Boundary conditions, type mismatches, null values
- **Buffer Overflow Protection**: Large input handling, memory safety
- **Injection Prevention**: SQL injection, command injection, XSS prevention
- **Resource Exhaustion**: Memory limits, CPU limits, infinite loops

**Example Security Test:**
```zig
test "primitive_security_malformed_json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var context = try TestContext.init(allocator);
    defer context.deinit();
    
    const malformed_inputs = [_][]const u8{
        "{\"key\": \"value\", \"unclosed\": ",  // Unclosed JSON
        "{\"key\": null, \"value\": undefined}",  // Invalid JSON values
        "\"just_a_string\"",  // Not an object
        "{\"duplicate\": 1, \"duplicate\": 2}",  // Duplicate keys
    };
    
    for (malformed_inputs) |malformed_json| {
        // Should gracefully handle malformed input
        const result = context.primitive_engine.executeRaw(malformed_json);
        try testing.expectError(error.InvalidJSON, result);
    }
}
```

**Test Files:**
- `tests/primitive_security_tests.zig` - Input validation and security
- `tests/fuzz_test_framework.zig` - Comprehensive fuzz testing
- `tests/security_validation_tests.zig` - Attack surface validation

## Integration Tests

### MCP Server and Protocol Tests

**Purpose**: Validate Model Context Protocol implementation and AI agent integration

**MCP Test Categories:**
- **Tool Registration**: Proper tool discovery and capability reporting
- **Tool Execution**: Correct parameter handling and response formatting
- **Protocol Compliance**: Full MCP specification adherence
- **Error Handling**: Graceful error propagation and recovery
- **Real-Time Events**: WebSocket broadcasting and state synchronization

**Example MCP Integration Test:**
```zig
test "mcp_tool_integration_full_cycle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var server = try MCPServer.init(allocator);
    defer server.deinit();
    
    // Test tool registration
    const tools = try server.listTools();
    try testing.expect(tools.len >= 5); // Minimum required tools
    
    // Test read_code tool execution
    const read_params = try createTestJSON(allocator, .{
        .file_path = "test_file.zig",
        .include_context = true
    });
    defer read_params.deinit();
    
    const result = try server.executeTool("read_code", read_params);
    try testing.expect(result.success == true);
    try testing.expectEqualStrings("text", result.content_type);
}
```

### Database Integration Tests

**Purpose**: Validate end-to-end database operations with temporal and semantic functionality

**Database Integration Areas:**
- **CRUD Operations**: Create, read, update, delete with temporal tracking
- **Hybrid Queries**: Combined semantic, lexical, and graph search
- **Transaction Management**: ACID properties and consistency
- **Concurrent Access**: Multi-agent simultaneous operations
- **Data Migration**: Schema evolution and backward compatibility

**Example Database Integration Test:**
```zig
test "database_temporal_query_integration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var database = Database.init(allocator);
    defer database.deinit();
    
    // Store data with timestamps
    try database.store("key1", "value1", 1000);
    try database.store("key1", "value2", 2000);  // Update same key
    try database.store("key1", "value3", 3000);  // Another update
    
    // Query historical data
    const history = try database.getHistory("key1");
    defer allocator.free(history);
    
    try testing.expectEqual(@as(usize, 3), history.len);
    try testing.expectEqualStrings("value3", history[0].value);  // Latest first
    try testing.expectEqualStrings("value1", history[2].value);  // Oldest last
}
```

### End-to-End Scenario Tests

**Purpose**: Validate complete workflows from AI agent request to response

**E2E Test Scenarios:**
- **Multi-Agent Collaboration**: Concurrent AI agents working on shared codebase
- **Code Analysis Workflows**: Complete analysis from file read to insight generation
- **Real-Time Synchronization**: WebSocket events and state consistency
- **Error Recovery Flows**: System resilience under various failure modes
- **Observatory Integration**: Frontend-backend data flow validation

**Test Files:**
- `tests/integration_test.zig` - System integration validation
- `tests/database_integration_tests.zig` - Database operation integration
- `tests/e2e_scenario_tests.zig` - Complete workflow validation

## Performance Tests

### Benchmark Suite Integration

**Purpose**: Validate performance targets through comprehensive benchmarking

**Performance Test Areas:**
- **Latency Validation**: P50/P90/P99 response times for all operations
- **Throughput Testing**: Operations per second under various loads
- **Scalability Analysis**: Performance characteristics as data grows
- **Memory Efficiency**: Resource usage patterns and optimization
- **Regression Detection**: Automated performance degradation detection

**Performance Targets:**

| Component | P50 Target | Actual Performance | Status |
|-----------|------------|-------------------|--------|
| MCP Tools | <100ms | 0.255ms | ✅ 392× better |
| Database Storage | <10ms | 0.11ms | ✅ 90× better |
| FRE Traversal | <5ms | 2.778ms | ✅ 1.8× better |
| Hybrid Queries | <10ms | 4.91ms | ✅ 2× better |

**Example Performance Test:**
```zig
test "hybrid_query_performance_validation" {
    const config = TestConfig{
        .target_latency_ms = 10.0,
        .test_data_size = 10000,
    };
    
    var context = try TestContext.initWithData(testing.allocator, config.test_data_size);
    defer context.deinit();
    
    var latencies = std.ArrayList(f64).init(testing.allocator);
    defer latencies.deinit();
    
    // Warmup phase
    for (0..100) |_| {
        _ = try context.executeHybridQuery("test query");
    }
    
    // Measurement phase
    var timer = try std.time.Timer.start();
    for (0..1000) |_| {
        timer.reset();
        _ = try context.executeHybridQuery("performance test query");
        const latency_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try latencies.append(latency_ms);
    }
    
    const p50_latency = percentile(latencies.items, 50);
    try testing.expect(p50_latency < config.target_latency_ms);
}
```

### Memory Performance Tests

**Purpose**: Validate memory usage patterns and detect memory-related performance issues

**Memory Test Areas:**
- **Allocation Efficiency**: Memory pool utilization and overhead reduction
- **Garbage Collection Impact**: Memory cleanup performance characteristics
- **Memory Leak Detection**: Real-time leak detection without false positives
- **Peak Memory Usage**: Resource usage under maximum load conditions
- **Memory Fragmentation**: Long-running memory usage patterns

**Test Files:**
- `tests/primitive_performance_tests.zig` - Primitive operation performance
- `tests/memory_performance_tests.zig` - Memory usage validation
- `tests/performance_regression_detector.zig` - Automated regression detection

## Security Tests

### Fuzz Testing Suite

**Purpose**: Validate system robustness through comprehensive fuzz testing

**Fuzz Testing Areas:**
- **Input Fuzzing**: Malformed JSON, extreme strings, binary data
- **Parameter Fuzzing**: Invalid primitive parameters, boundary conditions
- **Memory Exhaustion**: Resource limit testing and graceful degradation
- **Concurrent Fuzzing**: Multi-threaded stress with random inputs
- **Protocol Fuzzing**: MCP protocol edge cases and malformed messages

**Fuzz Test Configuration:**
```zig
pub const FuzzConfig = struct {
    iterations: u32 = 1000,
    max_input_size: usize = 10_000,
    timeout_ms: u64 = 5000,
    enable_crash_detection: bool = true,
    enable_memory_leak_detection: bool = true,
    seed: ?u64 = null,
};
```

**Example Fuzz Test:**
```zig
test "primitive_operations_fuzz_validation" {
    const config = FuzzConfig{
        .iterations = 500,
        .max_input_size = 5000,
    };
    
    var tester = try PrimitiveFuzzTester.init(testing.allocator, config);
    defer tester.deinit();
    
    const result = try tester.fuzzPrimitiveOperations();
    defer result.deinit(testing.allocator);
    
    // Validate no crashes or hangs
    try testing.expect(result.crashes_detected == 0);
    try testing.expect(result.hangs_detected < result.iterations_completed / 20); // <5% hangs acceptable
    try testing.expect(result.unique_errors > 0); // Should discover error cases
}
```

### Security Validation Tests

**Purpose**: Ensure system security through comprehensive attack surface analysis

**Security Validation Areas:**
- **Injection Attack Prevention**: SQL, command, and script injection testing
- **Authentication and Authorization**: Access control and privilege escalation
- **Input Sanitization**: XSS prevention and data validation
- **Resource Exhaustion Protection**: DoS attack resilience
- **Memory Safety**: Buffer overflow and use-after-free prevention

**Test Files:**
- `tests/fuzz_test_framework.zig` - Comprehensive fuzz testing framework
- `tests/primitive_security_tests.zig` - Security-focused primitive testing
- `tests/security_attack_surface_tests.zig` - Attack surface analysis

## Memory Safety Tests

### Memory Leak Detection

**Purpose**: Ensure zero memory leaks through comprehensive tracking and validation

**Memory Safety Areas:**
- **Allocation Tracking**: Complete allocation and deallocation monitoring
- **Use-After-Free Detection**: Memory access validation with poison patterns
- **Double-Free Protection**: Allocation state tracking and validation
- **Buffer Overflow Detection**: Memory boundary checking and validation
- **Memory Corruption Detection**: Pattern-based corruption identification

**Example Memory Safety Test:**
```zig
test "memory_safety_comprehensive_validation" {
    const config = MemorySafetyConfig{
        .enable_use_after_free_detection = true,
        .enable_double_free_detection = true,
        .poison_freed_memory = true,
    };
    
    const test_function = struct {
        fn run(allocator: Allocator) !void {
            // Perform various memory operations
            const data = try allocator.alloc(u8, 1000);
            defer allocator.free(data);
            
            // Use the memory
            @memset(data, 42);
            
            // Test nested allocations
            var list = std.ArrayList([]u8).init(allocator);
            defer {
                for (list.items) |item| {
                    allocator.free(item);
                }
                list.deinit();
            }
            
            for (0..10) |i| {
                const item = try allocator.alloc(u8, i * 10 + 100);
                try list.append(item);
            }
        }
    }.run;
    
    const result = try validateMemorySafety(testing.allocator, config, test_function);
    defer result.deinit(testing.allocator);
    
    // Validate no memory safety issues
    try testing.expect(result.leaked_allocations == 0);
    try testing.expect(result.use_after_free_detected == 0);
    try testing.expect(result.double_free_detected == 0);
    try testing.expect(result.buffer_overflow_detected == 0);
}
```

### Concurrent Memory Safety

**Purpose**: Validate memory safety under concurrent access patterns

**Concurrent Safety Areas:**
- **Race Condition Detection**: Shared data structure access validation
- **Atomic Operation Correctness**: Memory ordering and consistency
- **Thread-Safe Allocation**: Concurrent allocator safety validation
- **Resource Contention**: Lock-free data structure validation
- **Memory Barrier Correctness**: CPU cache coherence validation

**Test Files:**
- `tests/memory_safety_validator.zig` - Core memory safety validation
- `tests/concurrent_memory_safety_tests.zig` - Multi-threaded memory safety
- `tests/memory_leak_detection_tests.zig` - Comprehensive leak detection
- `tests/memory_corruption_tests.zig` - Memory corruption detection

## Concurrent and Stress Tests

### Concurrent Operations Testing

**Purpose**: Validate system behavior under concurrent access patterns

**Concurrent Test Areas:**
- **Multi-Agent Operations**: Simultaneous AI agent interactions
- **Database Concurrency**: Concurrent read/write operations
- **Resource Contention**: Lock contention and performance impact
- **Race Condition Detection**: Shared state access validation
- **Deadlock Prevention**: Resource acquisition ordering validation

**Example Concurrent Test:**
```zig
test "concurrent_primitive_operations" {
    const config = ConcurrentTestConfig{
        .num_threads = 8,
        .operations_per_thread = 1000,
        .test_duration_seconds = 10,
    };
    
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    const results = try runConcurrentTest(testing.allocator, config, context);
    defer {
        for (results) |*result| {
            result.deinit(testing.allocator);
        }
        testing.allocator.free(results);
    }
    
    // Validate no races or deadlocks
    for (results) |result| {
        try testing.expect(result.races_detected == 0);
        try testing.expect(result.deadlocks_detected == 0);
        try testing.expect(result.passed == true);
    }
}
```

### Stress Testing

**Purpose**: Validate system stability under extreme load conditions

**Stress Test Areas:**
- **High Load Scenarios**: Maximum throughput and capacity testing
- **Resource Exhaustion**: Behavior under memory/CPU/disk pressure
- **Long-Running Operations**: System stability over extended periods
- **Peak Usage Simulation**: Realistic maximum usage scenarios
- **Graceful Degradation**: Performance characteristics under overload

**Test Files:**
- `tests/concurrent_stress_tests.zig` - Multi-threaded stress testing
- `tests/load_testing_framework.zig` - High-load scenario testing
- `tests/resource_exhaustion_tests.zig` - Resource limit testing
- `tests/stability_tests.zig` - Long-running stability validation

## Test Execution Strategy

### Test Categorization by Priority

**P0 (Critical - Always Run):**
- Core primitive functionality
- Memory safety validation
- Basic integration tests
- Performance regression detection

**P1 (Important - CI/CD Required):**
- Comprehensive integration tests
- Security validation
- Concurrent operations testing
- Full benchmark suite

**P2 (Comprehensive - Pre-Release):**
- Extended fuzz testing
- Stress testing
- Long-running stability tests
- Observatory integration

**P3 (Extended - Periodic):**
- Performance optimization validation
- Edge case exploration
- Compatibility testing
- Documentation example validation

### Test Execution Commands

```bash
# Priority-based execution
zig build test                    # P0 critical tests
zig build test-all               # P0-P1 comprehensive suite
zig build test-extended          # P0-P2 pre-release validation
zig build test-full             # P0-P3 complete testing

# Category-specific execution
zig build test-unit             # Unit tests only
zig build test-integration      # Integration tests only
zig build test-performance      # Performance tests only
zig build test-security         # Security tests only
zig build test-memory-safety    # Memory safety only
zig build test-concurrent       # Concurrent tests only

# Specialized execution
zig build test-fuzz             # Fuzz testing suite
zig build test-regression       # Performance regression
zig build validate              # Full performance validation
```

The comprehensive test categorization ensures thorough validation across all system aspects while providing flexibility for different testing scenarios and development phases.