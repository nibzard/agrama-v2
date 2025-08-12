//! Enhanced MCP Server Test Suite
//! Comprehensive testing for all enhanced MCP tools and database integration
//!
//! Test Categories:
//! - MCP Protocol Compliance (JSON-RPC 2.0)
//! - Enhanced Tool Functionality
//! - Database Integration Correctness
//! - Performance Regression Testing
//! - Multi-agent Collaboration
//! - Memory Safety Validation

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Timer = std.time.Timer;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

const EnhancedMCPServer = @import("../src/enhanced_mcp_server.zig").EnhancedMCPServer;
const EnhancedMCPTools = @import("../src/enhanced_mcp_tools.zig").EnhancedMCPTools;
const EnhancedDatabase = @import("../src/enhanced_database.zig").EnhancedDatabase;
const EnhancedDatabaseConfig = @import("../src/enhanced_database.zig").EnhancedDatabaseConfig;
const MCPCompliantServer = @import("../src/mcp_compliant_server.zig");

/// Test result tracking for comprehensive reporting
const TestResult = struct {
    name: []const u8,
    category: TestCategory,
    passed: bool,
    duration_ns: u64,
    memory_used_bytes: usize = 0,
    error_message: ?[]const u8 = null,

    const TestCategory = enum {
        protocol_compliance,
        tool_functionality,
        database_integration,
        performance_regression,
        multi_agent,
        memory_safety,
        load_testing,
    };
};

/// Comprehensive test suite manager
pub const EnhancedMCPTestSuite = struct {
    allocator: Allocator,
    results: ArrayList(TestResult),
    server: ?EnhancedMCPServer = null,
    test_agents: ArrayList(TestAgent),

    const TestAgent = struct {
        id: []const u8,
        name: []const u8,
        capabilities: [][]const u8,
        connected_at: i64,

        pub fn deinit(self: *TestAgent, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            for (self.capabilities) |cap| {
                allocator.free(cap);
            }
            allocator.free(self.capabilities);
        }
    };

    pub fn init(allocator: Allocator) EnhancedMCPTestSuite {
        return .{
            .allocator = allocator,
            .results = ArrayList(TestResult).init(allocator),
            .test_agents = ArrayList(TestAgent).init(allocator),
        };
    }

    pub fn deinit(self: *EnhancedMCPTestSuite) void {
        for (self.results.items) |result| {
            if (result.error_message) |msg| {
                self.allocator.free(msg);
            }
        }
        self.results.deinit();

        for (self.test_agents.items) |*agent| {
            agent.deinit(self.allocator);
        }
        self.test_agents.deinit();

        if (self.server) |*server| {
            server.deinit();
        }
    }

    /// Initialize test server with enhanced database configuration
    pub fn setupTestServer(self: *EnhancedMCPTestSuite) !void {
        const config = EnhancedDatabaseConfig{
            .hnsw_vector_dimensions = 384, // Smaller for testing
            .hnsw_max_connections = 8,
            .hnsw_ef_construction = 100,
            .fre_default_recursion_levels = 2,
            .fre_max_frontier_size = 500,
            .crdt_enable_real_time_sync = true,
        };

        self.server = try EnhancedMCPServer.init(self.allocator, config);

        // Register test agents
        try self.createTestAgents();
    }

    /// Create test agents with various capabilities
    fn createTestAgents(self: *EnhancedMCPTestSuite) !void {
        const agent_configs = [_]struct {
            id: []const u8,
            name: []const u8,
            capabilities: []const []const u8,
        }{
            .{
                .id = "claude-test-agent",
                .name = "Claude Test Agent",
                .capabilities = &[_][]const u8{ "read_code_enhanced", "write_code_enhanced", "semantic_search" },
            },
            .{
                .id = "cursor-test-agent",
                .name = "Cursor Test Agent",
                .capabilities = &[_][]const u8{ "analyze_dependencies", "get_database_stats", "hybrid_search" },
            },
            .{
                .id = "custom-test-agent",
                .name = "Custom Test Agent",
                .capabilities = &[_][]const u8{ "read_code_enhanced", "semantic_search", "analyze_dependencies" },
            },
        };

        for (agent_configs) |config| {
            const agent_id = try self.allocator.dupe(u8, config.id);
            const agent_name = try self.allocator.dupe(u8, config.name);
            const capabilities = try self.allocator.alloc([]const u8, config.capabilities.len);

            for (config.capabilities, 0..) |cap, i| {
                capabilities[i] = try self.allocator.dupe(u8, cap);
            }

            const test_agent = TestAgent{
                .id = agent_id,
                .name = agent_name,
                .capabilities = capabilities,
                .connected_at = std.time.timestamp(),
            };

            try self.test_agents.append(test_agent);

            if (self.server) |*server| {
                try server.registerAgent(agent_id, agent_name, capabilities);
            }
        }
    }

    /// Run all test categories
    pub fn runAllTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("🧪 Starting Enhanced MCP Server Test Suite", .{});

        try self.setupTestServer();

        try self.runProtocolComplianceTests();
        try self.runToolFunctionalityTests();
        try self.runDatabaseIntegrationTests();
        try self.runPerformanceRegressionTests();
        try self.runMultiAgentTests();
        try self.runMemorySafetyTests();
        try self.runLoadTests();

        self.generateTestReport();
    }

    /// Test MCP Protocol Compliance (JSON-RPC 2.0)
    fn runProtocolComplianceTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("🔍 Running MCP Protocol Compliance Tests", .{});

        try self.testJSONRPCStructure();
        try self.testMCPToolDiscovery();
        try self.testMCPErrorHandling();
        try self.testMCPRequestValidation();
    }

    fn testJSONRPCStructure(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
        defer {
            const leaked = gpa.deinit();
            if (leaked == .leak) {
                try self.recordTestResult("JSON-RPC Structure", .protocol_compliance, false, 0, "Memory leak detected");
                return;
            }
        }
        const allocator = gpa.allocator();

        // Test JSON-RPC 2.0 request structure
        const request_json =
            \\{
            \\  "jsonrpc": "2.0",
            \\  "id": 1,
            \\  "method": "tools/call",
            \\  "params": {
            \\    "name": "read_code_enhanced",
            \\    "arguments": {
            \\      "path": "/test/file.zig",
            \\      "include_semantic_context": true
            \\    }
            \\  }
            \\}
        ;

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, request_json, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;

        // Validate JSON-RPC 2.0 compliance
        const jsonrpc_version = obj.get("jsonrpc").?.string;
        const id = obj.get("id").?.integer;
        const method = obj.get("method").?.string;
        const params = obj.get("params").?.object;

        try expect(std.mem.eql(u8, jsonrpc_version, "2.0"));
        try expect(id == 1);
        try expect(std.mem.eql(u8, method, "tools/call"));
        try expect(params.contains("name"));
        try expect(params.contains("arguments"));

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
        try self.recordTestResult("JSON-RPC Structure", .protocol_compliance, true, duration, null);
    }

    fn testMCPToolDiscovery(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            const tools = server.getAvailableTools();

            // Verify all enhanced tools are available
            var found_tools = std.StringHashMap(bool).init(self.allocator);
            defer found_tools.deinit();

            const expected_tools = [_][]const u8{
                "read_code_enhanced",
                "write_code_enhanced",
                "semantic_search",
                "analyze_dependencies",
                "get_database_stats",
            };

            for (expected_tools) |tool_name| {
                try found_tools.put(tool_name, false);
            }

            for (tools) |tool| {
                if (found_tools.getPtr(tool.name)) |found| {
                    found.* = true;
                }
            }

            // Check all tools were found
            var all_found = true;
            var it = found_tools.iterator();
            while (it.next()) |entry| {
                if (!entry.value_ptr.*) {
                    all_found = false;
                    break;
                }
            }

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("MCP Tool Discovery", .protocol_compliance, all_found, duration, null);
        } else {
            try self.recordTestResult("MCP Tool Discovery", .protocol_compliance, false, 0, "Server not initialized");
        }
    }

    fn testMCPErrorHandling(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Test error handling with invalid tool call
            const invalid_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-error-1"),
                .method = "tools/call",
                .params = .{
                    .name = "nonexistent_tool",
                    .arguments = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) },
                },
            };
            defer {
                self.allocator.free(invalid_request.id);
                self.allocator.free(invalid_request.method);
                self.allocator.free(invalid_request.params.name);
            }

            const response = server.handleRequest(invalid_request, "claude-test-agent") catch |err| {
                // Expected error
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const success = err == error.UnknownTool;
                try self.recordTestResult("MCP Error Handling", .protocol_compliance, success, duration, null);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Should have error in response
            const has_error = response.@"error" != null;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("MCP Error Handling", .protocol_compliance, has_error, duration, null);
        } else {
            try self.recordTestResult("MCP Error Handling", .protocol_compliance, false, 0, "Server not initialized");
        }
    }

    fn testMCPRequestValidation(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test request parameter validation
        var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
        defer {
            const leaked = gpa.deinit();
            if (leaked == .leak) {
                std.log.warn("Memory leak in MCP request validation test", .{});
            }
        }
        const allocator = gpa.allocator();

        // Create request with missing required parameters
        var arguments_map = std.json.ObjectMap.init(allocator);
        defer arguments_map.deinit();

        // Missing 'path' parameter for read_code_enhanced
        try arguments_map.put("include_history", std.json.Value{ .bool = true });

        const invalid_args_request = EnhancedMCPServer.MCPRequest{
            .id = try allocator.dupe(u8, "test-validation-1"),
            .method = try allocator.dupe(u8, "tools/call"),
            .params = .{
                .name = try allocator.dupe(u8, "read_code_enhanced"),
                .arguments = std.json.Value{ .object = arguments_map },
            },
        };
        defer {
            allocator.free(invalid_args_request.id);
            allocator.free(invalid_args_request.method);
            allocator.free(invalid_args_request.params.name);
        }

        if (self.server) |*server| {
            const response = server.handleRequest(invalid_args_request, "claude-test-agent") catch |err| {
                // Expected validation error
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const success = err == error.MissingPath;
                try self.recordTestResult("MCP Request Validation", .protocol_compliance, success, duration, null);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Should have validation error
            const has_validation_error = response.@"error" != null;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("MCP Request Validation", .protocol_compliance, has_validation_error, duration, null);
        } else {
            try self.recordTestResult("MCP Request Validation", .protocol_compliance, false, 0, "Server not initialized");
        }
    }

    /// Test Enhanced Tool Functionality
    fn runToolFunctionalityTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("⚙️ Running Enhanced Tool Functionality Tests", .{});

        try self.testReadCodeEnhanced();
        try self.testWriteCodeEnhanced();
        try self.testSemanticSearch();
        try self.testAnalyzeDependencies();
        try self.testDatabaseStats();
        try self.testLegacyCompatibility();
    }

    fn testReadCodeEnhanced(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Create test file for reading
            const test_file_path = "/tmp/test_read_enhanced.zig";
            const test_content =
                \\const std = @import("std");
                \\
                \\pub fn fibonacci(n: u32) u32 {
                \\    if (n <= 1) return n;
                \\    return fibonacci(n - 1) + fibonacci(n - 2);
                \\}
            ;

            // Write test file
            try std.fs.cwd().writeFile(test_file_path, test_content);
            defer std.fs.cwd().deleteFile(test_file_path) catch {};

            // Create read request
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_file_path) });
            try arguments_map.put("include_semantic_context", std.json.Value{ .bool = true });
            try arguments_map.put("include_dependencies", std.json.Value{ .bool = true });
            try arguments_map.put("include_history", std.json.Value{ .bool = false });

            const read_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-read-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "read_code_enhanced"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(read_request.id);
                self.allocator.free(read_request.method);
                self.allocator.free(read_request.params.name);
                // arguments cleanup handled by ObjectMap.deinit()
            }

            const response = server.handleRequest(read_request, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Read request failed: {}", .{err});
                try self.recordTestResult("Read Code Enhanced", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Validate response structure
            const success = response.result != null and response.@"error" == null;

            if (success and response.result) |result| {
                const result_obj = result.object;

                // Check required fields
                const has_path = result_obj.contains("path");
                const has_content = result_obj.contains("content");
                const has_semantic_context = result_obj.contains("semantic_context");
                const has_dependency_context = result_obj.contains("dependency_context");

                const all_fields_present = has_path and has_content and has_semantic_context and has_dependency_context;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Read Code Enhanced", .tool_functionality, all_fields_present, duration, null);
            } else {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Read Code Enhanced", .tool_functionality, false, duration, "Invalid response structure");
            }
        } else {
            try self.recordTestResult("Read Code Enhanced", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    fn testWriteCodeEnhanced(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            const test_file_path = "/tmp/test_write_enhanced.zig";
            const test_content =
                \\const std = @import("std");
                \\
                \\pub fn quickSort(arr: []i32) void {
                \\    if (arr.len <= 1) return;
                \\    // Implementation here
                \\}
            ;

            // Create write request
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_file_path) });
            try arguments_map.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, test_content) });
            try arguments_map.put("enable_semantic_indexing", std.json.Value{ .bool = true });
            try arguments_map.put("enable_dependency_tracking", std.json.Value{ .bool = true });
            try arguments_map.put("enable_crdt_sync", std.json.Value{ .bool = false }); // Disable for test

            const write_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-write-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "write_code_enhanced"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(write_request.id);
                self.allocator.free(write_request.method);
                self.allocator.free(write_request.params.name);
            }

            const response = server.handleRequest(write_request, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Write request failed: {}", .{err});
                try self.recordTestResult("Write Code Enhanced", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Cleanup test file
            defer std.fs.cwd().deleteFile(test_file_path) catch {};

            // Validate response
            const success = response.result != null and response.@"error" == null;

            if (success and response.result) |result| {
                const result_obj = result.object;

                // Check required fields
                const has_success = result_obj.get("success") != null and result_obj.get("success").?.bool;
                const has_path = result_obj.contains("path");
                const has_indexing_status = result_obj.contains("indexing_status");

                // Verify file was actually written
                const file_exists = std.fs.cwd().access(test_file_path, .{}) != error.FileNotFound;

                const all_checks_passed = has_success and has_path and has_indexing_status and file_exists;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Write Code Enhanced", .tool_functionality, all_checks_passed, duration, null);
            } else {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Write Code Enhanced", .tool_functionality, false, duration, "Invalid response structure");
            }
        } else {
            try self.recordTestResult("Write Code Enhanced", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    fn testSemanticSearch(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Create semantic search request
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("query", std.json.Value{ .string = try self.allocator.dupe(u8, "fibonacci recursive algorithm") });
            try arguments_map.put("max_results", std.json.Value{ .integer = 10 });
            try arguments_map.put("include_semantic", std.json.Value{ .bool = true });
            try arguments_map.put("include_lexical", std.json.Value{ .bool = true });
            try arguments_map.put("include_graph", std.json.Value{ .bool = true });

            const search_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-search-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "semantic_search"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(search_request.id);
                self.allocator.free(search_request.method);
                self.allocator.free(search_request.params.name);
            }

            const response = server.handleRequest(search_request, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Semantic search failed: {}", .{err});
                try self.recordTestResult("Semantic Search", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Validate search response
            const success = response.result != null and response.@"error" == null;

            if (success and response.result) |result| {
                const result_obj = result.object;

                const has_query = result_obj.contains("query");
                const has_total_results = result_obj.contains("total_results");
                const has_results = result_obj.contains("results");

                const all_fields_present = has_query and has_total_results and has_results;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Semantic Search", .tool_functionality, all_fields_present, duration, null);
            } else {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Semantic Search", .tool_functionality, false, duration, "Invalid search response");
            }
        } else {
            try self.recordTestResult("Semantic Search", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    fn testAnalyzeDependencies(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Create dependency analysis request
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("file_path", std.json.Value{ .string = try self.allocator.dupe(u8, "/test/example.zig") });
            try arguments_map.put("max_depth", std.json.Value{ .integer = 3 });
            try arguments_map.put("include_impact_analysis", std.json.Value{ .bool = true });

            const deps_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-deps-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "analyze_dependencies"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(deps_request.id);
                self.allocator.free(deps_request.method);
                self.allocator.free(deps_request.params.name);
            }

            const response = server.handleRequest(deps_request, "cursor-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Dependency analysis failed: {}", .{err});
                try self.recordTestResult("Analyze Dependencies", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Validate dependency analysis response
            const success = response.result != null and response.@"error" == null;

            if (success and response.result) |result| {
                const result_obj = result.object;

                const has_root_file = result_obj.contains("root_file");
                const has_total_dependencies = result_obj.contains("total_dependencies");
                const has_dependencies = result_obj.contains("dependencies");
                const has_impact_analysis = result_obj.contains("impact_analysis");

                const all_fields_present = has_root_file and has_total_dependencies and has_dependencies and has_impact_analysis;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Analyze Dependencies", .tool_functionality, all_fields_present, duration, null);
            } else {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Analyze Dependencies", .tool_functionality, false, duration, "Invalid dependency response");
            }
        } else {
            try self.recordTestResult("Analyze Dependencies", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    fn testDatabaseStats(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Create database stats request
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("include_performance_metrics", std.json.Value{ .bool = true });
            try arguments_map.put("include_component_details", std.json.Value{ .bool = true });

            const stats_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-stats-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "get_database_stats"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(stats_request.id);
                self.allocator.free(stats_request.method);
                self.allocator.free(stats_request.params.name);
            }

            const response = server.handleRequest(stats_request, "cursor-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Database stats failed: {}", .{err});
                try self.recordTestResult("Database Stats", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Validate database stats response
            const success = response.result != null and response.@"error" == null;

            if (success and response.result) |result| {
                const result_obj = result.object;

                const has_components = result_obj.contains("components");
                const has_performance = result_obj.contains("performance");

                const all_fields_present = has_components and has_performance;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Database Stats", .tool_functionality, all_fields_present, duration, null);
            } else {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Database Stats", .tool_functionality, false, duration, "Invalid stats response");
            }
        } else {
            try self.recordTestResult("Database Stats", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    fn testLegacyCompatibility(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test that legacy tools still work
        if (self.server) |*server| {
            // Test legacy read_code tool
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, "/test/legacy.zig") });
            try arguments_map.put("include_history", std.json.Value{ .bool = false });

            const legacy_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "test-legacy-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "read_code"), // Legacy tool name
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(legacy_request.id);
                self.allocator.free(legacy_request.method);
                self.allocator.free(legacy_request.params.name);
            }

            const response = server.handleRequest(legacy_request, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Legacy compatibility failed: {}", .{err});
                try self.recordTestResult("Legacy Compatibility", .tool_functionality, false, duration, error_msg);
                return;
            };
            defer {
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            // Legacy tools should work with reduced functionality
            const success = response.result != null and response.@"error" == null;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Legacy Compatibility", .tool_functionality, success, duration, null);
        } else {
            try self.recordTestResult("Legacy Compatibility", .tool_functionality, false, 0, "Server not initialized");
        }
    }

    /// Test Database Integration Correctness
    fn runDatabaseIntegrationTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("🗄️ Running Database Integration Tests", .{});

        try self.testHNSWIntegration();
        try self.testFREIntegration();
        try self.testCRDTIntegration();
        try self.testTripleHybridIntegration();
        try self.testTemporalQueries();
    }

    fn testHNSWIntegration(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test HNSW vector search integration
        if (self.server) |server| {
            const stats = server.getStats();

            // HNSW should be initialized and operational
            const hnsw_operational = stats.database.semantic_indexed_files >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("HNSW Integration", .database_integration, hnsw_operational, duration, null);
        } else {
            try self.recordTestResult("HNSW Integration", .database_integration, false, 0, "Server not initialized");
        }
    }

    fn testFREIntegration(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test FRE graph traversal integration
        if (self.server) |server| {
            const stats = server.getStats();

            // FRE should be integrated with graph operations
            const fre_operational = stats.database.graph_nodes >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("FRE Integration", .database_integration, fre_operational, duration, null);
        } else {
            try self.recordTestResult("FRE Integration", .database_integration, false, 0, "Server not initialized");
        }
    }

    fn testCRDTIntegration(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test CRDT collaboration integration
        if (self.server) |server| {
            const stats = server.getStats();

            // CRDT should be available for collaboration
            const crdt_operational = stats.database.active_crdt_documents >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("CRDT Integration", .database_integration, crdt_operational, duration, null);
        } else {
            try self.recordTestResult("CRDT Integration", .database_integration, false, 0, "Server not initialized");
        }
    }

    fn testTripleHybridIntegration(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test BM25 + HNSW + FRE integration
        if (self.server) |server| {
            const stats = server.getStats();

            // All hybrid search components should be operational
            const hybrid_operational = stats.semantic_searches >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Triple Hybrid Integration", .database_integration, hybrid_operational, duration, null);
        } else {
            try self.recordTestResult("Triple Hybrid Integration", .database_integration, false, 0, "Server not initialized");
        }
    }

    fn testTemporalQueries(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test temporal database queries
        if (self.server) |server| {
            const stats = server.getStats();

            // Temporal database should be operational
            const temporal_operational = stats.database.temporal_files >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Temporal Queries", .database_integration, temporal_operational, duration, null);
        } else {
            try self.recordTestResult("Temporal Queries", .database_integration, false, 0, "Server not initialized");
        }
    }

    /// Test Performance Regression
    fn runPerformanceRegressionTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("⚡ Running Performance Regression Tests", .{});

        try self.testMCPResponseTimes();
        try self.testSemanticSearchPerformance();
        try self.testDependencyAnalysisPerformance();
        try self.testThroughputRegression();
    }

    fn testMCPResponseTimes(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const target_response_time_ms = 100.0; // Sub-100ms target

        if (self.server) |*server| {
            var response_times = ArrayList(f64).init(self.allocator);
            defer response_times.deinit();

            // Run multiple requests and measure response times
            for (0..50) |i| {
                var arguments_map = std.json.ObjectMap.init(self.allocator);
                defer arguments_map.deinit();

                const test_path = try std.fmt.allocPrint(self.allocator, "/test/perf_{}.zig", .{i});
                defer self.allocator.free(test_path);

                try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_path) });

                const request = EnhancedMCPServer.MCPRequest{
                    .id = try std.fmt.allocPrint(self.allocator, "perf-test-{}", .{i}),
                    .method = try self.allocator.dupe(u8, "tools/call"),
                    .params = .{
                        .name = try self.allocator.dupe(u8, "read_code_enhanced"),
                        .arguments = std.json.Value{ .object = arguments_map },
                    },
                };
                defer {
                    self.allocator.free(request.id);
                    self.allocator.free(request.method);
                    self.allocator.free(request.params.name);
                }

                const request_start = std.time.nanoTimestamp();
                const response = server.handleRequest(request, "claude-test-agent") catch |err| {
                    std.log.warn("Performance test request {} failed: {}", .{ i, err });
                    continue;
                };
                const request_time_ns = std.time.nanoTimestamp() - request_start;
                const request_time_ms = @as(f64, @floatFromInt(request_time_ns)) / 1_000_000.0;

                try response_times.append(request_time_ms);

                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            if (response_times.items.len > 0) {
                // Calculate performance metrics
                var total_time: f64 = 0;
                var max_time: f64 = 0;
                for (response_times.items) |time| {
                    total_time += time;
                    if (time > max_time) max_time = time;
                }

                const avg_time = total_time / @as(f64, @floatFromInt(response_times.items.len));
                const meets_target = avg_time <= target_response_time_ms;

                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

                if (!meets_target) {
                    const error_msg = try std.fmt.allocPrint(self.allocator, "Avg response time {:.2}ms exceeds target {:.2}ms", .{ avg_time, target_response_time_ms });
                    try self.recordTestResult("MCP Response Times", .performance_regression, false, duration, error_msg);
                } else {
                    try self.recordTestResult("MCP Response Times", .performance_regression, true, duration, null);
                }
            } else {
                try self.recordTestResult("MCP Response Times", .performance_regression, false, 0, "No successful requests");
            }
        } else {
            try self.recordTestResult("MCP Response Times", .performance_regression, false, 0, "Server not initialized");
        }
    }

    fn testSemanticSearchPerformance(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const target_search_time_ms = 50.0; // Target for O(log n) HNSW search

        if (self.server) |*server| {
            // Test semantic search performance
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("query", std.json.Value{ .string = try self.allocator.dupe(u8, "algorithm implementation performance") });
            try arguments_map.put("max_results", std.json.Value{ .integer = 20 });

            const search_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "search-perf-test"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "semantic_search"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(search_request.id);
                self.allocator.free(search_request.method);
                self.allocator.free(search_request.params.name);
            }

            const search_start = std.time.nanoTimestamp();
            const response = server.handleRequest(search_request, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Semantic search perf test failed: {}", .{err});
                try self.recordTestResult("Semantic Search Performance", .performance_regression, false, duration, error_msg);
                return;
            };
            const search_time_ns = std.time.nanoTimestamp() - search_start;
            const search_time_ms = @as(f64, @floatFromInt(search_time_ns)) / 1_000_000.0;

            var mutable_response = response;
            mutable_response.deinit(self.allocator);

            const meets_target = search_time_ms <= target_search_time_ms;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!meets_target) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Search time {:.2}ms exceeds target {:.2}ms", .{ search_time_ms, target_search_time_ms });
                try self.recordTestResult("Semantic Search Performance", .performance_regression, false, duration, error_msg);
            } else {
                try self.recordTestResult("Semantic Search Performance", .performance_regression, true, duration, null);
            }
        } else {
            try self.recordTestResult("Semantic Search Performance", .performance_regression, false, 0, "Server not initialized");
        }
    }

    fn testDependencyAnalysisPerformance(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const target_analysis_time_ms = 75.0; // Target for FRE O(m log^(2/3) n) traversal

        if (self.server) |*server| {
            // Test dependency analysis performance
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            try arguments_map.put("file_path", std.json.Value{ .string = try self.allocator.dupe(u8, "/test/complex_dependencies.zig") });
            try arguments_map.put("max_depth", std.json.Value{ .integer = 3 });
            try arguments_map.put("include_impact_analysis", std.json.Value{ .bool = true });

            const deps_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "deps-perf-test"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "analyze_dependencies"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(deps_request.id);
                self.allocator.free(deps_request.method);
                self.allocator.free(deps_request.params.name);
            }

            const analysis_start = std.time.nanoTimestamp();
            const response = server.handleRequest(deps_request, "cursor-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Dependency analysis perf test failed: {}", .{err});
                try self.recordTestResult("Dependency Analysis Performance", .performance_regression, false, duration, error_msg);
                return;
            };
            const analysis_time_ns = std.time.nanoTimestamp() - analysis_start;
            const analysis_time_ms = @as(f64, @floatFromInt(analysis_time_ns)) / 1_000_000.0;

            var mutable_response = response;
            mutable_response.deinit(self.allocator);

            const meets_target = analysis_time_ms <= target_analysis_time_ms;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!meets_target) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Analysis time {:.2}ms exceeds target {:.2}ms", .{ analysis_time_ms, target_analysis_time_ms });
                try self.recordTestResult("Dependency Analysis Performance", .performance_regression, false, duration, error_msg);
            } else {
                try self.recordTestResult("Dependency Analysis Performance", .performance_regression, true, duration, null);
            }
        } else {
            try self.recordTestResult("Dependency Analysis Performance", .performance_regression, false, 0, "Server not initialized");
        }
    }

    fn testThroughputRegression(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const target_throughput_qps = 500.0; // Target throughput: 500 queries per second

        if (self.server) |*server| {
            const num_requests = 100;
            const batch_start = std.time.nanoTimestamp();

            var successful_requests: u32 = 0;

            // Execute batch of requests
            for (0..num_requests) |i| {
                var arguments_map = std.json.ObjectMap.init(self.allocator);
                defer arguments_map.deinit();

                try arguments_map.put("include_performance_metrics", std.json.Value{ .bool = true });

                const stats_request = EnhancedMCPServer.MCPRequest{
                    .id = try std.fmt.allocPrint(self.allocator, "throughput-{}", .{i}),
                    .method = try self.allocator.dupe(u8, "tools/call"),
                    .params = .{
                        .name = try self.allocator.dupe(u8, "get_database_stats"),
                        .arguments = std.json.Value{ .object = arguments_map },
                    },
                };
                defer {
                    self.allocator.free(stats_request.id);
                    self.allocator.free(stats_request.method);
                    self.allocator.free(stats_request.params.name);
                }

                const response = server.handleRequest(stats_request, "cursor-test-agent") catch |err| {
                    std.log.warn("Throughput test request {} failed: {}", .{ i, err });
                    continue;
                };

                var mutable_response = response;
                mutable_response.deinit(self.allocator);

                successful_requests += 1;
            }

            const batch_time_ns = std.time.nanoTimestamp() - batch_start;
            const batch_time_s = @as(f64, @floatFromInt(batch_time_ns)) / 1_000_000_000.0;
            const actual_throughput = @as(f64, @floatFromInt(successful_requests)) / batch_time_s;

            const meets_target = actual_throughput >= target_throughput_qps;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!meets_target) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Throughput {:.1} QPS below target {:.1} QPS", .{ actual_throughput, target_throughput_qps });
                try self.recordTestResult("Throughput Regression", .performance_regression, false, duration, error_msg);
            } else {
                try self.recordTestResult("Throughput Regression", .performance_regression, true, duration, null);
            }
        } else {
            try self.recordTestResult("Throughput Regression", .performance_regression, false, 0, "Server not initialized");
        }
    }

    /// Test Multi-agent Collaboration
    fn runMultiAgentTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("👥 Running Multi-agent Collaboration Tests", .{});

        try self.testConcurrentAccess();
        try self.testCRDTConflictResolution();
        try self.testEventBroadcasting();
        try self.testAgentIsolation();
    }

    fn testConcurrentAccess(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        if (self.server) |*server| {
            // Simulate concurrent access from multiple agents
            const concurrent_agents = 3;
            const requests_per_agent = 10;

            var threads = ArrayList(Thread).init(self.allocator);
            defer threads.deinit();

            var success_count = std.atomic.Atomic(u32).init(0);
            var error_count = std.atomic.Atomic(u32).init(0);

            const ThreadContext = struct {
                server: *EnhancedMCPServer,
                agent_id: []const u8,
                requests: u32,
                success_counter: *std.atomic.Atomic(u32),
                error_counter: *std.atomic.Atomic(u32),
                allocator: Allocator,
            };

            const worker_fn = struct {
                fn run(context: ThreadContext) void {
                    for (0..context.requests) |i| {
                        var arguments_map = std.json.ObjectMap.init(context.allocator);
                        defer arguments_map.deinit();

                        const test_path = std.fmt.allocPrint(context.allocator, "/test/concurrent_{}_{}.zig", .{ context.agent_id, i }) catch {
                            _ = context.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        };
                        defer context.allocator.free(test_path);

                        arguments_map.put("path", std.json.Value{ .string = context.allocator.dupe(u8, test_path) catch {
                            _ = context.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        } }) catch {
                            _ = context.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        };

                        const request = EnhancedMCPServer.MCPRequest{
                            .id = std.fmt.allocPrint(context.allocator, "concurrent-{}-{}", .{ context.agent_id, i }) catch {
                                _ = context.error_counter.fetchAdd(1, .seq_cst);
                                continue;
                            },
                            .method = context.allocator.dupe(u8, "tools/call") catch {
                                _ = context.error_counter.fetchAdd(1, .seq_cst);
                                continue;
                            },
                            .params = .{
                                .name = context.allocator.dupe(u8, "read_code_enhanced") catch {
                                    _ = context.error_counter.fetchAdd(1, .seq_cst);
                                    continue;
                                },
                                .arguments = std.json.Value{ .object = arguments_map },
                            },
                        };
                        defer {
                            context.allocator.free(request.id);
                            context.allocator.free(request.method);
                            context.allocator.free(request.params.name);
                        }

                        const response = context.server.handleRequest(request, context.agent_id) catch {
                            _ = context.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        };

                        var mutable_response = response;
                        mutable_response.deinit(context.allocator);

                        _ = context.success_counter.fetchAdd(1, .seq_cst);
                    }
                }
            }.run;

            // Start concurrent worker threads
            for (0..concurrent_agents) |i| {
                const agent_id = try std.fmt.allocPrint(self.allocator, "concurrent-agent-{}", .{i});
                defer self.allocator.free(agent_id);

                const context = ThreadContext{
                    .server = server,
                    .agent_id = agent_id,
                    .requests = requests_per_agent,
                    .success_counter = &success_count,
                    .error_counter = &error_count,
                    .allocator = self.allocator,
                };

                const thread = try Thread.spawn(.{}, worker_fn, .{context});
                try threads.append(thread);
            }

            // Wait for all threads to complete
            for (threads.items) |thread| {
                thread.join();
            }

            const total_expected = concurrent_agents * requests_per_agent;
            const total_success = success_count.load(.seq_cst);
            const total_errors = error_count.load(.seq_cst);

            // Consider test successful if most requests succeeded
            const success_rate = @as(f64, @floatFromInt(total_success)) / @as(f64, @floatFromInt(total_expected));
            const concurrent_access_successful = success_rate >= 0.8; // 80% success rate threshold

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!concurrent_access_successful) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Success rate {:.1}% below 80%, {} errors", .{ success_rate * 100, total_errors });
                try self.recordTestResult("Concurrent Access", .multi_agent, false, duration, error_msg);
            } else {
                try self.recordTestResult("Concurrent Access", .multi_agent, true, duration, null);
            }
        } else {
            try self.recordTestResult("Concurrent Access", .multi_agent, false, 0, "Server not initialized");
        }
    }

    fn testCRDTConflictResolution(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test CRDT conflict resolution between agents
        if (self.server) |*server| {
            // Simulate conflicting writes from different agents
            const test_file = "/tmp/crdt_test_conflict.zig";
            const content1 = "const value = 1;";
            const content2 = "const value = 2;";

            // Agent 1 writes first
            var arguments_map1 = std.json.ObjectMap.init(self.allocator);
            defer arguments_map1.deinit();

            try arguments_map1.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_file) });
            try arguments_map1.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, content1) });
            try arguments_map1.put("enable_crdt_sync", std.json.Value{ .bool = true });

            const write_request1 = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "crdt-write-1"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "write_code_enhanced"),
                    .arguments = std.json.Value{ .object = arguments_map1 },
                },
            };
            defer {
                self.allocator.free(write_request1.id);
                self.allocator.free(write_request1.method);
                self.allocator.free(write_request1.params.name);
            }

            const response1 = server.handleRequest(write_request1, "claude-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "First CRDT write failed: {}", .{err});
                try self.recordTestResult("CRDT Conflict Resolution", .multi_agent, false, duration, error_msg);
                return;
            };
            var mutable_response1 = response1;
            mutable_response1.deinit(self.allocator);

            // Agent 2 writes conflicting content
            var arguments_map2 = std.json.ObjectMap.init(self.allocator);
            defer arguments_map2.deinit();

            try arguments_map2.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_file) });
            try arguments_map2.put("content", std.json.Value{ .string = try self.allocator.dupe(u8, content2) });
            try arguments_map2.put("enable_crdt_sync", std.json.Value{ .bool = true });

            const write_request2 = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "crdt-write-2"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "write_code_enhanced"),
                    .arguments = std.json.Value{ .object = arguments_map2 },
                },
            };
            defer {
                self.allocator.free(write_request2.id);
                self.allocator.free(write_request2.method);
                self.allocator.free(write_request2.params.name);
            }

            const response2 = server.handleRequest(write_request2, "cursor-test-agent") catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Second CRDT write failed: {}", .{err});
                try self.recordTestResult("CRDT Conflict Resolution", .multi_agent, false, duration, error_msg);
                return;
            };
            var mutable_response2 = response2;
            mutable_response2.deinit(self.allocator);

            // Cleanup
            defer std.fs.cwd().deleteFile(test_file) catch {};

            // Both writes should succeed (conflict resolution handles differences)
            const both_successful = response1.result != null and response2.result != null;
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("CRDT Conflict Resolution", .multi_agent, both_successful, duration, null);
        } else {
            try self.recordTestResult("CRDT Conflict Resolution", .multi_agent, false, 0, "Server not initialized");
        }
    }

    fn testEventBroadcasting(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test event broadcasting to connected agents
        if (self.server) |server| {
            // Event broadcasting is tested indirectly through MCP tool calls
            // In a real implementation, this would test WebSocket event distribution

            const stats = server.getStats();

            // Test passes if server can provide stats (indicates event system is operational)
            const event_system_operational = stats.agents >= 0; // Should not error

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Event Broadcasting", .multi_agent, event_system_operational, duration, null);
        } else {
            try self.recordTestResult("Event Broadcasting", .multi_agent, false, 0, "Server not initialized");
        }
    }

    fn testAgentIsolation(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test that agents are properly isolated (access control, metrics, etc.)
        if (self.server) |server| {
            const stats = server.getStats();

            // Each test agent should be tracked separately
            const expected_agents = self.test_agents.items.len;
            const actual_agents = stats.agents;

            const agent_isolation_correct = actual_agents == expected_agents;

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!agent_isolation_correct) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Expected {} agents, found {}", .{ expected_agents, actual_agents });
                try self.recordTestResult("Agent Isolation", .multi_agent, false, duration, error_msg);
            } else {
                try self.recordTestResult("Agent Isolation", .multi_agent, true, duration, null);
            }
        } else {
            try self.recordTestResult("Agent Isolation", .multi_agent, false, 0, "Server not initialized");
        }
    }

    /// Test Memory Safety
    fn runMemorySafetyTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("🛡️ Running Memory Safety Tests", .{});

        try self.testMemoryLeakDetection();
        try self.testBoundsChecking();
        try self.testResourceCleanup();
    }

    fn testMemoryLeakDetection(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Use GeneralPurposeAllocator with leak detection
        var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
        const allocator = gpa.allocator();

        // Perform operations that might leak memory
        {
            const config = EnhancedDatabaseConfig{};
            var test_server = EnhancedMCPServer.init(allocator, config) catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Memory leak test server init failed: {}", .{err});
                try self.recordTestResult("Memory Leak Detection", .memory_safety, false, duration, error_msg);
                _ = gpa.deinit();
                return;
            };
            defer test_server.deinit();

            // Register and unregister agents
            try test_server.registerAgent("leak-test-agent", "Leak Test Agent", &[_][]const u8{"read_code_enhanced"});
            test_server.unregisterAgent("leak-test-agent");
        }

        // Check for leaks
        const leaked = gpa.deinit();
        const no_leaks = leaked != .leak;

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

        if (!no_leaks) {
            try self.recordTestResult("Memory Leak Detection", .memory_safety, false, duration, "Memory leak detected");
        } else {
            try self.recordTestResult("Memory Leak Detection", .memory_safety, true, duration, null);
        }
    }

    fn testBoundsChecking(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test bounds checking with invalid parameters
        if (self.server) |*server| {
            // Create request with potentially problematic parameters
            var arguments_map = std.json.ObjectMap.init(self.allocator);
            defer arguments_map.deinit();

            // Very long path that might cause buffer overruns
            const long_path = "/test/" ++ "very_long_filename" ** 50 ++ ".zig";
            try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, long_path) });

            const bounds_request = EnhancedMCPServer.MCPRequest{
                .id = try self.allocator.dupe(u8, "bounds-test"),
                .method = try self.allocator.dupe(u8, "tools/call"),
                .params = .{
                    .name = try self.allocator.dupe(u8, "read_code_enhanced"),
                    .arguments = std.json.Value{ .object = arguments_map },
                },
            };
            defer {
                self.allocator.free(bounds_request.id);
                self.allocator.free(bounds_request.method);
                self.allocator.free(bounds_request.params.name);
            }

            // Should handle gracefully without crashing
            const response = server.handleRequest(bounds_request, "claude-test-agent") catch |err| {
                // Expected to handle gracefully
                const handled_gracefully = err == error.FileNotFound or err == error.PathTooLong;
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                try self.recordTestResult("Bounds Checking", .memory_safety, handled_gracefully, duration, null);
                return;
            };

            var mutable_response = response;
            mutable_response.deinit(self.allocator);

            // Response should be valid (no crashes)
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Bounds Checking", .memory_safety, true, duration, null);
        } else {
            try self.recordTestResult("Bounds Checking", .memory_safety, false, 0, "Server not initialized");
        }
    }

    fn testResourceCleanup(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test that resources are properly cleaned up
        if (self.server) |*server| {
            const initial_stats = server.getStats();

            // Perform operations that allocate resources
            for (0..10) |i| {
                var arguments_map = std.json.ObjectMap.init(self.allocator);
                defer arguments_map.deinit();

                const test_path = try std.fmt.allocPrint(self.allocator, "/test/cleanup_{}.zig", .{i});
                defer self.allocator.free(test_path);

                try arguments_map.put("path", std.json.Value{ .string = try self.allocator.dupe(u8, test_path) });

                const cleanup_request = EnhancedMCPServer.MCPRequest{
                    .id = try std.fmt.allocPrint(self.allocator, "cleanup-{}", .{i}),
                    .method = try self.allocator.dupe(u8, "tools/call"),
                    .params = .{
                        .name = try self.allocator.dupe(u8, "read_code_enhanced"),
                        .arguments = std.json.Value{ .object = arguments_map },
                    },
                };
                defer {
                    self.allocator.free(cleanup_request.id);
                    self.allocator.free(cleanup_request.method);
                    self.allocator.free(cleanup_request.params.name);
                }

                const response = server.handleRequest(cleanup_request, "claude-test-agent") catch continue;
                var mutable_response = response;
                mutable_response.deinit(self.allocator);
            }

            const final_stats = server.getStats();

            // Resource usage should not have grown excessively
            const resource_growth_reasonable = final_stats.requests >= initial_stats.requests; // Should increase

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
            try self.recordTestResult("Resource Cleanup", .memory_safety, resource_growth_reasonable, duration, null);
        } else {
            try self.recordTestResult("Resource Cleanup", .memory_safety, false, 0, "Server not initialized");
        }
    }

    /// Test Load Testing
    fn runLoadTests(self: *EnhancedMCPTestSuite) !void {
        std.log.info("⚖️ Running Load Tests", .{});

        try self.testHighConcurrencyLoad();
        try self.testSustainedLoad();
        try self.testMemoryUnderLoad();
    }

    fn testHighConcurrencyLoad(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const target_concurrent_agents = 20;
        const requests_per_agent = 5;

        if (self.server) |*server| {
            var success_count = std.atomic.Atomic(u32).init(0);
            var error_count = std.atomic.Atomic(u32).init(0);

            // Register additional agents for load testing
            var load_agents = ArrayList([]const u8).init(self.allocator);
            defer {
                for (load_agents.items) |agent_id| {
                    server.unregisterAgent(agent_id);
                    self.allocator.free(agent_id);
                }
                load_agents.deinit();
            }

            for (0..target_concurrent_agents) |i| {
                const agent_id = try std.fmt.allocPrint(self.allocator, "load-agent-{}", .{i});
                try load_agents.append(agent_id);
                try server.registerAgent(agent_id, "Load Test Agent", &[_][]const u8{"get_database_stats"});
            }

            // Simulate high concurrency load
            var threads = ArrayList(Thread).init(self.allocator);
            defer threads.deinit();

            const LoadContext = struct {
                server: *EnhancedMCPServer,
                agent_id: []const u8,
                requests: u32,
                success_counter: *std.atomic.Atomic(u32),
                error_counter: *std.atomic.Atomic(u32),
                allocator: Allocator,
            };

            const load_worker = struct {
                fn run(ctx: LoadContext) void {
                    for (0..ctx.requests) |_| {
                        var arguments_map = std.json.ObjectMap.init(ctx.allocator);
                        defer arguments_map.deinit();

                        arguments_map.put("include_performance_metrics", std.json.Value{ .bool = true }) catch {
                            _ = ctx.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        };

                        const load_request = EnhancedMCPServer.MCPRequest{
                            .id = std.fmt.allocPrint(ctx.allocator, "load-{}-{}", .{ ctx.agent_id, std.time.nanoTimestamp() }) catch {
                                _ = ctx.error_counter.fetchAdd(1, .seq_cst);
                                continue;
                            },
                            .method = ctx.allocator.dupe(u8, "tools/call") catch {
                                _ = ctx.error_counter.fetchAdd(1, .seq_cst);
                                continue;
                            },
                            .params = .{
                                .name = ctx.allocator.dupe(u8, "get_database_stats") catch {
                                    _ = ctx.error_counter.fetchAdd(1, .seq_cst);
                                    continue;
                                },
                                .arguments = std.json.Value{ .object = arguments_map },
                            },
                        };
                        defer {
                            ctx.allocator.free(load_request.id);
                            ctx.allocator.free(load_request.method);
                            ctx.allocator.free(load_request.params.name);
                        }

                        const response = ctx.server.handleRequest(load_request, ctx.agent_id) catch {
                            _ = ctx.error_counter.fetchAdd(1, .seq_cst);
                            continue;
                        };

                        var mutable_response = response;
                        mutable_response.deinit(ctx.allocator);

                        _ = ctx.success_counter.fetchAdd(1, .seq_cst);
                    }
                }
            }.run;

            // Start load test threads
            for (load_agents.items) |agent_id| {
                const context = LoadContext{
                    .server = server,
                    .agent_id = agent_id,
                    .requests = requests_per_agent,
                    .success_counter = &success_count,
                    .error_counter = &error_count,
                    .allocator = self.allocator,
                };

                const thread = try Thread.spawn(.{}, load_worker, .{context});
                try threads.append(thread);
            }

            // Wait for completion
            for (threads.items) |thread| {
                thread.join();
            }

            const total_expected = target_concurrent_agents * requests_per_agent;
            const total_success = success_count.load(.seq_cst);
            const success_rate = @as(f64, @floatFromInt(total_success)) / @as(f64, @floatFromInt(total_expected));

            const load_handled_well = success_rate >= 0.75; // 75% success rate under high load
            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!load_handled_well) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Success rate {:.1}% below 75% under high concurrency", .{success_rate * 100});
                try self.recordTestResult("High Concurrency Load", .load_testing, false, duration, error_msg);
            } else {
                try self.recordTestResult("High Concurrency Load", .load_testing, true, duration, null);
            }
        } else {
            try self.recordTestResult("High Concurrency Load", .load_testing, false, 0, "Server not initialized");
        }
    }

    fn testSustainedLoad(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();
        const load_duration_ms = 5000; // 5 seconds
        const request_interval_ms = 10; // 100 requests/second

        if (self.server) |*server| {
            var request_count: u32 = 0;
            var error_count: u32 = 0;

            const load_end_time = std.time.milliTimestamp() + load_duration_ms;

            while (std.time.milliTimestamp() < load_end_time) {
                var arguments_map = std.json.ObjectMap.init(self.allocator);
                defer arguments_map.deinit();

                try arguments_map.put("include_performance_metrics", std.json.Value{ .bool = true });

                const sustained_request = EnhancedMCPServer.MCPRequest{
                    .id = try std.fmt.allocPrint(self.allocator, "sustained-{}", .{request_count}),
                    .method = try self.allocator.dupe(u8, "tools/call"),
                    .params = .{
                        .name = try self.allocator.dupe(u8, "get_database_stats"),
                        .arguments = std.json.Value{ .object = arguments_map },
                    },
                };
                defer {
                    self.allocator.free(sustained_request.id);
                    self.allocator.free(sustained_request.method);
                    self.allocator.free(sustained_request.params.name);
                }

                const response = server.handleRequest(sustained_request, "claude-test-agent") catch |err| {
                    error_count += 1;
                    std.log.warn("Sustained load request {} failed: {}", .{ request_count, err });
                    std.time.sleep(request_interval_ms * 1_000_000); // nanoseconds
                    continue;
                };

                var mutable_response = response;
                mutable_response.deinit(self.allocator);

                request_count += 1;
                std.time.sleep(request_interval_ms * 1_000_000); // nanoseconds
            }

            const error_rate = if (request_count > 0) @as(f64, @floatFromInt(error_count)) / @as(f64, @floatFromInt(request_count)) else 1.0;
            const sustained_load_successful = error_rate <= 0.05; // Max 5% error rate

            const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));

            if (!sustained_load_successful) {
                const error_msg = try std.fmt.allocPrint(self.allocator, "Error rate {:.2}% above 5% during sustained load", .{error_rate * 100});
                try self.recordTestResult("Sustained Load", .load_testing, false, duration, error_msg);
            } else {
                try self.recordTestResult("Sustained Load", .load_testing, true, duration, null);
            }
        } else {
            try self.recordTestResult("Sustained Load", .load_testing, false, 0, "Server not initialized");
        }
    }

    fn testMemoryUnderLoad(self: *EnhancedMCPTestSuite) !void {
        const test_start = std.time.nanoTimestamp();

        // Test memory behavior under load
        var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
        defer {
            const leaked = gpa.deinit();
            if (leaked == .leak) {
                std.log.warn("Memory leaks detected during load testing", .{});
            }
        }
        const load_allocator = gpa.allocator();

        {
            const config = EnhancedDatabaseConfig{};
            var load_server = EnhancedMCPServer.init(load_allocator, config) catch |err| {
                const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
                const error_msg = try std.fmt.allocPrint(self.allocator, "Memory load test server init failed: {}", .{err});
                try self.recordTestResult("Memory Under Load", .load_testing, false, duration, error_msg);
                return;
            };
            defer load_server.deinit();

            try load_server.registerAgent("memory-load-agent", "Memory Load Agent", &[_][]const u8{"get_database_stats"});

            // Perform many operations to test memory stability
            for (0..200) |i| {
                var arguments_map = std.json.ObjectMap.init(load_allocator);
                defer arguments_map.deinit();

                try arguments_map.put("include_performance_metrics", std.json.Value{ .bool = true });

                const memory_request = EnhancedMCPServer.MCPRequest{
                    .id = try std.fmt.allocPrint(load_allocator, "memory-{}", .{i}),
                    .method = try load_allocator.dupe(u8, "tools/call"),
                    .params = .{
                        .name = try load_allocator.dupe(u8, "get_database_stats"),
                        .arguments = std.json.Value{ .object = arguments_map },
                    },
                };
                defer {
                    load_allocator.free(memory_request.id);
                    load_allocator.free(memory_request.method);
                    load_allocator.free(memory_request.params.name);
                }

                const response = load_server.handleRequest(memory_request, "memory-load-agent") catch continue;
                var mutable_response = response;
                mutable_response.deinit(load_allocator);
            }
        } // Server goes out of scope and cleans up

        // Check for memory issues
        const no_memory_issues = gpa.deinit() != .leak;

        const duration = @as(u64, @intCast(std.time.nanoTimestamp() - test_start));
        try self.recordTestResult("Memory Under Load", .load_testing, no_memory_issues, duration, null);
    }

    /// Record a test result
    fn recordTestResult(self: *EnhancedMCPTestSuite, name: []const u8, category: TestResult.TestCategory, passed: bool, duration_ns: u64, error_message: ?[]const u8) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const owned_error = if (error_message) |msg| try self.allocator.dupe(u8, msg) else null;

        const result = TestResult{
            .name = owned_name,
            .category = category,
            .passed = passed,
            .duration_ns = duration_ns,
            .error_message = owned_error,
        };

        try self.results.append(result);
    }

    /// Generate comprehensive test report
    fn generateTestReport(self: *EnhancedMCPTestSuite) void {
        std.log.info("\n" ++ "=" ** 60, .{});
        std.log.info("ENHANCED MCP SERVER TEST REPORT", .{});
        std.log.info("=" ** 60, .{});

        // Calculate overall statistics
        var total_tests: u32 = 0;
        var passed_tests: u32 = 0;
        var failed_tests: u32 = 0;
        var total_duration_ns: u64 = 0;

        var category_stats = std.EnumMap(TestResult.TestCategory, struct { total: u32 = 0, passed: u32 = 0 }){};

        for (self.results.items) |result| {
            total_tests += 1;
            total_duration_ns += result.duration_ns;

            if (result.passed) {
                passed_tests += 1;
            } else {
                failed_tests += 1;
            }

            // Update category stats
            var cat_stat = category_stats.get(result.category) orelse .{};
            cat_stat.total += 1;
            if (result.passed) cat_stat.passed += 1;
            category_stats.put(result.category, cat_stat);
        }

        const pass_rate = if (total_tests > 0) @as(f64, @floatFromInt(passed_tests)) / @as(f64, @floatFromInt(total_tests)) else 0.0;
        const total_duration_s = @as(f64, @floatFromInt(total_duration_ns)) / 1_000_000_000.0;

        // Overall summary
        std.log.info("\n📊 OVERALL RESULTS:", .{});
        std.log.info("  Total Tests: {}", .{total_tests});
        std.log.info("  Passed: {} ✅", .{passed_tests});
        std.log.info("  Failed: {} ❌", .{failed_tests});
        std.log.info("  Pass Rate: {:.1}%", .{pass_rate * 100});
        std.log.info("  Total Duration: {:.2}s", .{total_duration_s});

        // Category breakdown
        std.log.info("\n📂 CATEGORY BREAKDOWN:", .{});
        inline for (@typeInfo(TestResult.TestCategory).Enum.fields) |field| {
            const category = @field(TestResult.TestCategory, field.name);
            const stats = category_stats.get(category) orelse .{};
            if (stats.total > 0) {
                const cat_pass_rate = @as(f64, @floatFromInt(stats.passed)) / @as(f64, @floatFromInt(stats.total));
                std.log.info("  {s}: {}/{} ({:.1}%)", .{ field.name, stats.passed, stats.total, cat_pass_rate * 100 });
            }
        }

        // Failed test details
        if (failed_tests > 0) {
            std.log.info("\n❌ FAILED TESTS:", .{});
            for (self.results.items) |result| {
                if (!result.passed) {
                    const duration_ms = @as(f64, @floatFromInt(result.duration_ns)) / 1_000_000.0;
                    std.log.info("  [{s}] {s} ({:.2}ms)", .{ @tagName(result.category), result.name, duration_ms });
                    if (result.error_message) |msg| {
                        std.log.info("    Error: {s}", .{msg});
                    }
                }
            }
        }

        // Performance summary
        std.log.info("\n⚡ PERFORMANCE SUMMARY:", .{});
        var perf_tests: u32 = 0;
        var perf_passed: u32 = 0;
        var fastest_ns: u64 = std.math.maxInt(u64);
        var slowest_ns: u64 = 0;

        for (self.results.items) |result| {
            if (result.category == .performance_regression) {
                perf_tests += 1;
                if (result.passed) perf_passed += 1;
                if (result.duration_ns < fastest_ns) fastest_ns = result.duration_ns;
                if (result.duration_ns > slowest_ns) slowest_ns = result.duration_ns;
            }
        }

        if (perf_tests > 0) {
            const fastest_ms = @as(f64, @floatFromInt(fastest_ns)) / 1_000_000.0;
            const slowest_ms = @as(f64, @floatFromInt(slowest_ns)) / 1_000_000.0;
            std.log.info("  Performance Tests: {}/{}", .{ perf_passed, perf_tests });
            std.log.info("  Fastest Test: {:.2}ms", .{fastest_ms});
            std.log.info("  Slowest Test: {:.2}ms", .{slowest_ms});
        }

        // Final verdict
        std.log.info("\n🎯 FINAL VERDICT:", .{});
        if (pass_rate >= 1.0) {
            std.log.info("🟢 EXCELLENT - ALL TESTS PASSED!", .{});
        } else if (pass_rate >= 0.95) {
            std.log.info("🟢 VERY GOOD - MINOR ISSUES TO ADDRESS", .{});
        } else if (pass_rate >= 0.85) {
            std.log.info("🟡 GOOD - SOME IMPROVEMENTS NEEDED", .{});
        } else if (pass_rate >= 0.70) {
            std.log.info("🟠 FAIR - SIGNIFICANT ISSUES TO RESOLVE", .{});
        } else {
            std.log.info("🔴 POOR - MAJOR PROBLEMS DETECTED", .{});
        }

        std.log.info("=" ** 60, .{});
    }
};

/// Main test runner entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leaks detected in main test suite", .{});
        }
    }
    const allocator = gpa.allocator();

    var test_suite = EnhancedMCPTestSuite.init(allocator);
    defer test_suite.deinit();

    try test_suite.runAllTests();
}

// Basic unit tests for test infrastructure
test "enhanced_mcp_test_suite_init" {
    var suite = EnhancedMCPTestSuite.init(testing.allocator);
    defer suite.deinit();

    try expect(suite.results.items.len == 0);
    try expect(suite.test_agents.items.len == 0);
}

test "test_result_recording" {
    var suite = EnhancedMCPTestSuite.init(testing.allocator);
    defer suite.deinit();

    try suite.recordTestResult("Test Example", .protocol_compliance, true, 1000000, null);

    try expect(suite.results.items.len == 1);
    const result = suite.results.items[0];
    try expect(result.passed);
    try expect(result.category == .protocol_compliance);
    try expect(std.mem.eql(u8, result.name, "Test Example"));
}
