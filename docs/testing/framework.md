# Test Framework

## Zig Testing Foundation

Agrama's testing framework is built on Zig's powerful native testing capabilities, enhanced with custom infrastructure designed specifically for high-performance AI systems and temporal knowledge graphs.

## Core Testing Infrastructure

### Test Infrastructure System

The unified test infrastructure (`tests/test_infrastructure.zig`) orchestrates all testing activities with comprehensive tracking and reporting:

```zig
pub const TestInfrastructureConfig = struct {
    enable_memory_leak_detection: bool = true,
    enable_performance_regression_detection: bool = true,
    enable_concurrent_testing: bool = true,
    enable_fuzz_testing: bool = true,
    enable_error_recovery_testing: bool = true,
    
    // Performance settings
    regression_threshold_percent: f64 = 5.0,
    performance_timeout_ms: u64 = 30000,
    
    // Coverage settings
    target_coverage_percent: f64 = 90.0,
    generate_coverage_report: bool = true,
};
```

### Memory Safety Validation

The Memory Safety Validator (`tests/memory_safety_validator.zig`) provides comprehensive memory safety checking:

**Features:**
- **Real-time leak detection** without arena allocator masking
- **Use-after-free detection** with memory poisoning
- **Double-free protection** with allocation state tracking
- **Buffer overflow detection** with memory pattern validation
- **Stack trace capture** for leak source identification

**Usage Pattern:**
```zig
const config = MemorySafetyConfig{
    .enable_stack_traces = true,
    .poison_freed_memory = true,
    .poison_value = 0xDE, // "DEAD" pattern
};

const result = try validateMemorySafety(allocator, config, testFunction);
defer result.deinit(allocator);

try testing.expect(result.leaked_allocations == 0);
try testing.expect(result.use_after_free_detected == 0);
```

### Fuzz Testing Framework

The Fuzz Testing Framework (`tests/fuzz_test_framework.zig`) provides structured robustness validation:

**Capabilities:**
- **Malformed JSON generation** with realistic edge cases
- **Extreme string patterns** including Unicode boundary testing
- **Memory exhaustion scenarios** with graceful recovery validation
- **Primitive parameter fuzzing** with comprehensive error coverage
- **Timeout and hang detection** for infinite loop prevention

**Input Generation Strategies:**
```zig
pub const FuzzInputGenerator = struct {
    // Generate malformed JSON with realistic patterns
    pub fn generateMalformedJSON(self: *FuzzInputGenerator, max_size: usize) ![]const u8;
    
    // Generate extreme string inputs for boundary testing
    pub fn generateExtremeString(self: *FuzzInputGenerator, max_size: usize) ![]const u8;
    
    // Generate malformed primitive parameters
    pub fn generateMalformedPrimitiveParams(self: *FuzzInputGenerator) !std.json.Value;
};
```

## Zig Testing Patterns

### Standard Test Structure

Agrama follows consistent patterns for all test implementations:

```zig
test "component_functionality_description" {
    // Setup: Create test allocator and resources
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Initialize component under test
    var component = try Component.init(allocator);
    defer component.deinit();
    
    // Execute: Perform operations under test
    const result = try component.performOperation(test_input);
    
    // Verify: Assert expected outcomes
    try testing.expect(result.success == true);
    try testing.expectEqual(@as(u32, 42), result.value);
    try testing.expectError(error.InvalidInput, component.performBadOperation());
}
```

### Memory Management in Tests

**Arena Allocator Pattern** (Recommended for most tests):
```zig
test "memory_safe_operation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit(); // Automatic cleanup
    const allocator = arena.allocator();
    
    // All allocations automatically freed on arena.deinit()
    const data = try allocator.alloc(u8, 1000);
    // No explicit free required
}
```

**Debug Allocator Pattern** (For leak detection):
```zig
test "leak_detection_validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();
    
    // Explicit allocation and deallocation required
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data); // Required for leak prevention
}
```

### Error Testing Patterns

**Expected Error Testing:**
```zig
test "error_handling_validation" {
    // Test specific error conditions
    try testing.expectError(error.OutOfMemory, functionThatShouldFailOnOOM());
    try testing.expectError(error.InvalidInput, functionWithBadInput());
    
    // Test error recovery
    const result = functionThatMightFail() catch |err| switch (err) {
        error.RecoverableError => .{ .success = false, .recovered = true },
        else => return err,
    };
    
    try testing.expect(result.recovered == true);
}
```

### Performance Testing Integration

**Benchmark-Style Testing:**
```zig
test "performance_validation" {
    const iterations = 1000;
    var timer = try std.time.Timer.start();
    
    // Warmup phase
    for (0..100) |_| {
        _ = try performOperation();
    }
    
    // Measurement phase
    timer.reset();
    for (0..iterations) |_| {
        _ = try performOperation();
    }
    
    const elapsed_ns = timer.read();
    const avg_latency_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(iterations));
    
    // Validate against performance target
    try testing.expect(avg_latency_ms < 5.0); // <5ms target
}
```

## Custom Test Utilities

### Test Context Helper

The test framework provides utilities for common testing scenarios:

```zig
pub const TestContext = struct {
    allocator: Allocator,
    database: *Database,
    semantic_db: *SemanticDatabase,
    primitive_engine: *PrimitiveEngine,
    
    pub fn init(allocator: Allocator) !TestContext {
        const database = try allocator.create(Database);
        database.* = Database.init(allocator);
        
        const semantic_db = try allocator.create(SemanticDatabase);
        semantic_db.* = try SemanticDatabase.init(allocator, .{});
        
        const primitive_engine = try allocator.create(PrimitiveEngine);
        primitive_engine.* = try PrimitiveEngine.init(allocator, database, semantic_db, null);
        
        return TestContext{
            .allocator = allocator,
            .database = database,
            .semantic_db = semantic_db,
            .primitive_engine = primitive_engine,
        };
    }
    
    pub fn deinit(self: *TestContext) void {
        self.primitive_engine.deinit();
        self.semantic_db.deinit();
        self.database.deinit();
        
        self.allocator.destroy(self.primitive_engine);
        self.allocator.destroy(self.semantic_db);
        self.allocator.destroy(self.database);
    }
};
```

### JSON Test Utilities

Helper functions for JSON-based testing:

```zig
pub fn createTestJSON(allocator: Allocator, data: anytype) !std.json.Value {
    const json_string = try std.json.stringifyAlloc(allocator, data, .{});
    defer allocator.free(json_string);
    
    return try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
}

pub fn expectJSONEqual(expected: std.json.Value, actual: std.json.Value) !void {
    // Custom JSON comparison logic
    switch (expected) {
        .string => |expected_str| {
            try testing.expectEqualStrings(expected_str, actual.string);
        },
        .integer => |expected_int| {
            try testing.expectEqual(expected_int, actual.integer);
        },
        // ... additional type handling
    }
}
```

## Build System Integration

### Test Execution Targets

The build system (`build.zig`) provides comprehensive test execution targets:

```bash
# Core test commands
zig build test                    # Standard unit tests
zig build test-all               # Comprehensive test suite
zig build test-infrastructure    # Test infrastructure validation

# Specialized test categories  
zig build test-primitives        # Primitive operation tests
zig build test-enhanced-mcp      # MCP server comprehensive tests
zig build test-concurrent        # Concurrent stress testing
zig build test-fuzz             # Fuzz testing suite

# Performance and validation
zig build validate              # Optimized performance validation
zig build bench-regression      # Performance regression detection
```

### Test Target Configuration

Build system test target pattern:
```zig
// Individual test suite
const primitive_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("tests/primitive_tests.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
primitive_tests.root_module.addImport("agrama_lib", lib_mod);

const run_primitive_tests = b.addRunArtifact(primitive_tests);
const test_primitives_step = b.step("test-primitives", "Run primitive tests");
test_primitives_step.dependOn(&run_primitive_tests.step);
```

## Concurrent Testing Framework

### Thread Safety Validation

The concurrent testing framework (`tests/concurrent_stress_tests.zig`) validates multi-threaded safety:

**Configuration:**
```zig
pub const ConcurrentTestConfig = struct {
    num_threads: u32 = 8,
    operations_per_thread: u32 = 1000,
    test_duration_seconds: u32 = 10,
    enable_race_detection: bool = true,
    enable_deadlock_detection: bool = true,
};
```

**Test Scenarios:**
- **Concurrent primitive operations** across multiple threads
- **Race condition detection** in shared data structures
- **Deadlock prevention** in resource acquisition
- **Memory safety under concurrency** with atomic operations
- **Performance degradation analysis** under concurrent load

### Stress Testing Patterns

```zig
fn concurrentOperationTest(config: ConcurrentTestConfig) !ConcurrentTestResult {
    var threads: [config.num_threads]std.Thread = undefined;
    var results: [config.num_threads]ThreadResult = undefined;
    
    // Launch worker threads
    for (&threads, &results, 0..) |*thread, *result, i| {
        thread.* = try std.Thread.spawn(.{}, workerFunction, .{ i, config, result });
    }
    
    // Wait for completion and collect results
    for (threads) |thread| {
        thread.join();
    }
    
    // Analyze results for races and performance
    return analyzeResults(results);
}
```

## Error Recovery Testing

### Resilience Validation

The framework includes comprehensive error recovery testing:

**Scenarios Tested:**
- **Out of memory conditions** with graceful degradation
- **Network timeouts** with automatic retry mechanisms
- **Malformed input handling** with proper error propagation
- **Resource exhaustion** with cleanup and recovery
- **Partial failure scenarios** with rollback mechanisms

**Recovery Validation Pattern:**
```zig
test "error_recovery_comprehensive" {
    const recovery_scenarios = [_]struct { error_type: anyerror, should_recover: bool }{
        .{ .error_type = error.OutOfMemory, .should_recover = true },
        .{ .error_type = error.InvalidInput, .should_recover = true },
        .{ .error_type = error.NetworkTimeout, .should_recover = true },
    };
    
    for (recovery_scenarios) |scenario| {
        const result = systemUnderTest.performOperationWithRecovery() catch |err| {
            if (err == scenario.error_type and scenario.should_recover) {
                continue; // Expected recoverable error
            }
            return err; // Unexpected error
        };
        
        // Validate successful recovery
        try testing.expect(result.recovered_successfully);
    }
}
```

## Performance Regression Framework

### Automated Performance Tracking

The performance regression detector (`tests/performance_regression_detector.zig`) provides automated performance monitoring:

**Features:**
- **Baseline comparison** against historical performance data
- **Statistical analysis** with confidence intervals
- **Regression alerting** with configurable thresholds
- **Performance trend analysis** over time
- **Benchmark result archival** for historical comparison

**Usage:**
```zig
const detector = PerformanceRegressionDetector.init(allocator, .{
    .baseline_file = "benchmarks/baseline.json",
    .regression_threshold_percent = 5.0,
    .confidence_level = 0.95,
});

const result = try detector.compareToBaseline(current_results);
if (result.regressions_detected > 0) {
    return error.PerformanceRegression;
}
```

## Best Practices

### Test Organization
- **One test file per module** for clear organization
- **Descriptive test names** indicating functionality and expected outcome
- **Grouped related tests** using nested test blocks where appropriate
- **Consistent setup/teardown** patterns across all tests

### Memory Management
- **Use arena allocators** for automatic cleanup in most tests
- **Debug allocator for leak detection** when memory safety is critical
- **Explicit resource cleanup** with defer statements
- **Memory usage validation** for performance-critical components

### Error Handling
- **Test both success and failure paths** comprehensively
- **Validate error messages** and error types
- **Test error recovery mechanisms** and graceful degradation
- **Include edge cases** and boundary conditions

### Performance Testing
- **Include warmup phases** for accurate measurement
- **Use statistical analysis** rather than single measurements
- **Test with realistic data** that matches production scenarios
- **Validate against specific targets** rather than arbitrary thresholds

The Agrama test framework provides the foundation for comprehensive validation of all system components, ensuring production readiness through rigorous testing methodologies and comprehensive coverage across all critical system aspects.