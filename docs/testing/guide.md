# Testing Guide

## Writing Effective Tests

This guide provides best practices and patterns for writing high-quality tests in the Agrama system, ensuring comprehensive coverage, maintainability, and reliability.

## Test Design Principles

### 1. Clear Test Intent

Every test should have a clear, single purpose that is immediately obvious from its name and structure:

```zig
// ❌ Poor: Unclear intent
test "database_test" {
    // What aspect of the database is being tested?
}

// ✅ Good: Clear, specific intent
test "database_store_operation_persists_data_with_timestamp" {
    // Clear what behavior is being validated
}
```

### 2. Comprehensive Coverage

Tests should cover all critical paths, including success cases, error conditions, and edge cases:

```zig
test "primitive_store_comprehensive_coverage" {
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    // Success case: Normal operation
    {
        const params = try createStoreParams("key1", "value1");
        defer params.deinit();
        const result = try context.primitive_engine.executePrimitive("store", params, "agent1");
        try testing.expect(result.success);
    }
    
    // Error case: Invalid parameters
    {
        const invalid_params = try createInvalidParams();
        defer invalid_params.deinit();
        try testing.expectError(error.InvalidInput, 
            context.primitive_engine.executePrimitive("store", invalid_params, "agent1"));
    }
    
    // Edge case: Empty key
    {
        const empty_key_params = try createStoreParams("", "value");
        defer empty_key_params.deinit();
        try testing.expectError(error.EmptyKey,
            context.primitive_engine.executePrimitive("store", empty_key_params, "agent1"));
    }
    
    // Edge case: Very large value
    {
        const large_value = try testing.allocator.alloc(u8, 10_000_000);
        defer testing.allocator.free(large_value);
        @memset(large_value, 'A');
        
        const large_params = try createStoreParams("large_key", large_value);
        defer large_params.deinit();
        const result = try context.primitive_engine.executePrimitive("store", large_params, "agent1");
        try testing.expect(result.success); // Should handle large data
    }
}
```

### 3. Isolation and Independence

Tests should be completely independent and not rely on external state or other tests:

```zig
// ❌ Poor: Depends on external state
test "database_retrieve_existing_data" {
    // Assumes data was stored by another test
    const result = try database.retrieve("some_key");
    try testing.expect(result != null);
}

// ✅ Good: Self-contained and isolated
test "database_retrieve_returns_stored_data" {
    var database = Database.init(testing.allocator);
    defer database.deinit();
    
    // Setup: Store data within this test
    try database.store("test_key", "test_value", 12345);
    
    // Execute: Retrieve the data
    const result = try database.retrieve("test_key");
    
    // Verify: Check the result
    try testing.expectEqualStrings("test_value", result.?.value);
    try testing.expectEqual(@as(i64, 12345), result.?.timestamp);
}
```

## Memory Management Best Practices

### Arena Allocator Pattern (Recommended)

Use arena allocators for automatic cleanup in most test scenarios:

```zig
test "arena_allocator_pattern" {
    // Arena automatically cleans up all allocations
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit(); // All allocations freed here
    const allocator = arena.allocator();
    
    // All allocations use arena allocator
    var context = try TestContext.init(allocator);
    // No explicit deinit needed - arena handles cleanup
    
    const test_data = try allocator.alloc(u8, 1000);
    // No explicit free needed - arena handles cleanup
    
    // Test logic here...
}
```

### Debug Allocator for Leak Detection

Use debug allocators when validating memory safety:

```zig
test "memory_leak_validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        // Test fails if leaks detected
        try testing.expect(leaked != .leak);
    }
    const allocator = gpa.allocator();
    
    // Explicit allocation and deallocation required
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data); // Required to prevent leak
    
    // Test logic using data...
}
```

### Memory-Intensive Test Pattern

For tests involving large allocations or memory stress:

```zig
test "memory_intensive_operation" {
    // Use page allocator for large allocations
    const allocator = std.heap.page_allocator;
    
    // Track memory usage
    const initial_memory = getCurrentMemoryUsage();
    defer {
        const final_memory = getCurrentMemoryUsage();
        const memory_delta = final_memory - initial_memory;
        // Validate memory usage is within expected bounds
        try testing.expect(memory_delta < 100 * 1024 * 1024); // <100MB
    }
    
    // Test large allocation scenarios
    const large_buffer = try allocator.alloc(u8, 50 * 1024 * 1024); // 50MB
    defer allocator.free(large_buffer);
    
    // Test logic...
}
```

## Performance Testing Patterns

### Latency Measurement

Standard pattern for measuring operation latency:

```zig
test "operation_latency_measurement" {
    const iterations = 1000;
    const target_latency_ms = 5.0;
    
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    var latencies = std.ArrayList(f64).init(testing.allocator);
    defer latencies.deinit();
    
    // Warmup phase (critical for accurate measurements)
    for (0..100) |_| {
        _ = try context.performOperation();
    }
    
    // Measurement phase
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        timer.reset();
        _ = try context.performOperation();
        const latency_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try latencies.append(latency_ms);
    }
    
    // Statistical analysis
    const p50_latency = percentile(latencies.items, 50);
    const p90_latency = percentile(latencies.items, 90);
    const p99_latency = percentile(latencies.items, 99);
    
    // Validate against targets
    try testing.expect(p50_latency < target_latency_ms);
    
    // Log performance metrics for tracking
    std.log.info("P50: {:.3}ms, P90: {:.3}ms, P99: {:.3}ms", .{ p50_latency, p90_latency, p99_latency });
}
```

### Throughput Testing

Pattern for measuring operations per second:

```zig
test "operation_throughput_measurement" {
    const test_duration_seconds = 10;
    const min_throughput_ops_per_sec = 1000;
    
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    const start_time = std.time.timestamp();
    var operations_completed: u64 = 0;
    
    // Run operations for specified duration
    while (std.time.timestamp() - start_time < test_duration_seconds) {
        _ = try context.performOperation();
        operations_completed += 1;
    }
    
    const actual_duration = std.time.timestamp() - start_time;
    const throughput = @as(f64, @floatFromInt(operations_completed)) / @as(f64, @floatFromInt(actual_duration));
    
    try testing.expect(throughput >= min_throughput_ops_per_sec);
    
    std.log.info("Throughput: {:.1} ops/sec ({} ops in {}s)", .{ throughput, operations_completed, actual_duration });
}
```

## Error Handling Validation

### Expected Error Testing

Test that operations fail appropriately under invalid conditions:

```zig
test "error_handling_comprehensive" {
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    // Test specific error conditions
    const error_scenarios = [_]struct {
        description: []const u8,
        input: []const u8,
        expected_error: anyerror,
    }{
        .{ .description = "Empty JSON", .input = "", .expected_error = error.InvalidJSON },
        .{ .description = "Malformed JSON", .input = "{invalid", .expected_error = error.InvalidJSON },
        .{ .description = "Missing required field", .input = "{\"value\": \"test\"}", .expected_error = error.MissingKey },
        .{ .description = "Invalid data type", .input = "{\"key\": 123, \"value\": \"test\"}", .expected_error = error.InvalidType },
    };
    
    for (error_scenarios) |scenario| {
        const result = context.processInput(scenario.input);
        try testing.expectError(scenario.expected_error, result);
        
        std.log.info("✓ {s}: Expected error {}", .{ scenario.description, scenario.expected_error });
    }
}
```

### Error Recovery Testing

Validate that systems recover gracefully from error conditions:

```zig
test "error_recovery_validation" {
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    // Cause an error condition
    const error_result = context.performOperationWithError();
    try testing.expectError(error.SimulatedFailure, error_result);
    
    // Verify system state is still valid
    try testing.expect(context.isHealthy());
    
    // Verify normal operations can continue
    const recovery_result = try context.performNormalOperation();
    try testing.expect(recovery_result.success);
    
    // Verify system fully recovered
    try testing.expect(context.isFullyOperational());
}
```

## Test Data Management

### Realistic Test Data Generation

Create test data that matches production characteristics:

```zig
fn generateRealisticTestData(allocator: Allocator, count: usize) ![]TestRecord {
    var records = try allocator.alloc(TestRecord, count);
    
    var prng = std.rand.DefaultPrng.init(12345); // Fixed seed for reproducibility
    const random = prng.random();
    
    for (records, 0..) |*record, i| {
        // Generate realistic key distribution (Zipfian)
        const key_id = generateZipfianId(random, count);
        record.key = try std.fmt.allocPrint(allocator, "key_{}", .{key_id});
        
        // Generate realistic value sizes (log-normal distribution)
        const value_size = generateLogNormalSize(random, 100, 1000);
        record.value = try generateRandomString(allocator, value_size);
        
        // Generate realistic timestamp (recent with some spread)
        const base_timestamp = std.time.timestamp();
        record.timestamp = base_timestamp - random.intRangeAtMost(i64, 0, 7 * 24 * 60 * 60); // Within last week
        
        // Generate realistic metadata
        record.metadata = try generateRealisticMetadata(allocator, random);
    }
    
    return records;
}
```

### Test Data Cleanup

Ensure proper cleanup of test data:

```zig
const TestDataSet = struct {
    allocator: Allocator,
    records: []TestRecord,
    
    pub fn init(allocator: Allocator, count: usize) !TestDataSet {
        return TestDataSet{
            .allocator = allocator,
            .records = try generateRealisticTestData(allocator, count),
        };
    }
    
    pub fn deinit(self: *TestDataSet) void {
        for (self.records) |*record| {
            self.allocator.free(record.key);
            self.allocator.free(record.value);
            // Clean up metadata if needed
        }
        self.allocator.free(self.records);
    }
};

test "test_data_management" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var test_data = try TestDataSet.init(allocator, 1000);
    defer test_data.deinit(); // Proper cleanup
    
    // Use test_data.records in tests...
}
```

## Concurrent Testing Patterns

### Thread Safety Validation

Test operations under concurrent access:

```zig
test "concurrent_access_safety" {
    const num_threads = 8;
    const operations_per_thread = 1000;
    
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    var threads: [num_threads]std.Thread = undefined;
    var results: [num_threads]ThreadResult = undefined;
    
    // Launch worker threads
    for (&threads, &results, 0..) |*thread, *result, i| {
        const thread_config = ThreadConfig{
            .thread_id = i,
            .operations_count = operations_per_thread,
            .context = &context,
        };
        
        thread.* = try std.Thread.spawn(.{}, workerThreadFunction, .{ thread_config, result });
    }
    
    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }
    
    // Analyze results
    var total_operations: u64 = 0;
    var total_errors: u64 = 0;
    
    for (results) |result| {
        total_operations += result.operations_completed;
        total_errors += result.errors_encountered;
        
        // No thread should have detected data races
        try testing.expect(result.races_detected == 0);
    }
    
    // Verify expected total operations
    try testing.expectEqual(num_threads * operations_per_thread, total_operations);
    
    // Verify system consistency after concurrent operations
    try testing.expect(context.isConsistent());
}
```

### Race Condition Detection

Use patterns to detect race conditions:

```zig
test "race_condition_detection" {
    var shared_counter = std.atomic.Value(u64).init(0);
    const num_threads = 16;
    const increments_per_thread = 10000;
    
    var threads: [num_threads]std.Thread = undefined;
    
    // Launch threads that increment shared counter
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, struct {
            fn incrementCounter(counter: *std.atomic.Value(u64), count: u32) void {
                for (0..count) |_| {
                    _ = counter.fetchAdd(1, .monotonic);
                }
            }
        }.incrementCounter, .{ &shared_counter, increments_per_thread });
    }
    
    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
    
    // Verify no increments were lost (would indicate race condition)
    const final_value = shared_counter.load(.monotonic);
    const expected_value = num_threads * increments_per_thread;
    
    try testing.expectEqual(expected_value, final_value);
}
```

## Debugging Failing Tests

### Comprehensive Test Output

Provide detailed information when tests fail:

```zig
test "detailed_failure_reporting" {
    var context = try TestContext.init(testing.allocator);
    defer context.deinit();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected_output: []const u8,
        description: []const u8,
    }{
        .{ .input = "test1", .expected_output = "result1", .description = "Basic functionality" },
        .{ .input = "test2", .expected_output = "result2", .description = "Edge case handling" },
        .{ .input = "test3", .expected_output = "result3", .description = "Error recovery" },
    };
    
    for (test_cases, 0..) |test_case, i| {
        const actual_output = try context.processInput(test_case.input);
        
        if (!std.mem.eql(u8, test_case.expected_output, actual_output)) {
            // Provide detailed failure information
            std.log.err("Test case {} failed: {s}", .{ i, test_case.description });
            std.log.err("  Input: '{s}'", .{test_case.input});
            std.log.err("  Expected: '{s}'", .{test_case.expected_output});
            std.log.err("  Actual: '{s}'", .{actual_output});
            std.log.err("  Context state: {}", .{context.getDebugInfo()});
            
            return error.TestFailed;
        }
    }
}
```

### Test State Inspection

Provide utilities for inspecting test state:

```zig
const TestContext = struct {
    // ... other fields
    
    pub fn getDebugInfo(self: *TestContext) DebugInfo {
        return DebugInfo{
            .database_records = self.database.getRecordCount(),
            .active_connections = self.connection_count,
            .memory_usage_bytes = self.getCurrentMemoryUsage(),
            .last_operation_timestamp = self.last_operation_timestamp,
        };
    }
    
    pub fn validateInternalConsistency(self: *TestContext) !void {
        // Check database integrity
        if (!self.database.isConsistent()) {
            return error.DatabaseInconsistent;
        }
        
        // Check memory pools
        if (!self.memory_pools.isValid()) {
            return error.MemoryPoolCorrupted;
        }
        
        // Check semantic database
        if (!self.semantic_db.isConsistent()) {
            return error.SemanticDatabaseInconsistent;
        }
    }
};
```

## Performance Test Interpretation

### Statistical Analysis

Proper interpretation of performance test results:

```zig
fn analyzePerformanceResults(latencies: []f64) PerformanceAnalysis {
    // Sort for percentile calculation
    std.sort.heap(f64, latencies, {}, std.sort.asc(f64));
    
    return PerformanceAnalysis{
        .mean = calculateMean(latencies),
        .median = latencies[latencies.len / 2],
        .p90 = latencies[@intFromFloat(@as(f64, @floatFromInt(latencies.len)) * 0.9)],
        .p99 = latencies[@intFromFloat(@as(f64, @floatFromInt(latencies.len)) * 0.99)],
        .p999 = latencies[@intFromFloat(@as(f64, @floatFromInt(latencies.len)) * 0.999)],
        .min = latencies[0],
        .max = latencies[latencies.len - 1],
        .standard_deviation = calculateStdDev(latencies),
        .coefficient_of_variation = calculateCV(latencies),
    };
}
```

### Performance Regression Detection

Detect performance changes over time:

```zig
test "performance_regression_detection" {
    const baseline_p50_ms = 2.5;
    const regression_threshold_percent = 5.0;
    
    // Run current performance test
    const current_results = try runPerformanceTest();
    defer current_results.deinit();
    
    const current_p50 = current_results.p50_latency_ms;
    const regression_percent = ((current_p50 - baseline_p50_ms) / baseline_p50_ms) * 100.0;
    
    if (regression_percent > regression_threshold_percent) {
        std.log.err("PERFORMANCE REGRESSION DETECTED:");
        std.log.err("  Baseline P50: {:.3}ms", .{baseline_p50_ms});
        std.log.err("  Current P50: {:.3}ms", .{current_p50});
        std.log.err("  Regression: {:.1}%", .{regression_percent});
        return error.PerformanceRegression;
    }
    
    std.log.info("✓ Performance within acceptable range: {:.3}ms ({:.1}% vs baseline)", .{ current_p50, regression_percent });
}
```

## Best Practices Summary

### Do's
- **Write descriptive test names** that clearly indicate what is being tested
- **Use arena allocators** for automatic memory cleanup in most tests
- **Test both success and failure paths** comprehensively
- **Include performance validation** in time-critical operations
- **Provide detailed failure information** for debugging
- **Use realistic test data** that matches production characteristics
- **Validate system consistency** after operations
- **Include warmup phases** in performance tests

### Don'ts
- **Don't create interdependent tests** that rely on execution order
- **Don't ignore memory leaks** even in test code
- **Don't skip edge cases** and boundary conditions
- **Don't use only average latencies** - include percentiles
- **Don't forget to test error recovery** mechanisms
- **Don't use unrealistic test data** that hides performance issues
- **Don't skip concurrent testing** for shared resources
- **Don't ignore test failures** in CI/CD pipelines

### Development Workflow Integration

```bash
# Always run before committing
zig fmt . && zig build && zig build test

# Extended validation before major changes
zig build test-all && zig build validate

# Performance validation before releases
zig build bench-regression && zig build validate
```

Following these guidelines ensures that Agrama's test suite maintains high quality, provides reliable validation, and supports confident development and deployment of production-ready temporal knowledge graph database functionality.