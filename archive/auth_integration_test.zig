//! Authentication Integration Tests
//! Comprehensive tests for the authentication and authorization system

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Database = @import("../src/database.zig").Database;
const auth = @import("../src/auth.zig");
const auth_config = @import("../src/auth_config.zig");
const AuthenticatedMCPServer = @import("../src/authenticated_mcp_server.zig").AuthenticatedMCPServer;
const AuthenticatedWebSocketServer = @import("../src/authenticated_websocket.zig").AuthenticatedWebSocketServer;

/// Integration test suite for authentication system
const AuthenticationIntegrationTest = struct {
    allocator: Allocator,
    database: Database,
    auth_system: auth.AuthSystem,
    mcp_server: AuthenticatedMCPServer,

    pub fn init(allocator: Allocator) !AuthenticationIntegrationTest {
        var database = Database.init(allocator);

        const auth_config_obj = auth.AuthConfig{
            .enabled = true,
            .development_mode = false,
            .jwt_secret = "test-secret-for-integration-testing",
            .rate_limiting_enabled = true,
            .audit_logging_enabled = true,
        };

        var auth_system = auth.AuthSystem.init(allocator, auth_config_obj);
        var mcp_server = try AuthenticatedMCPServer.init(allocator, &database, auth_config_obj);

        // Set up test API keys
        try auth_system.addApiKey("admin-test-key", "Admin Test User", .admin);
        try auth_system.addApiKey("dev-test-key", "Developer Test User", .developer);
        try auth_system.addApiKey("readonly-test-key", "ReadOnly Test User", .read_only);
        try auth_system.addApiKey("restricted-test-key", "Restricted Test User", .restricted);

        return AuthenticationIntegrationTest{
            .allocator = allocator,
            .database = database,
            .auth_system = auth_system,
            .mcp_server = mcp_server,
        };
    }

    pub fn deinit(self: *AuthenticationIntegrationTest) void {
        self.mcp_server.deinit();
        self.auth_system.deinit();
        self.database.deinit();
    }

    /// Test complete authentication flow with different roles
    pub fn testCompleteAuthenticationFlow(self: *AuthenticationIntegrationTest) !void {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // Test admin authentication
        try headers.put("X-API-Key", "admin-test-key");

        const admin_context = try self.auth_system.authenticate(headers, "127.0.0.1");
        try testing.expect(admin_context.authenticated == true);
        try testing.expectEqualSlices(u8, "Admin Test User", admin_context.user_id);
        try testing.expect(admin_context.role == .admin);

        // Test admin can access all tools
        try self.auth_system.authorize(admin_context, "read_code");
        try self.auth_system.authorize(admin_context, "write_code");
        try self.auth_system.authorize(admin_context, "admin_tool");

        // Test developer authentication
        _ = headers.remove("X-API-Key");
        try headers.put("X-API-Key", "dev-test-key");

        const dev_context = try self.auth_system.authenticate(headers, "127.0.0.1");
        try testing.expect(dev_context.authenticated == true);
        try testing.expect(dev_context.role == .developer);

        // Test developer can access development tools
        try self.auth_system.authorize(dev_context, "read_code");
        try self.auth_system.authorize(dev_context, "write_code");

        // Test read-only authentication
        _ = headers.remove("X-API-Key");
        try headers.put("X-API-Key", "readonly-test-key");

        const readonly_context = try self.auth_system.authenticate(headers, "127.0.0.1");
        try testing.expect(readonly_context.authenticated == true);
        try testing.expect(readonly_context.role == .read_only);

        // Test read-only can access read tools but not write tools
        try self.auth_system.authorize(readonly_context, "read_code");
        try testing.expectError(auth.AuthError.InsufficientPermissions, self.auth_system.authorize(readonly_context, "write_code"));
    }

    /// Test MCP server authentication integration
    pub fn testMCPServerAuthentication(self: *AuthenticationIntegrationTest) !void {
        // Create authenticated MCP request
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("X-API-Key", "dev-test-key");

        var request_args = std.json.ObjectMap.init(self.allocator);
        defer request_args.deinit();
        try request_args.put("path", std.json.Value{ .string = "test.txt" });

        const authenticated_request = @import("../src/authenticated_mcp_server.zig").AuthenticatedMCPRequest{
            .id = "test-request-1",
            .method = "tools/call",
            .params = .{
                .name = "read_code",
                .arguments = std.json.Value{ .object = request_args },
            },
            .headers = headers,
            .source_ip = "127.0.0.1",
        };

        // Handle authenticated request
        var response = try self.mcp_server.handleAuthenticatedRequest(authenticated_request);
        defer response.deinit(self.allocator);

        try testing.expect(response.authenticated == true);
        try testing.expectEqualSlices(u8, "Developer Test User", response.user_id.?);
        try testing.expect(response.@"error" == null);
    }

    /// Test rate limiting functionality
    pub fn testRateLimiting(self: *AuthenticationIntegrationTest) !void {
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();
        try headers.put("X-API-Key", "restricted-test-key");

        // Make multiple rapid requests (simplified test)
        var request_count: u32 = 0;
        while (request_count < 10) {
            const context = self.auth_system.authenticate(headers, "127.0.0.1") catch |err| switch (err) {
                auth.AuthError.RateLimitExceeded => {
                    // Expected after rate limit is hit
                    try testing.expect(request_count > 0);
                    return;
                },
                else => return err,
            };

            try testing.expect(context.authenticated == true);
            request_count += 1;
        }
    }

    /// Test audit logging functionality
    pub fn testAuditLogging(self: *AuthenticationIntegrationTest) !void {
        const initial_stats = self.auth_system.getStats();

        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // Successful authentication
        try headers.put("X-API-Key", "admin-test-key");
        const context = try self.auth_system.authenticate(headers, "127.0.0.1");
        try self.auth_system.authorize(context, "read_code");

        // Failed authentication
        _ = headers.remove("X-API-Key");
        try headers.put("X-API-Key", "invalid-key");
        _ = self.auth_system.authenticate(headers, "127.0.0.1") catch {};

        const final_stats = self.auth_system.getStats();

        // Verify audit events were recorded
        try testing.expect(final_stats.successful_authentications > initial_stats.successful_authentications);
        try testing.expect(final_stats.failed_authentications > initial_stats.failed_authentications);
    }

    /// Test security statistics and reporting
    pub fn testSecurityReporting(self: *AuthenticationIntegrationTest) !void {
        // Generate some authentication activity
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // Successful authentications
        try headers.put("X-API-Key", "admin-test-key");
        _ = try self.auth_system.authenticate(headers, "127.0.0.1");

        try headers.put("X-API-Key", "dev-test-key");
        _ = try self.auth_system.authenticate(headers, "127.0.0.1");

        // Failed authentication
        try headers.put("X-API-Key", "invalid-key");
        _ = self.auth_system.authenticate(headers, "127.0.0.1") catch {};

        // Get security statistics
        const security_stats = self.mcp_server.getSecurityStats();
        try testing.expect(security_stats.total_api_keys >= 4);
        try testing.expect(security_stats.successful_authentications >= 2);
        try testing.expect(security_stats.failed_authentications >= 1);

        // Get security report
        var security_report = try self.mcp_server.getSecurityReport(self.allocator);
        defer security_report.deinit(self.allocator);

        try testing.expect(security_report.authentication_enabled == true);
        try testing.expect(security_report.development_mode == false);
        try testing.expect(security_report.recommendations.len > 0);
    }

    /// Test tool-specific security configuration
    pub fn testToolSecurityConfiguration(self: *AuthenticationIntegrationTest) !void {
        // Add custom tool security
        try self.mcp_server.addToolSecurity("custom_admin_tool", .admin, 5, .detailed);

        var headers = std.StringHashMap([]const u8).init(self.allocator);
        defer headers.deinit();

        // Test that developer cannot access admin-only tool
        try headers.put("X-API-Key", "dev-test-key");
        const dev_context = try self.auth_system.authenticate(headers, "127.0.0.1");

        try testing.expectError(auth.AuthError.InsufficientPermissions, self.auth_system.authorize(dev_context, "custom_admin_tool"));

        // Test that admin can access the tool
        _ = headers.remove("X-API-Key");
        try headers.put("X-API-Key", "admin-test-key");
        const admin_context = try self.auth_system.authenticate(headers, "127.0.0.1");

        try self.auth_system.authorize(admin_context, "custom_admin_tool");
    }
};

test "authentication configuration loading" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config_loader = auth_config.ConfigLoader.init(allocator);

    // Test development configuration
    var dev_config = try config_loader.generateDevConfig();
    defer dev_config.deinit(allocator);

    try testing.expect(dev_config.auth.development_mode == true);
    try testing.expect(dev_config.auth.enabled == false);

    // Validate configuration
    try config_loader.validateConfig(dev_config);

    // Test production configuration
    var prod_config = try config_loader.generateProductionTemplate();
    defer prod_config.deinit(allocator);

    try testing.expect(prod_config.auth.development_mode == false);
    try testing.expect(prod_config.auth.enabled == true);
}

test "API key configuration parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config_loader = auth_config.ConfigLoader.init(allocator);

    // Test API key parsing
    var api_key = try config_loader.parseApiKeyDefinition("key123:TestApp:admin:1672531200");
    defer api_key.deinit(allocator);

    try testing.expectEqualSlices(u8, "key123", api_key.key);
    try testing.expectEqualSlices(u8, "TestApp", api_key.name);
    try testing.expect(api_key.role == .admin);
    try testing.expect(api_key.expires_at == 1672531200);
}

test "full authentication system integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var integration_test = try AuthenticationIntegrationTest.init(allocator);
    defer integration_test.deinit();

    // Run all integration tests
    try integration_test.testCompleteAuthenticationFlow();
    try integration_test.testMCPServerAuthentication();
    try integration_test.testAuditLogging();
    try integration_test.testSecurityReporting();
    try integration_test.testToolSecurityConfiguration();

    std.log.info("All authentication integration tests passed successfully!");
}

test "development mode authentication bypass" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dev_config = auth.AuthConfig{
        .enabled = true,
        .development_mode = true, // Enable dev mode
        .jwt_secret = "test-secret",
    };

    var auth_system = auth.AuthSystem.init(allocator, dev_config);
    defer auth_system.deinit();

    // Empty headers should authenticate in dev mode
    var empty_headers = std.StringHashMap([]const u8).init(allocator);
    defer empty_headers.deinit();

    const context = try auth_system.authenticate(empty_headers, null);
    try testing.expect(context.authenticated == true);
    try testing.expect(context.role == .admin);
    try testing.expect(context.auth_method == .none);

    // Should be able to access all tools in dev mode
    try auth_system.authorize(context, "read_code");
    try auth_system.authorize(context, "write_code");
    try auth_system.authorize(context, "admin_tool");
}

test "authentication error handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const auth_config_obj = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
    };

    var auth_system = auth.AuthSystem.init(allocator, auth_config_obj);
    defer auth_system.deinit();

    try auth_system.addApiKey("valid-key", "Valid User", .developer);

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    // Test missing authentication header
    try testing.expectError(auth.AuthError.MissingAuthHeader, auth_system.authenticate(headers, null));

    // Test invalid API key
    try headers.put("X-API-Key", "invalid-key");
    try testing.expectError(auth.AuthError.InvalidApiKey, auth_system.authenticate(headers, null));

    // Test valid authentication
    _ = headers.remove("X-API-Key");
    try headers.put("X-API-Key", "valid-key");
    const context = try auth_system.authenticate(headers, null);
    try testing.expect(context.authenticated == true);

    // Test insufficient permissions
    try testing.expectError(auth.AuthError.InsufficientPermissions, auth_system.authorize(context, "admin_only_tool"));
}

test "authentication performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const auth_config_obj = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret-for-performance",
        .rate_limiting_enabled = false, // Disable for performance test
        .audit_logging_enabled = false, // Disable for performance test
    };

    var auth_system = auth.AuthSystem.init(allocator, auth_config_obj);
    defer auth_system.deinit();

    // Add test API key
    try auth_system.addApiKey("perf-test-key", "Performance Test User", .developer);

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-API-Key", "perf-test-key");

    // Measure authentication performance
    const iterations = 1000;
    const start_time = std.time.milliTimestamp();

    var i: u32 = 0;
    while (i < iterations) {
        const context = try auth_system.authenticate(headers, "127.0.0.1");
        try auth_system.authorize(context, "read_code");
        i += 1;
    }

    const end_time = std.time.milliTimestamp();
    const duration_ms = end_time - start_time;
    const avg_time_per_auth = @as(f64, @floatFromInt(duration_ms)) / @as(f64, @floatFromInt(iterations));

    std.log.info("Authentication performance: {} iterations in {}ms (avg: {d:.2}ms per auth)", .{ iterations, duration_ms, avg_time_per_auth });

    // Performance target: sub-1ms authentication
    try testing.expect(avg_time_per_auth < 1.0);
}

test "WebSocket authentication integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const auth_config_obj = auth.AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
    };

    var auth_system = auth.AuthSystem.init(allocator, auth_config_obj);
    defer auth_system.deinit();

    try auth_system.addApiKey("ws-test-key", "WebSocket Test User", .developer);

    var ws_server = AuthenticatedWebSocketServer.init(allocator, 8080, &auth_system);
    defer ws_server.deinit();

    // Test WebSocket authentication
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-API-Key", "ws-test-key");

    const ws_auth_context = try ws_server.authenticateConnection(headers, "127.0.0.1");
    try testing.expect(ws_auth_context.authenticated == true);
    try testing.expectEqualSlices(u8, "WebSocket Test User", ws_auth_context.user_id);
    try testing.expect(ws_auth_context.role == .developer);
}
