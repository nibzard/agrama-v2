---
title: MCP Development Guide  
description: Guide for extending and developing the Agrama MCP server with custom tools and integrations
---

# MCP Development Guide

Comprehensive guide for developers who want to extend the Agrama MCP server, add custom tools, or contribute to the codebase.

## Architecture Overview

### Core Components

The Agrama MCP server is built with a modular architecture in Zig:

```
src/
├── mcp_compliant_server.zig    # Core MCP protocol implementation
├── enhanced_mcp_tools.zig      # Enhanced tool definitions
├── mcp_utils.zig              # Utility functions
├── database.zig               # Temporal knowledge graph
├── memory_pools.zig           # Memory management
└── triple_hybrid_search.zig   # Search engine
```

### Key Design Principles

1. **Memory Safety**: Zero-cost abstractions with compile-time guarantees
2. **Performance**: Sub-millisecond response times through optimization
3. **Modularity**: Clean separation between protocol, tools, and database
4. **Extensibility**: Plugin-like architecture for custom tools

## Setting up Development Environment

### Prerequisites

```bash
# Install Zig 0.12+
curl https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz | tar -xJ
export PATH=$PATH:./zig-linux-x86_64-0.12.0

# Verify installation
zig version
```

### Building from Source

```bash
# Clone repository
git clone https://github.com/your-org/agrama-v2.git
cd agrama-v2

# Development build with debug symbols
zig build -Doptimize=Debug

# Run tests
zig build test

# Run with debug output
./zig-out/bin/agrama mcp --verbose
```

### IDE Setup

#### VS Code with Zig Extension

```json
// .vscode/settings.json
{
  "zig.enableInlayHints": true,
  "zig.buildOnSave": true,
  "zig.formatOnSave": true,
  "files.associations": {
    "*.zig": "zig"
  },
  "editor.tabSize": 4,
  "editor.insertSpaces": true
}
```

#### Vim/Neovim

```lua
-- Using nvim-lspconfig
require('lspconfig').zls.setup{
  settings = {
    zls = {
      enable_inlay_hints = true,
      enable_snippets = true,
      warn_style = true,
    },
  },
}
```

## Adding Custom MCP Tools

### Tool Development Workflow

1. **Define Tool Schema**: Create input/output schemas
2. **Implement Handler**: Write the tool execution logic
3. **Register Tool**: Add to the tool registry
4. **Test Tool**: Write comprehensive tests
5. **Document Tool**: Add API documentation

### Step 1: Define Tool Schema

Create a new tool in `src/custom_tools.zig`:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Custom tool for code complexity analysis
pub const CodeComplexityTool = struct {
    pub const name = "analyze_complexity";
    pub const description = "Analyze code complexity metrics including cyclomatic complexity";

    /// Input schema definition
    pub const InputSchema = struct {
        file_path: []const u8,
        metrics: ?[]const []const u8 = null, // ["cyclomatic", "cognitive", "halstead"]
        threshold: ?f32 = 10.0,
        include_functions: ?bool = true,
    };

    /// Output schema definition  
    pub const OutputSchema = struct {
        file_path: []const u8,
        overall_complexity: f32,
        functions: []FunctionComplexity,
        metrics: ComplexityMetrics,
        warnings: []Warning,

        pub const FunctionComplexity = struct {
            name: []const u8,
            line_start: u32,
            line_end: u32,
            cyclomatic: f32,
            cognitive: f32,
            halstead: ?HalsteadMetrics = null,
        };

        pub const ComplexityMetrics = struct {
            cyclomatic: f32,
            cognitive: f32,
            maintainability_index: f32,
        };

        pub const HalsteadMetrics = struct {
            vocabulary: u32,
            length: u32,
            difficulty: f32,
            effort: f32,
        };

        pub const Warning = struct {
            level: []const u8, // "info", "warning", "error"
            message: []const u8,
            line: ?u32 = null,
            function: ?[]const u8 = null,
        };
    };
```

### Step 2: Implement Handler

```zig
    /// Tool execution handler
    pub fn execute(
        database: *Database,
        params: InputSchema,
        agent_id: []const u8,
        allocator: Allocator
    ) !std.json.Value {
        // Input validation
        try validateInput(params);

        // Read file content
        const file_content = database.getFile(params.file_path) catch |err| switch (err) {
            error.FileNotFound => {
                return createErrorResponse(allocator, "File not found", params.file_path);
            },
            else => return err,
        };
        defer allocator.free(file_content.content);

        // Analyze complexity
        var analyzer = CodeComplexityAnalyzer.init(allocator);
        defer analyzer.deinit();

        const analysis = try analyzer.analyze(file_content.content, params);

        // Convert to JSON
        return try analysisToJson(allocator, analysis, params);
    }

    /// Input validation
    fn validateInput(params: InputSchema) !void {
        if (params.file_path.len == 0) {
            return error.EmptyFilePath;
        }

        if (params.threshold) |threshold| {
            if (threshold <= 0) {
                return error.InvalidThreshold;
            }
        }

        if (params.metrics) |metrics| {
            for (metrics) |metric| {
                if (!isValidMetric(metric)) {
                    return error.InvalidMetric;
                }
            }
        }
    }

    fn isValidMetric(metric: []const u8) bool {
        const valid_metrics = [_][]const u8{ "cyclomatic", "cognitive", "halstead" };
        for (valid_metrics) |valid| {
            if (std.mem.eql(u8, metric, valid)) {
                return true;
            }
        }
        return false;
    }

    /// Create error response
    fn createErrorResponse(
        allocator: Allocator,
        message: []const u8,
        context: []const u8
    ) !std.json.Value {
        var error_obj = std.json.ObjectMap.init(allocator);
        try error_obj.put("success", std.json.Value{ .bool = false });
        try error_obj.put("error", std.json.Value{ .string = try allocator.dupe(u8, message) });
        try error_obj.put("context", std.json.Value{ .string = try allocator.dupe(u8, context) });
        return std.json.Value{ .object = error_obj };
    }

    /// Convert analysis results to JSON
    fn analysisToJson(
        allocator: Allocator,
        analysis: ComplexityAnalysis,
        params: InputSchema
    ) !std.json.Value {
        var result = std.json.ObjectMap.init(allocator);
        
        // Basic information
        try result.put("file_path", std.json.Value{ .string = try allocator.dupe(u8, params.file_path) });
        try result.put("overall_complexity", std.json.Value{ .float = analysis.overall_complexity });

        // Functions array
        var functions_array = std.json.Array.init(allocator);
        for (analysis.functions) |func| {
            var func_obj = std.json.ObjectMap.init(allocator);
            try func_obj.put("name", std.json.Value{ .string = try allocator.dupe(u8, func.name) });
            try func_obj.put("line_start", std.json.Value{ .integer = @as(i64, @intCast(func.line_start)) });
            try func_obj.put("line_end", std.json.Value{ .integer = @as(i64, @intCast(func.line_end)) });
            try func_obj.put("cyclomatic", std.json.Value{ .float = func.cyclomatic });
            try func_obj.put("cognitive", std.json.Value{ .float = func.cognitive });
            
            if (func.halstead) |halstead| {
                var halstead_obj = std.json.ObjectMap.init(allocator);
                try halstead_obj.put("vocabulary", std.json.Value{ .integer = @as(i64, @intCast(halstead.vocabulary)) });
                try halstead_obj.put("length", std.json.Value{ .integer = @as(i64, @intCast(halstead.length)) });
                try halstead_obj.put("difficulty", std.json.Value{ .float = halstead.difficulty });
                try halstead_obj.put("effort", std.json.Value{ .float = halstead.effort });
                try func_obj.put("halstead", std.json.Value{ .object = halstead_obj });
            }
            
            try functions_array.append(std.json.Value{ .object = func_obj });
        }
        try result.put("functions", std.json.Value{ .array = functions_array });

        // Metrics
        var metrics_obj = std.json.ObjectMap.init(allocator);
        try metrics_obj.put("cyclomatic", std.json.Value{ .float = analysis.metrics.cyclomatic });
        try metrics_obj.put("cognitive", std.json.Value{ .float = analysis.metrics.cognitive });
        try metrics_obj.put("maintainability_index", std.json.Value{ .float = analysis.metrics.maintainability_index });
        try result.put("metrics", std.json.Value{ .object = metrics_obj });

        // Warnings
        var warnings_array = std.json.Array.init(allocator);
        for (analysis.warnings) |warning| {
            var warning_obj = std.json.ObjectMap.init(allocator);
            try warning_obj.put("level", std.json.Value{ .string = try allocator.dupe(u8, warning.level) });
            try warning_obj.put("message", std.json.Value{ .string = try allocator.dupe(u8, warning.message) });
            
            if (warning.line) |line| {
                try warning_obj.put("line", std.json.Value{ .integer = @as(i64, @intCast(line)) });
            }
            
            if (warning.function) |function| {
                try warning_obj.put("function", std.json.Value{ .string = try allocator.dupe(u8, function) });
            }
            
            try warnings_array.append(std.json.Value{ .object = warning_obj });
        }
        try result.put("warnings", std.json.Value{ .array = warnings_array });

        return std.json.Value{ .object = result };
    }
};
```

### Step 3: Register Tool

Add your tool to the MCP server in `src/mcp_compliant_server.zig`:

```zig
const CustomTools = @import("custom_tools.zig");

/// Initialize all tools
fn initializeTools(self: *MCPCompliantServer, allocator: Allocator) !void {
    // Core tools
    try self.registerTool(allocator, "read_code", EnhancedMCPTools.ReadCodeEnhanced);
    try self.registerTool(allocator, "write_code", EnhancedMCPTools.WriteCodeEnhanced);
    
    // Custom tools
    try self.registerTool(allocator, "analyze_complexity", CustomTools.CodeComplexityTool);
    
    // ... other tools
}

/// Generic tool registration
fn registerTool(
    self: *MCPCompliantServer,
    allocator: Allocator,
    name: []const u8,
    comptime Tool: type
) !void {
    // Create tool definition
    var arena = std.heap.ArenaAllocator.init(allocator);
    const tool_def = MCPToolDefinition{
        .name = try allocator.dupe(u8, Tool.name),
        .title = try allocator.dupe(u8, Tool.name), // Can be customized
        .description = try allocator.dupe(u8, Tool.description),
        .inputSchema = try createInputSchema(allocator, Tool.InputSchema),
        .arena = arena,
    };

    // Register handler
    try self.tools.append(tool_def);
    try self.tool_handlers.put(name, ToolHandler{
        .execute = struct {
            fn call(
                database: *Database,
                params: std.json.Value,
                agent_id: []const u8,
                allocator_inner: Allocator
            ) !std.json.Value {
                // Parse parameters
                const typed_params = try std.json.parseFromValue(
                    Tool.InputSchema,
                    allocator_inner,
                    params,
                    .{}
                );

                // Execute tool
                return Tool.execute(database, typed_params, agent_id, allocator_inner);
            }
        }.call,
    });
}
```

### Step 4: Testing Custom Tools

Create tests in `tests/custom_tools_test.zig`:

```zig
const std = @import("std");
const testing = std.testing;
const CustomTools = @import("../src/custom_tools.zig");
const Database = @import("../src/database.zig").Database;

test "CodeComplexityTool - basic functionality" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup test database
    var database = try Database.init(allocator, ":memory:");
    defer database.deinit();

    // Add test file
    const test_code = 
        \\const std = @import("std");
        \\
        \\pub fn simpleFunction(x: i32) i32 {
        \\    if (x > 0) {
        \\        return x * 2;
        \\    } else {
        \\        return x * -2;
        \\    }
        \\}
        \\
        \\pub fn complexFunction(a: i32, b: i32, c: i32) i32 {
        \\    var result: i32 = 0;
        \\    
        \\    for (0..10) |i| {
        \\        if (i % 2 == 0) {
        \\            if (a > b) {
        \\                result += a;
        \\            } else if (b > c) {
        \\                result += b;
        \\            } else {
        \\                result += c;
        \\            }
        \\        } else {
        \\            switch (i) {
        \\                1, 3, 5 => result -= 1,
        \\                7, 9 => result += 1,
        \\                else => result *= 2,
        \\            }
        \\        }
        \\    }
        \\    
        \\    return result;
        \\}
    ;

    try database.storeFile("test_file.zig", test_code, "test_agent");

    // Test tool execution
    const params = CustomTools.CodeComplexityTool.InputSchema{
        .file_path = "test_file.zig",
        .metrics = &[_][]const u8{ "cyclomatic", "cognitive" },
        .threshold = 5.0,
        .include_functions = true,
    };

    const result = try CustomTools.CodeComplexityTool.execute(
        &database,
        params,
        "test_agent",
        allocator
    );

    // Validate results
    try testing.expect(result == .object);
    const result_obj = result.object;
    
    try testing.expect(result_obj.contains("file_path"));
    try testing.expect(result_obj.contains("overall_complexity"));
    try testing.expect(result_obj.contains("functions"));
    try testing.expect(result_obj.contains("metrics"));

    const functions = result_obj.get("functions").?.array;
    try testing.expect(functions.items.len == 2); // simpleFunction and complexFunction

    // Check that complex function has higher complexity
    const simple_func = functions.items[0].object;
    const complex_func = functions.items[1].object;
    
    const simple_cyclomatic = simple_func.get("cyclomatic").?.float;
    const complex_cyclomatic = complex_func.get("cyclomatic").?.float;
    
    try testing.expect(complex_cyclomatic > simple_cyclomatic);
}

test "CodeComplexityTool - error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var database = try Database.init(allocator, ":memory:");
    defer database.deinit();

    // Test with non-existent file
    const params = CustomTools.CodeComplexityTool.InputSchema{
        .file_path = "nonexistent.zig",
        .threshold = 5.0,
    };

    const result = try CustomTools.CodeComplexityTool.execute(
        &database,
        params,
        "test_agent",
        allocator
    );

    // Should return error response
    try testing.expect(result == .object);
    const result_obj = result.object;
    try testing.expect(result_obj.contains("success"));
    try testing.expect(result_obj.get("success").?.bool == false);
    try testing.expect(result_obj.contains("error"));
}

test "CodeComplexityTool - parameter validation" {
    // Test invalid threshold
    const invalid_params = CustomTools.CodeComplexityTool.InputSchema{
        .file_path = "test.zig",
        .threshold = -1.0, // Invalid
    };

    try testing.expectError(error.InvalidThreshold, CustomTools.CodeComplexityTool.validateInput(invalid_params));

    // Test invalid metric
    const invalid_metric_params = CustomTools.CodeComplexityTool.InputSchema{
        .file_path = "test.zig",
        .metrics = &[_][]const u8{"invalid_metric"},
    };

    try testing.expectError(error.InvalidMetric, CustomTools.CodeComplexityTool.validateInput(invalid_metric_params));
}
```

### Step 5: Integration Testing

Test the tool through the MCP protocol:

```zig
test "CodeComplexityTool - MCP integration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup MCP server
    var server = try MCPCompliantServer.init(allocator);
    defer server.deinit();

    // Test tool discovery
    const tools_response = try server.handleToolsList(allocator);
    defer tools_response.deinit();

    // Verify tool is listed
    var found_tool = false;
    const tools = tools_response.result.?.object.get("tools").?.array;
    for (tools.items) |tool| {
        const tool_obj = tool.object;
        const tool_name = tool_obj.get("name").?.string;
        if (std.mem.eql(u8, tool_name, "analyze_complexity")) {
            found_tool = true;
            
            // Verify schema
            const schema = tool_obj.get("inputSchema").?.object;
            try testing.expect(schema.contains("properties"));
            
            const properties = schema.get("properties").?.object;
            try testing.expect(properties.contains("file_path"));
            try testing.expect(properties.contains("threshold"));
            break;
        }
    }
    try testing.expect(found_tool);

    // Test tool execution through MCP
    const mcp_request = 
        \\{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze_complexity","arguments":{"file_path":"test.zig","threshold":5.0}}}
    ;

    const response = try server.processRequest(mcp_request);
    defer response.deinit();

    // Validate MCP response format
    try testing.expect(std.mem.eql(u8, response.jsonrpc, "2.0"));
    try testing.expect(response.id != null);
    try testing.expect(response.result != null);
}
```

## Event System Architecture

### Real-time Event Broadcasting

The MCP server supports real-time event broadcasting for collaboration:

```zig
/// Event types that can be broadcast
pub const MCPEvent = union(enum) {
    tool_call: ToolCallEvent,
    database_change: DatabaseChangeEvent,
    agent_action: AgentActionEvent,
    performance_metric: PerformanceMetricEvent,
    custom: CustomEvent,

    pub const ToolCallEvent = struct {
        agent_id: []const u8,
        tool_name: []const u8,
        timestamp: i64,
        duration_ms: f64,
        success: bool,
    };

    pub const DatabaseChangeEvent = struct {
        operation: []const u8, // "create", "update", "delete"
        entity_path: []const u8,
        agent_id: []const u8,
        timestamp: i64,
    };

    pub const AgentActionEvent = struct {
        agent_id: []const u8,
        action: []const u8,
        context: std.json.Value,
        timestamp: i64,
    };

    pub const PerformanceMetricEvent = struct {
        metric_name: []const u8,
        value: f64,
        unit: []const u8,
        timestamp: i64,
    };

    pub const CustomEvent = struct {
        event_type: []const u8,
        data: std.json.Value,
        timestamp: i64,
    };
};

/// Event broadcaster for real-time updates
pub const EventBroadcaster = struct {
    subscribers: ArrayList(EventSubscriber),
    allocator: Allocator,
    mutex: std.Thread.Mutex,

    pub const EventSubscriber = struct {
        id: []const u8,
        callback: *const fn (event: MCPEvent) void,
        filter: ?EventFilter = null,
    };

    pub const EventFilter = struct {
        event_types: ?[]const []const u8 = null,
        agent_ids: ?[]const []const u8 = null,
    };

    pub fn init(allocator: Allocator) EventBroadcaster {
        return EventBroadcaster{
            .subscribers = ArrayList(EventSubscriber).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn subscribe(self: *EventBroadcaster, subscriber: EventSubscriber) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.subscribers.append(subscriber);
    }

    pub fn broadcast(self: *EventBroadcaster, event: MCPEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.subscribers.items) |subscriber| {
            if (self.shouldNotify(subscriber, event)) {
                subscriber.callback(event);
            }
        }
    }

    fn shouldNotify(self: *EventBroadcaster, subscriber: EventSubscriber, event: MCPEvent) bool {
        _ = self;
        
        if (subscriber.filter) |filter| {
            // Check event type filter
            if (filter.event_types) |types| {
                const event_type = @tagName(event);
                var found = false;
                for (types) |allowed_type| {
                    if (std.mem.eql(u8, event_type, allowed_type)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }

            // Check agent ID filter
            if (filter.agent_ids) |agent_ids| {
                const event_agent_id = switch (event) {
                    .tool_call => |e| e.agent_id,
                    .database_change => |e| e.agent_id,
                    .agent_action => |e| e.agent_id,
                    else => null,
                };

                if (event_agent_id) |agent_id| {
                    var found = false;
                    for (agent_ids) |allowed_id| {
                        if (std.mem.eql(u8, agent_id, allowed_id)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) return false;
                }
            }
        }

        return true;
    }
};
```

### Custom Event Handlers

```zig
/// Custom event handler for logging
const LoggingEventHandler = struct {
    logger: std.log.ScopedLogging(.mcp_events),

    pub fn handleEvent(event: MCPEvent) void {
        switch (event) {
            .tool_call => |e| {
                logger.info("Tool call: {} by {} ({}ms, success: {})", .{
                    e.tool_name, e.agent_id, e.duration_ms, e.success
                });
            },
            .database_change => |e| {
                logger.info("Database {}: {} by {} at {}", .{
                    e.operation, e.entity_path, e.agent_id, e.timestamp
                });
            },
            .performance_metric => |e| {
                logger.debug("Metric {}: {} {}", .{ e.metric_name, e.value, e.unit });
            },
            else => {},
        }
    }
};

/// Performance monitoring event handler
const PerformanceMonitor = struct {
    metrics: std.HashMap([]const u8, MetricHistory, std.hash_map.StringContext, 80),
    allocator: Allocator,

    const MetricHistory = struct {
        values: std.ArrayList(f64),
        timestamps: std.ArrayList(i64),
        max_size: usize = 1000,
    };

    pub fn handleEvent(self: *PerformanceMonitor, event: MCPEvent) void {
        switch (event) {
            .performance_metric => |e| {
                self.recordMetric(e.metric_name, e.value, e.timestamp);
            },
            .tool_call => |e| {
                self.recordMetric("tool_call_duration", e.duration_ms, e.timestamp);
                self.recordMetric("tool_call_success_rate", if (e.success) 1.0 else 0.0, e.timestamp);
            },
            else => {},
        }
    }

    fn recordMetric(self: *PerformanceMonitor, name: []const u8, value: f64, timestamp: i64) void {
        var history = self.metrics.getOrPut(name) catch return;
        
        if (!history.found_existing) {
            history.value_ptr.* = MetricHistory{
                .values = std.ArrayList(f64).init(self.allocator),
                .timestamps = std.ArrayList(i64).init(self.allocator),
            };
        }

        const metric_history = history.value_ptr;
        
        metric_history.values.append(value) catch return;
        metric_history.timestamps.append(timestamp) catch return;

        // Keep only recent values
        if (metric_history.values.items.len > metric_history.max_size) {
            _ = metric_history.values.orderedRemove(0);
            _ = metric_history.timestamps.orderedRemove(0);
        }
    }
};
```

## Testing Framework

### Unit Testing

Create comprehensive unit tests for your components:

```zig
const std = @import("std");
const testing = std.testing;

/// Test utilities for MCP development
pub const MCPTestUtils = struct {
    /// Create a test MCP server
    pub fn createTestServer(allocator: Allocator) !MCPCompliantServer {
        var server = try MCPCompliantServer.init(allocator);
        
        // Initialize with test database
        server.database = try Database.init(allocator, ":memory:");
        
        return server;
    }

    /// Create test MCP request
    pub fn createTestRequest(
        allocator: Allocator,
        method: []const u8,
        params: std.json.Value
    ) ![]const u8 {
        const request = .{
            .jsonrpc = "2.0",
            .id = 1,
            .method = method,
            .params = params,
        };

        return try std.json.stringifyAlloc(allocator, request, .{});
    }

    /// Parse MCP response for testing
    pub fn parseTestResponse(
        allocator: Allocator,
        response_json: []const u8
    ) !std.json.Parsed(MCPResponse) {
        return try std.json.parseFromSlice(MCPResponse, allocator, response_json, .{});
    }

    /// Assert successful MCP response
    pub fn assertSuccessfulResponse(response: MCPResponse) !void {
        try testing.expect(response.@"error" == null);
        try testing.expect(response.result != null);
        try testing.expectEqualStrings("2.0", response.jsonrpc);
    }

    /// Assert error response with specific code
    pub fn assertErrorResponse(response: MCPResponse, expected_code: i32) !void {
        try testing.expect(response.result == null);
        try testing.expect(response.@"error" != null);
        try testing.expectEqual(expected_code, response.@"error".?.code);
    }
};
```

### Integration Testing

```zig
test "Full MCP workflow integration" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var server = try MCPTestUtils.createTestServer(allocator);
    defer server.deinit();

    // Test 1: Initialize connection
    const init_request = try MCPTestUtils.createTestRequest(allocator, "initialize", .{
        .object = std.json.ObjectMap.init(allocator),
    });
    defer allocator.free(init_request);

    var init_response = try server.processRequest(init_request);
    defer init_response.deinit();

    try MCPTestUtils.assertSuccessfulResponse(init_response);

    // Test 2: List tools
    const list_request = try MCPTestUtils.createTestRequest(allocator, "tools/list", null);
    defer allocator.free(list_request);

    var list_response = try server.processRequest(list_request);
    defer list_response.deinit();

    try MCPTestUtils.assertSuccessfulResponse(list_response);
    
    // Verify tools are listed
    const tools = list_response.result.?.object.get("tools").?.array;
    try testing.expect(tools.items.len > 0);

    // Test 3: Call a tool
    var params = std.json.ObjectMap.init(allocator);
    try params.put("path", .{ .string = "test.zig" });

    const tool_request = try MCPTestUtils.createTestRequest(allocator, "tools/call", .{
        .object = params,
    });
    defer allocator.free(tool_request);

    var tool_response = try server.processRequest(tool_request);
    defer tool_response.deinit();

    // Should handle gracefully even with missing file
    try testing.expect(tool_response.result != null or tool_response.@"error" != null);
}
```

### Performance Testing

```zig
test "Tool performance benchmarks" {
    const iterations = 1000;
    var total_time: u64 = 0;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var server = try MCPTestUtils.createTestServer(allocator);
    defer server.deinit();

    // Warm up
    for (0..10) |_| {
        _ = try server.callTool("read_code", .{ .path = "test.zig" });
    }

    // Benchmark
    for (0..iterations) |_| {
        const start = std.time.nanoTimestamp();
        
        _ = try server.callTool("read_code", .{ .path = "test.zig" });
        
        const end = std.time.nanoTimestamp();
        total_time += @intCast(end - start);
    }

    const avg_time_ns = total_time / iterations;
    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;

    // Assert performance target (should be < 1ms)
    try testing.expect(avg_time_ms < 1.0);
    
    std.debug.print("Average tool call time: {d:.3}ms\n", .{avg_time_ms});
}
```

## Debugging and Monitoring

### Debug Configuration

```zig
/// Debug configuration for development
pub const DebugConfig = struct {
    enable_request_logging: bool = true,
    enable_performance_tracking: bool = true,
    enable_memory_tracking: bool = true,
    log_level: LogLevel = .debug,

    pub const LogLevel = enum {
        debug,
        info,
        warning,
        @"error",
    };
};

/// Debug-enabled MCP server
pub const DebugMCPServer = struct {
    base_server: MCPCompliantServer,
    debug_config: DebugConfig,
    request_counter: std.atomic.Atomic(u64),
    performance_tracker: PerformanceTracker,

    pub fn processRequestDebug(self: *DebugMCPServer, request_json: []const u8) !MCPResponse {
        const request_id = self.request_counter.fetchAdd(1, .SeqCst);
        const start_time = std.time.nanoTimestamp();

        if (self.debug_config.enable_request_logging) {
            std.log.debug("Request #{}: {s}", .{ request_id, request_json });
        }

        const response = self.base_server.processRequest(request_json) catch |err| {
            std.log.err("Request #{} failed: {}", .{ request_id, err });
            return err;
        };

        if (self.debug_config.enable_performance_tracking) {
            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            
            std.log.debug("Request #{} completed in {d:.3}ms", .{ request_id, duration_ms });
            self.performance_tracker.recordRequest(duration_ms);
        }

        return response;
    }
};
```

### Memory Debugging

```zig
/// Memory debugging utilities
pub const MemoryDebugger = struct {
    allocations: std.HashMap(usize, AllocationInfo, std.hash_map.AutoContext(usize), 80),
    total_allocated: std.atomic.Atomic(usize),
    peak_allocated: std.atomic.Atomic(usize),
    allocator: Allocator,

    const AllocationInfo = struct {
        size: usize,
        timestamp: i64,
        stack_trace: [16]usize,
    };

    pub fn trackAllocation(self: *MemoryDebugger, ptr: [*]u8, size: usize) void {
        const current_total = self.total_allocated.fetchAdd(size, .SeqCst) + size;
        
        // Update peak if necessary
        const current_peak = self.peak_allocated.load(.SeqCst);
        if (current_total > current_peak) {
            _ = self.peak_allocated.compareAndSwap(current_peak, current_total, .SeqCst, .SeqCst);
        }

        // Record allocation
        var stack_trace: [16]usize = undefined;
        const stack_size = std.debug.captureStackTrace(2, &stack_trace);
        
        const info = AllocationInfo{
            .size = size,
            .timestamp = std.time.timestamp(),
            .stack_trace = stack_trace,
        };

        self.allocations.put(@intFromPtr(ptr), info) catch {};
    }

    pub fn trackDeallocation(self: *MemoryDebugger, ptr: [*]u8) void {
        const addr = @intFromPtr(ptr);
        
        if (self.allocations.fetchRemove(addr)) |entry| {
            _ = self.total_allocated.fetchSub(entry.value.size, .SeqCst);
        }
    }

    pub fn printMemoryReport(self: *MemoryDebugger) void {
        const total = self.total_allocated.load(.SeqCst);
        const peak = self.peak_allocated.load(.SeqCst);
        const active_allocations = self.allocations.count();

        std.log.info("Memory Report:");
        std.log.info("  Total allocated: {} bytes", .{total});
        std.log.info("  Peak allocated: {} bytes", .{peak});
        std.log.info("  Active allocations: {}", .{active_allocations});

        if (active_allocations > 0) {
            std.log.warn("Potential memory leaks detected:");
            var iterator = self.allocations.iterator();
            while (iterator.next()) |entry| {
                std.log.warn("  Leak at 0x{x}: {} bytes", .{ entry.key_ptr.*, entry.value_ptr.size });
            }
        }
    }
};
```

### Profiling Integration

```zig
/// Profiler for MCP operations
pub const MCPProfiler = struct {
    samples: std.HashMap([]const u8, ProfileData, std.hash_map.StringContext, 80),
    allocator: Allocator,

    const ProfileData = struct {
        total_calls: u64,
        total_time_ns: u64,
        min_time_ns: u64,
        max_time_ns: u64,
        percentiles: [5]u64, // P50, P75, P90, P95, P99
        recent_times: std.ArrayList(u64),

        pub fn addSample(self: *ProfileData, time_ns: u64) void {
            self.total_calls += 1;
            self.total_time_ns += time_ns;
            
            if (time_ns < self.min_time_ns) self.min_time_ns = time_ns;
            if (time_ns > self.max_time_ns) self.max_time_ns = time_ns;
            
            self.recent_times.append(time_ns) catch {};
            
            // Keep only recent samples for percentile calculation
            if (self.recent_times.items.len > 10000) {
                _ = self.recent_times.orderedRemove(0);
            }
            
            self.updatePercentiles();
        }

        fn updatePercentiles(self: *ProfileData) void {
            if (self.recent_times.items.len == 0) return;
            
            var sorted_times = std.ArrayList(u64).init(self.recent_times.allocator);
            defer sorted_times.deinit();
            
            sorted_times.appendSlice(self.recent_times.items) catch return;
            std.sort.sort(u64, sorted_times.items, {}, std.sort.asc(u64));
            
            const len = sorted_times.items.len;
            self.percentiles[0] = sorted_times.items[len * 50 / 100]; // P50
            self.percentiles[1] = sorted_times.items[len * 75 / 100]; // P75
            self.percentiles[2] = sorted_times.items[len * 90 / 100]; // P90
            self.percentiles[3] = sorted_times.items[len * 95 / 100]; // P95
            self.percentiles[4] = sorted_times.items[len * 99 / 100]; // P99
        }
    };

    pub fn recordOperation(self: *MCPProfiler, operation: []const u8, duration_ns: u64) !void {
        var result = try self.samples.getOrPut(operation);
        
        if (!result.found_existing) {
            result.value_ptr.* = ProfileData{
                .total_calls = 0,
                .total_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .max_time_ns = 0,
                .percentiles = [_]u64{0} ** 5,
                .recent_times = std.ArrayList(u64).init(self.allocator),
            };
        }

        result.value_ptr.addSample(duration_ns);
    }

    pub fn printProfile(self: *MCPProfiler) void {
        std.log.info("MCP Performance Profile:");
        
        var iterator = self.samples.iterator();
        while (iterator.next()) |entry| {
            const operation = entry.key_ptr.*;
            const data = entry.value_ptr.*;
            
            const avg_time_ms = @as(f64, @floatFromInt(data.total_time_ns / data.total_calls)) / 1_000_000.0;
            const p50_ms = @as(f64, @floatFromInt(data.percentiles[0])) / 1_000_000.0;
            const p99_ms = @as(f64, @floatFromInt(data.percentiles[4])) / 1_000_000.0;
            
            std.log.info("  {s}:", .{operation});
            std.log.info("    Calls: {}", .{data.total_calls});
            std.log.info("    Avg: {d:.3}ms", .{avg_time_ms});
            std.log.info("    P50: {d:.3}ms", .{p50_ms});
            std.log.info("    P99: {d:.3}ms", .{p99_ms});
        }
    }
};
```

## Contributing Guidelines

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Use meaningful variable and function names
- Add comprehensive documentation comments
- Include error handling for all operations

### Pull Request Process

1. **Fork and branch**: Create feature branch from `main`
2. **Implement changes**: Add new features or fixes
3. **Add tests**: Ensure comprehensive test coverage
4. **Update docs**: Update relevant documentation
5. **Performance test**: Verify no performance regressions
6. **Submit PR**: Include detailed description and test results

### Performance Requirements

All new tools and features must meet these performance targets:

- **Tool Response**: < 100ms P99 (target: < 10ms P50)
- **Memory Usage**: < 1MB per tool call
- **Memory Leaks**: Zero tolerance
- **Error Rate**: < 1% under normal load

This development guide provides the foundation for extending and contributing to the Agrama MCP server, ensuring high-quality, performant additions to the codebase.