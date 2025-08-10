//! Authenticated MCP Server with comprehensive security framework
//! Extends the base MCP server with authentication, authorization, and audit logging

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Thread = std.Thread;
const Mutex = Thread.Mutex;

const Database = @import("database.zig").Database;
const MCPServer = @import("mcp_server.zig").MCPServer;
const MCPCompliantServer = @import("mcp_compliant_server.zig").MCPCompliantServer;
const WebSocketServer = @import("websocket.zig").WebSocketServer;
const auth = @import("auth.zig");

/// Security-enhanced request structure with authentication context
pub const AuthenticatedMCPRequest = struct {
    id: []const u8,
    method: []const u8,
    params: struct {
        name: []const u8,
        arguments: std.json.Value,
    },
    auth_context: ?auth.AuthContext = null,
    source_ip: ?[]const u8 = null,
    headers: ?std.StringHashMap([]const u8) = null,

    pub fn deinit(self: *AuthenticatedMCPRequest, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.method);
        allocator.free(self.params.name);
        self.params.arguments.deinit();

        if (self.source_ip) |ip| {
            allocator.free(ip);
        }

        if (self.headers) |*headers_map| {
            var iterator = headers_map.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            headers_map.deinit();
        }
    }
};

/// Enhanced response with security metadata
pub const AuthenticatedMCPResponse = struct {
    id: []const u8,
    result: ?std.json.Value = null,
    @"error": ?auth.AuthError = null,
    execution_time_ms: u64 = 0,
    user_id: ?[]const u8 = null,
    authenticated: bool = false,

    pub fn deinit(self: *AuthenticatedMCPResponse, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.result) |*result| {
            result.deinit();
        }
        if (self.user_id) |user| {
            allocator.free(user);
        }
    }
};

/// Security configuration for MCP tools
pub const ToolSecurityConfig = struct {
    name: []const u8,
    required_role: auth.Role,
    rate_limit_per_minute: ?u32 = null,
    audit_level: AuditLevel = .standard,

    pub const AuditLevel = enum {
        none, // No audit logging
        basic, // Log tool calls only
        standard, // Log calls and basic parameters
        detailed, // Log everything including full content
    };
};

/// Authenticated MCP Server with comprehensive security
pub const AuthenticatedMCPServer = struct {
    allocator: Allocator,
    base_server: MCPServer,
    auth_system: auth.AuthSystem,
    tool_security: HashMap([]const u8, ToolSecurityConfig, StringContext, std.hash_map.default_max_load_percentage),
    security_metrics: SecurityMetrics,
    mutex: Mutex,

    const StringContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    /// Security metrics tracking
    const SecurityMetrics = struct {
        authenticated_requests: u64 = 0,
        rejected_requests: u64 = 0,
        blocked_ips: u64 = 0,
        rate_limited_requests: u64 = 0,
        total_audit_events: u64 = 0,

        pub fn recordAuthenticatedRequest(self: *SecurityMetrics) void {
            self.authenticated_requests += 1;
        }

        pub fn recordRejectedRequest(self: *SecurityMetrics) void {
            self.rejected_requests += 1;
        }

        pub fn recordRateLimitedRequest(self: *SecurityMetrics) void {
            self.rate_limited_requests += 1;
        }
    };

    /// Initialize authenticated MCP server
    pub fn init(allocator: Allocator, database: *Database, auth_config: auth.AuthConfig) !AuthenticatedMCPServer {
        var base_server = MCPServer.init(allocator, database);
        var auth_system = auth.AuthSystem.init(allocator, auth_config);

        // Load API keys from environment
        try auth.loadApiKeysFromEnv(&auth_system);

        var server = AuthenticatedMCPServer{
            .allocator = allocator,
            .base_server = base_server,
            .auth_system = auth_system,
            .tool_security = HashMap([]const u8, ToolSecurityConfig, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .security_metrics = SecurityMetrics{},
            .mutex = Mutex{},
        };

        // Configure default tool security settings
        try server.configureDefaultToolSecurity();

        return server;
    }

    /// Clean up resources
    pub fn deinit(self: *AuthenticatedMCPServer) void {
        self.base_server.deinit();
        self.auth_system.deinit();

        // Clean up tool security configs
        var iterator = self.tool_security.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.name);
        }
        self.tool_security.deinit();
    }

    /// Configure default security settings for standard MCP tools
    fn configureDefaultToolSecurity(self: *AuthenticatedMCPServer) !void {
        // Read operations - accessible to all authenticated users
        try self.addToolSecurity("read_code", .read_only, 100, .standard);
        try self.addToolSecurity("get_context", .read_only, 50, .basic);
        try self.addToolSecurity("read_code_collaborative", .read_only, 100, .standard);

        // Write operations - require developer role or higher
        try self.addToolSecurity("write_code", .developer, 50, .detailed);
        try self.addToolSecurity("write_code_collaborative", .developer, 30, .detailed);

        // Administrative operations - admin only
        try self.addToolSecurity("get_server_stats", .admin, 10, .basic);
        try self.addToolSecurity("manage_agents", .admin, 5, .detailed);

        // Collaborative tools - developer access
        try self.addToolSecurity("update_cursor", .developer, 200, .basic);
        try self.addToolSecurity("get_collaborative_context", .developer, 100, .standard);
    }

    /// Add security configuration for a specific tool
    pub fn addToolSecurity(self: *AuthenticatedMCPServer, tool_name: []const u8, required_role: auth.Role, rate_limit: u32, audit_level: ToolSecurityConfig.AuditLevel) !void {
        const owned_name = try self.allocator.dupe(u8, tool_name);
        const config = ToolSecurityConfig{
            .name = owned_name,
            .required_role = required_role,
            .rate_limit_per_minute = rate_limit,
            .audit_level = audit_level,
        };

        try self.tool_security.put(owned_name, config);

        std.log.info("Configured security for tool '{}': role={s} rate_limit={} audit={s}", .{ tool_name, required_role.toString(), rate_limit, @tagName(audit_level) });
    }

    /// Register an agent with authentication
    pub fn registerAgent(self: *AuthenticatedMCPServer, agent_id: []const u8, agent_name: []const u8, headers: std.StringHashMap([]const u8)) !void {
        // Authenticate agent registration request
        const auth_context = self.auth_system.authenticate(headers, null) catch |err| {
            self.security_metrics.recordRejectedRequest();
            std.log.warn("Agent registration failed for '{}': authentication error", .{agent_id});
            return err;
        };

        // Require admin role for agent registration
        if (auth_context.role != .admin) {
            self.security_metrics.recordRejectedRequest();
            std.log.warn("Agent registration rejected for '{}': insufficient permissions (role={})", .{ agent_id, auth_context.role.toString() });
            return auth.AuthError.InsufficientPermissions;
        }

        // Register with base server
        try self.base_server.registerAgent(agent_id, agent_name);

        self.security_metrics.recordAuthenticatedRequest();
        std.log.info("Agent '{}' ({}) registered successfully by user '{}'", .{ agent_name, agent_id, auth_context.user_id });
    }

    /// Handle authenticated MCP request
    pub fn handleAuthenticatedRequest(self: *AuthenticatedMCPServer, request: AuthenticatedMCPRequest) !AuthenticatedMCPResponse {
        const start_time = std.time.milliTimestamp();

        var response = AuthenticatedMCPResponse{
            .id = try self.allocator.dupe(u8, request.id),
        };

        // Authenticate request if authentication is enabled
        const auth_context = if (request.headers) |headers| blk: {
            break :blk self.auth_system.authenticate(headers, request.source_ip) catch |err| {
                response.@"error" = err;
                response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                self.security_metrics.recordRejectedRequest();
                return response;
            };
        } else if (self.auth_system.config.development_mode) blk: {
            break :blk auth.AuthContext{
                .authenticated = true,
                .user_id = "dev-user",
                .role = .admin,
                .auth_method = .none,
                .allowed_tools = null,
            };
        } else {
            response.@"error" = auth.AuthError.MissingAuthHeader;
            response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            self.security_metrics.recordRejectedRequest();
            return response;
        };

        // Authorize tool access
        self.auth_system.authorize(auth_context, request.params.name) catch |err| {
            response.@"error" = err;
            response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            self.security_metrics.recordRejectedRequest();
            return response;
        };

        // Check tool-specific security requirements
        if (self.tool_security.get(request.params.name)) |tool_config| {
            // Verify role requirements
            if (@intFromEnum(auth_context.role) < @intFromEnum(tool_config.required_role)) {
                response.@"error" = auth.AuthError.InsufficientPermissions;
                response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
                self.security_metrics.recordRejectedRequest();
                return response;
            }

            // Apply tool-specific rate limiting (simplified implementation)
            if (tool_config.rate_limit_per_minute) |_| {
                // In a full implementation, this would check tool-specific rate limits
                // For now, we rely on the general authentication rate limiting
            }

            // Log audit event based on audit level
            try self.logToolAccess(auth_context, request.params.name, tool_config.audit_level, request.params.arguments);
        }

        // Execute the tool via base server
        const base_response = self.base_server.handleRequest(.{
            .id = request.id,
            .method = request.method,
            .params = request.params,
        }, auth_context.user_id) catch |err| {
            response.@"error" = err;
            response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            return response;
        };
        defer {
            var mutable_base_response = base_response;
            mutable_base_response.deinit(self.allocator);
        }

        // Copy result and metadata
        if (base_response.result) |result| {
            response.result = result; // Transfer ownership
        }

        response.execution_time_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        response.user_id = try self.allocator.dupe(u8, auth_context.user_id);
        response.authenticated = true;

        self.security_metrics.recordAuthenticatedRequest();

        return response;
    }

    /// Log tool access for audit trail
    fn logToolAccess(self: *AuthenticatedMCPServer, context: auth.AuthContext, tool_name: []const u8, audit_level: ToolSecurityConfig.AuditLevel, arguments: std.json.Value) !void {
        _ = self; // Prevent unused parameter warning

        switch (audit_level) {
            .none => {}, // No logging
            .basic => {
                std.log.info("TOOL_ACCESS: user={} tool={} role={}", .{ context.user_id, tool_name, context.role.toString() });
            },
            .standard => {
                std.log.info("TOOL_ACCESS: user={} tool={} role={} method={}", .{ context.user_id, tool_name, context.role.toString(), context.auth_method });
            },
            .detailed => {
                // In production, be careful about logging sensitive data
                const args_preview = if (arguments == .object and arguments.object.count() > 0) "..." else "{}";
                std.log.info("TOOL_ACCESS: user={} tool={} role={} method={} args={}", .{ context.user_id, tool_name, context.role.toString(), context.auth_method, args_preview });
            },
        }
    }

    /// Get comprehensive security statistics
    pub fn getSecurityStats(self: *AuthenticatedMCPServer) SecurityStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        const auth_stats = self.auth_system.getStats();
        const base_stats = self.base_server.getStats();

        return SecurityStats{
            .authenticated_requests = self.security_metrics.authenticated_requests,
            .rejected_requests = self.security_metrics.rejected_requests,
            .rate_limited_requests = self.security_metrics.rate_limited_requests,
            .total_api_keys = auth_stats.total_api_keys,
            .successful_authentications = auth_stats.successful_authentications,
            .failed_authentications = auth_stats.failed_authentications,
            .active_agents = base_stats.agents,
            .total_requests = base_stats.requests,
            .average_response_time_ms = base_stats.avg_response_ms,
        };
    }

    /// Get security report with recommendations
    pub fn getSecurityReport(self: *AuthenticatedMCPServer, allocator: Allocator) !SecurityReport {
        const stats = self.getSecurityStats();
        const auth_stats = self.auth_system.getStats();

        var recommendations = ArrayList([]const u8).init(allocator);

        // Analysis and recommendations
        if (auth_stats.failed_authentications > auth_stats.successful_authentications / 10) {
            try recommendations.append(try allocator.dupe(u8, "HIGH: Unusual number of failed authentications detected"));
        }

        if (auth_stats.locked_accounts > 0) {
            try recommendations.append(try std.fmt.allocPrint(allocator, "MEDIUM: {} accounts currently locked", .{auth_stats.locked_accounts}));
        }

        if (stats.rate_limited_requests > stats.authenticated_requests / 20) {
            try recommendations.append(try allocator.dupe(u8, "MEDIUM: High rate of rate-limited requests"));
        }

        if (!self.auth_system.config.enabled) {
            try recommendations.append(try allocator.dupe(u8, "CRITICAL: Authentication is disabled"));
        } else if (self.auth_system.config.development_mode) {
            try recommendations.append(try allocator.dupe(u8, "WARNING: Running in development mode with bypassed authentication"));
        }

        if (stats.total_api_keys == 0 and self.auth_system.config.enabled) {
            try recommendations.append(try allocator.dupe(u8, "WARNING: No API keys configured"));
        }

        if (recommendations.items.len == 0) {
            try recommendations.append(try allocator.dupe(u8, "OK: No security issues detected"));
        }

        return SecurityReport{
            .timestamp = std.time.timestamp(),
            .authentication_enabled = self.auth_system.config.enabled,
            .development_mode = self.auth_system.config.development_mode,
            .total_requests = stats.authenticated_requests + stats.rejected_requests,
            .success_rate = if (stats.authenticated_requests + stats.rejected_requests > 0)
                @as(f32, @floatFromInt(stats.authenticated_requests)) / @as(f32, @floatFromInt(stats.authenticated_requests + stats.rejected_requests))
            else
                1.0,
            .recommendations = try recommendations.toOwnedSlice(),
        };
    }

    /// Add WebSocket authentication
    pub fn authenticateWebSocketConnection(self: *AuthenticatedMCPServer, headers: std.StringHashMap([]const u8), source_ip: ?[]const u8) !auth.AuthContext {
        return self.auth_system.authenticate(headers, source_ip);
    }

    /// Perform security maintenance
    pub fn performSecurityMaintenance(self: *AuthenticatedMCPServer) void {
        self.auth_system.performMaintenance();

        std.log.debug("Security maintenance completed - Auth events: {}, Active rate limits: {}", .{
            self.auth_system.getStats().audit_events,
            self.auth_system.getStats().active_rate_limits,
        });
    }
};

/// Combined security statistics
pub const SecurityStats = struct {
    authenticated_requests: u64,
    rejected_requests: u64,
    rate_limited_requests: u64,
    total_api_keys: u32,
    successful_authentications: u32,
    failed_authentications: u32,
    active_agents: u32,
    total_requests: u64,
    average_response_time_ms: f64,
};

/// Security analysis report
pub const SecurityReport = struct {
    timestamp: i64,
    authentication_enabled: bool,
    development_mode: bool,
    total_requests: u64,
    success_rate: f32,
    recommendations: [][]const u8,

    pub fn deinit(self: *SecurityReport, allocator: Allocator) void {
        for (self.recommendations) |rec| {
            allocator.free(rec);
        }
        allocator.free(self.recommendations);
    }
};

/// Authenticated WebSocket server integration
pub const AuthenticatedWebSocketServer = struct {
    base_server: *WebSocketServer,
    auth_system: *auth.AuthSystem,

    pub fn init(base_server: *WebSocketServer, auth_system: *auth.AuthSystem) AuthenticatedWebSocketServer {
        return AuthenticatedWebSocketServer{
            .base_server = base_server,
            .auth_system = auth_system,
        };
    }

    /// Authenticate WebSocket connection before allowing access
    pub fn authenticateConnection(self: *AuthenticatedWebSocketServer, headers: std.StringHashMap([]const u8), source_ip: ?[]const u8) !auth.AuthContext {
        return self.auth_system.authenticate(headers, source_ip);
    }

    /// Send message to authenticated clients only
    pub fn broadcastAuthenticated(self: *AuthenticatedWebSocketServer, message: []const u8, min_role: auth.Role) void {
        // In a full implementation, this would track client authentication states
        // and only broadcast to clients with sufficient permissions
        _ = min_role;
        self.base_server.broadcast(message);
    }
};

// Unit Tests
test "AuthenticatedMCPServer initialization and configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const auth_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var server = try AuthenticatedMCPServer.init(allocator, &db, auth_config);
    defer server.deinit();

    // Test that default tool security is configured
    const read_config = server.tool_security.get("read_code");
    try testing.expect(read_config != null);
    try testing.expect(read_config.?.required_role == .read_only);

    const write_config = server.tool_security.get("write_code");
    try testing.expect(write_config != null);
    try testing.expect(write_config.?.required_role == .developer);
}

test "Tool security configuration and access control" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const auth_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var server = try AuthenticatedMCPServer.init(allocator, &db, auth_config);
    defer server.deinit();

    // Add test API keys
    try server.auth_system.addApiKey("dev-key", "Developer", .developer);
    try server.auth_system.addApiKey("readonly-key", "ReadOnly", .read_only);

    // Test custom tool security
    try server.addToolSecurity("custom_tool", .admin, 10, .detailed);

    const custom_config = server.tool_security.get("custom_tool");
    try testing.expect(custom_config != null);
    try testing.expect(custom_config.?.required_role == .admin);
    try testing.expect(custom_config.?.rate_limit_per_minute == 10);
}

test "Security statistics and reporting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const auth_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var server = try AuthenticatedMCPServer.init(allocator, &db, auth_config);
    defer server.deinit();

    // Get initial security stats
    const stats = server.getSecurityStats();
    try testing.expect(stats.authenticated_requests == 0);
    try testing.expect(stats.rejected_requests == 0);

    // Get security report
    var report = try server.getSecurityReport(allocator);
    defer report.deinit(allocator);

    try testing.expect(report.authentication_enabled == true);
    try testing.expect(report.development_mode == false);
    try testing.expect(report.recommendations.len > 0);
}

test "Development mode authentication bypass" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const auth_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = true, // Development mode
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var server = try AuthenticatedMCPServer.init(allocator, &db, auth_config);
    defer server.deinit();

    // Create request without headers (should work in dev mode)
    var request = AuthenticatedMCPRequest{
        .id = "test-id",
        .method = "tools/call",
        .params = .{
            .name = "read_code",
            .arguments = std.json.Value{ .object = std.json.ObjectMap.init(allocator) },
        },
        .headers = null, // No authentication headers
    };

    // This should succeed in development mode
    var response = try server.handleAuthenticatedRequest(request);
    defer response.deinit(allocator);

    try testing.expect(response.authenticated == true);
}
