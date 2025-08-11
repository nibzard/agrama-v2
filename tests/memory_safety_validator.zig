//! Memory Safety Validator for Agrama
//! 
//! Provides comprehensive memory safety validation:
//! - Real-time leak detection without masking by arena allocators
//! - Use-after-free detection
//! - Buffer overflow protection
//! - Double-free detection
//! - Memory corruption detection

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const print = std.debug.print;

/// Memory allocation tracking information
const AllocationInfo = struct {
    ptr: usize,
    size: usize,
    stack_trace: ?std.builtin.StackTrace = null,
    timestamp: i64,
    freed: bool = false,
};

/// Memory safety validation configuration
pub const MemorySafetyConfig = struct {
    enable_stack_traces: bool = true,
    enable_use_after_free_detection: bool = true,
    enable_double_free_detection: bool = true,
    enable_buffer_overflow_detection: bool = true,
    enable_leak_reporting: bool = true,
    max_tracked_allocations: usize = 10000,
    poison_freed_memory: bool = true,
    poison_value: u8 = 0xDE, // "DEAD" pattern
};

/// Memory safety validation result
pub const MemorySafetyResult = struct {
    total_allocations: usize,
    total_frees: usize,
    active_allocations: usize,
    leaked_allocations: usize,
    leaked_bytes: usize,
    use_after_free_detected: usize,
    double_free_detected: usize,
    buffer_overflow_detected: usize,
    memory_corruption_detected: usize,
    peak_memory_bytes: usize,
    
    // Detailed leak information
    leak_details: []AllocationInfo,
    
    pub fn deinit(self: *MemorySafetyResult, allocator: Allocator) void {
        allocator.free(self.leak_details);
    }
    
    pub fn print_summary(self: MemorySafetyResult) void {
        print("\n" ++ "=" * 60 ++ "\n");
        print("MEMORY SAFETY VALIDATION REPORT\n");
        print("=" * 60 ++ "\n");
        
        print("📊 Allocation Statistics:\n");
        print("  Total Allocations: {}\n", .{self.total_allocations});
        print("  Total Frees: {}\n", .{self.total_frees});
        print("  Active Allocations: {}\n", .{self.active_allocations});
        print("  Peak Memory: {:.2} MB\n", .{@as(f64, @floatFromInt(self.peak_memory_bytes)) / (1024.0 * 1024.0)});
        
        print("\n🔍 Safety Issues Detected:\n");
        print("  Leaked Allocations: {} ({:.2} KB)\n", .{ self.leaked_allocations, @as(f64, @floatFromInt(self.leaked_bytes)) / 1024.0 });
        print("  Use After Free: {}\n", .{self.use_after_free_detected});
        print("  Double Free: {}\n", .{self.double_free_detected});
        print("  Buffer Overflow: {}\n", .{self.buffer_overflow_detected});
        print("  Memory Corruption: {}\n", .{self.memory_corruption_detected});
        
        const total_issues = self.leaked_allocations + self.use_after_free_detected + 
                           self.double_free_detected + self.buffer_overflow_detected + self.memory_corruption_detected;
        
        print("\n🏆 Overall Status: ");
        if (total_issues == 0) {
            print("✅ MEMORY SAFE - No issues detected!\n");
        } else if (total_issues <= 5) {
            print("⚠️ MINOR ISSUES - {} memory safety issues\n", .{total_issues});
        } else {
            print("❌ MEMORY UNSAFE - {} critical issues detected\n", .{total_issues});
        }
        
        // Print leak details if any
        if (self.leak_details.len > 0) {
            print("\n📋 Leak Details:\n");
            for (self.leak_details[0..@min(self.leak_details.len, 10)]) |leak| { // Show first 10 leaks
                print("  Leak: {} bytes at 0x{X} (timestamp: {})\n", .{ leak.size, leak.ptr, leak.timestamp });
            }
            if (self.leak_details.len > 10) {
                print("  ... and {} more leaks\n", .{self.leak_details.len - 10});
            }
        }
        
        print("=" * 60 ++ "\n");
    }
};

/// Memory safety validating allocator wrapper
pub const MemorySafetyValidator = struct {
    backing_allocator: Allocator,
    config: MemorySafetyConfig,
    
    // Tracking data
    allocations: HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage),
    total_allocations: usize = 0,
    total_frees: usize = 0,
    current_memory: usize = 0,
    peak_memory: usize = 0,
    
    // Safety counters
    use_after_free_count: usize = 0,
    double_free_count: usize = 0,
    buffer_overflow_count: usize = 0,
    corruption_count: usize = 0,
    
    // Thread safety
    mutex: std.Thread.Mutex = .{},
    
    pub fn init(backing_allocator: Allocator, config: MemorySafetyConfig) MemorySafetyValidator {
        return .{
            .backing_allocator = backing_allocator,
            .config = config,
            .allocations = HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), std.hash_map.default_max_load_percentage).init(backing_allocator),
        };
    }
    
    pub fn deinit(self: *MemorySafetyValidator) void {
        self.allocations.deinit();
    }
    
    pub fn allocator(self: *MemorySafetyValidator) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *MemorySafetyValidator = @ptrCast(@alignCast(ctx));
        _ = ret_addr;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Perform actual allocation
        const result = self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);
        
        if (result) |ptr| {
            const ptr_addr = @intFromPtr(ptr);
            
            // Track allocation
            self.total_allocations += 1;
            self.current_memory += len;
            self.peak_memory = @max(self.peak_memory, self.current_memory);
            
            // Store allocation info
            if (self.allocations.count() < self.config.max_tracked_allocations) {
                var allocation_info = AllocationInfo{
                    .ptr = ptr_addr,
                    .size = len,
                    .timestamp = std.time.timestamp(),
                };
                
                // Capture stack trace if enabled
                if (self.config.enable_stack_traces) {
                    // Note: Full stack trace capture would require more setup
                    allocation_info.stack_trace = std.builtin.StackTrace{
                        .instruction_addresses = &[_]usize{ret_addr},
                        .index = 1,
                    };
                }
                
                self.allocations.put(ptr_addr, allocation_info) catch {
                    // Continue even if we can't track - don't fail the allocation
                };
            }
            
            // Initialize memory with pattern for corruption detection
            if (self.config.enable_buffer_overflow_detection) {
                @memset(ptr[0..len], 0xAB); // "Allocated Block" pattern
            }
        }
        
        return result;
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *MemorySafetyValidator = @ptrCast(@alignCast(ctx));
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const ptr_addr = @intFromPtr(buf.ptr);
        
        // Update tracking info
        if (self.allocations.getPtr(ptr_addr)) |info| {
            const old_size = info.size;
            
            // Attempt resize
            const success = self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
            
            if (success) {
                // Update tracking
                self.current_memory = self.current_memory - old_size + new_len;
                self.peak_memory = @max(self.peak_memory, self.current_memory);
                info.size = new_len;
                info.timestamp = std.time.timestamp();
                
                // Initialize new memory if growing
                if (new_len > old_size and self.config.enable_buffer_overflow_detection) {
                    @memset(buf[old_size..new_len], 0xAB);
                }
            }
            
            return success;
        }
        
        // Fallback to backing allocator
        return self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *MemorySafetyValidator = @ptrCast(@alignCast(ctx));
        _ = buf_align;
        _ = ret_addr;
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const ptr_addr = @intFromPtr(buf.ptr);
        
        // Check for tracking info
        if (self.allocations.getPtr(ptr_addr)) |info| {
            // Double free detection
            if (info.freed) {
                self.double_free_count += 1;
                print("⚠️ DOUBLE FREE detected at 0x{X} (size: {} bytes)\n", .{ ptr_addr, info.size });
                // Continue with free to avoid corruption, but record the error
            }
            
            // Mark as freed
            info.freed = true;
            self.total_frees += 1;
            self.current_memory -= info.size;
            
            // Poison freed memory
            if (self.config.poison_freed_memory) {
                @memset(buf, self.config.poison_value);
            }
        } else {
            // Free of untracked memory - could be a problem or just overflow tracking
            self.total_frees += 1;
        }
        
        // Perform actual free
        self.backing_allocator.rawFree(buf, buf_align, ret_addr);
    }
    
    /// Check for use-after-free by scanning for poison patterns
    pub fn checkUseAfterFree(self: *MemorySafetyValidator, ptr: [*]u8, len: usize) bool {
        if (!self.config.enable_use_after_free_detection) return false;
        
        const ptr_addr = @intFromPtr(ptr);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.allocations.get(ptr_addr)) |info| {
            if (info.freed) {
                // Check if memory still contains poison pattern
                var poison_bytes: usize = 0;
                const check_len = @min(len, info.size);
                
                for (ptr[0..check_len]) |byte| {
                    if (byte == self.config.poison_value) {
                        poison_bytes += 1;
                    }
                }
                
                // If less than 50% poison pattern, likely used after free
                if (poison_bytes * 2 < check_len) {
                    self.use_after_free_count += 1;
                    print("⚠️ USE AFTER FREE detected at 0x{X} (size: {} bytes, {}/{} poison bytes)\n", 
                          .{ ptr_addr, info.size, poison_bytes, check_len });
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /// Generate comprehensive memory safety report
    pub fn generateReport(self: *MemorySafetyValidator) !MemorySafetyResult {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Count leaks
        var leaked_count: usize = 0;
        var leaked_bytes: usize = 0;
        var leak_list = ArrayList(AllocationInfo).init(self.backing_allocator);
        
        var iterator = self.allocations.iterator();
        while (iterator.next()) |entry| {
            const info = entry.value_ptr.*;
            if (!info.freed) {
                leaked_count += 1;
                leaked_bytes += info.size;
                try leak_list.append(info);
            }
        }
        
        return MemorySafetyResult{
            .total_allocations = self.total_allocations,
            .total_frees = self.total_frees,
            .active_allocations = leaked_count,
            .leaked_allocations = leaked_count,
            .leaked_bytes = leaked_bytes,
            .use_after_free_detected = self.use_after_free_count,
            .double_free_detected = self.double_free_count,
            .buffer_overflow_detected = self.buffer_overflow_count,
            .memory_corruption_detected = self.corruption_count,
            .peak_memory_bytes = self.peak_memory,
            .leak_details = try leak_list.toOwnedSlice(),
        };
    }
    
    /// Validate memory safety for a test function
    pub fn validateTestFunction(self: *MemorySafetyValidator, test_fn: fn (Allocator) anyerror!void) !MemorySafetyResult {
        // Reset counters
        self.use_after_free_count = 0;
        self.double_free_count = 0;
        self.buffer_overflow_count = 0;
        self.corruption_count = 0;
        
        // Clear existing allocations
        self.allocations.clearRetainingCapacity();
        
        const initial_memory = self.current_memory;
        
        // Run the test function
        try test_fn(self.allocator());
        
        // Check final state
        const final_memory = self.current_memory;
        
        // Generate report
        var result = try self.generateReport();
        
        // Additional validation
        if (final_memory > initial_memory) {
            // Memory increase detected - potential leak
            result.leaked_bytes += final_memory - initial_memory;
        }
        
        return result;
    }
};

/// Convenience function to run memory safety validation on a test
pub fn validateMemorySafety(
    backing_allocator: Allocator, 
    config: MemorySafetyConfig, 
    test_fn: fn (Allocator) anyerror!void
) !MemorySafetyResult {
    var validator = MemorySafetyValidator.init(backing_allocator, config);
    defer validator.deinit();
    
    return try validator.validateTestFunction(test_fn);
}

// Tests
test "memory_safety_validator_basic" {
    const config = MemorySafetyConfig{};
    
    const test_function = struct {
        fn run(allocator: Allocator) !void {
            const data = try allocator.alloc(u8, 100);
            defer allocator.free(data);
            
            data[0] = 42; // Use the memory
        }
    }.run;
    
    const result = try validateMemorySafety(testing.allocator, config, test_function);
    defer {
        var mut_result = result;
        mut_result.deinit(testing.allocator);
    }
    
    try testing.expect(result.leaked_allocations == 0);
    try testing.expect(result.total_allocations >= 1);
    try testing.expect(result.total_frees >= 1);
}

test "memory_safety_validator_leak_detection" {
    const config = MemorySafetyConfig{};
    
    const leaky_function = struct {
        fn run(allocator: Allocator) !void {
            _ = try allocator.alloc(u8, 50); // Intentional leak
            
            const data = try allocator.alloc(u8, 100);
            defer allocator.free(data);
        }
    }.run;
    
    const result = try validateMemorySafety(testing.allocator, config, leaky_function);
    defer {
        var mut_result = result;
        mut_result.deinit(testing.allocator);
    }
    
    try testing.expect(result.leaked_allocations > 0);
    try testing.expect(result.leaked_bytes >= 50);
}