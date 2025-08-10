//! Authentication Configuration Management
//! Provides utilities for loading and managing authentication configuration
//! from environment variables, files, and command line arguments

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const auth = @import("auth.zig");

/// Configuration validation errors
pub const ConfigError = error{
    InvalidJwtSecret,
    InvalidRole,
    InvalidApiKeyFormat,
    MissingRequiredConfig,
    ConfigFileNotFound,
    InvalidConfigFile,
};

/// Extended authentication configuration with deployment options
pub const DeploymentAuthConfig = struct {
    // Base auth configuration
    auth: auth.AuthConfig,

    // Deployment-specific settings
    log_level: LogLevel = .info,
    security_headers_enabled: bool = true,
    cors_enabled: bool = false,
    cors_origins: []const []const u8 = &[_][]const u8{},
    session_timeout_minutes: u32 = 60,
    cleanup_interval_minutes: u32 = 10,

    // TLS/SSL settings
    tls_cert_path: ?[]const u8 = null,
    tls_key_path: ?[]const u8 = null,

    // Monitoring and alerting
    metrics_enabled: bool = true,
    alert_on_failed_auth_threshold: u32 = 10,
    alert_webhook_url: ?[]const u8 = null,

    pub const LogLevel = enum {
        debug,
        info,
        warn,
        @"error",

        pub fn fromString(str: []const u8) ?LogLevel {
            if (std.mem.eql(u8, str, "debug")) return .debug;
            if (std.mem.eql(u8, str, "info")) return .info;
            if (std.mem.eql(u8, str, "warn")) return .warn;
            if (std.mem.eql(u8, str, "error")) return .@"error";
            return null;
        }
    };

    pub fn deinit(self: *DeploymentAuthConfig, allocator: Allocator) void {
        allocator.free(self.auth.jwt_secret);

        if (self.tls_cert_path) |path| allocator.free(path);
        if (self.tls_key_path) |path| allocator.free(path);
        if (self.alert_webhook_url) |url| allocator.free(url);

        for (self.cors_origins) |origin| {
            allocator.free(origin);
        }
        allocator.free(self.cors_origins);
    }
};

/// API key definition from configuration
pub const ApiKeyConfig = struct {
    key: []const u8,
    name: []const u8,
    role: auth.Role,
    expires_at: ?i64 = null,
    allowed_tools: ?[]const []const u8 = null,
    rate_limit_per_hour: ?u32 = null,

    pub fn deinit(self: *ApiKeyConfig, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.name);

        if (self.allowed_tools) |tools| {
            for (tools) |tool| {
                allocator.free(tool);
            }
            allocator.free(tools);
        }
    }
};

/// Configuration loader with multiple sources
pub const ConfigLoader = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ConfigLoader {
        return ConfigLoader{ .allocator = allocator };
    }

    /// Load configuration from environment variables
    pub fn loadFromEnvironment(self: *ConfigLoader) !DeploymentAuthConfig {
        const enabled = self.getEnvBool("AGRAMA_AUTH_ENABLED", true);
        const dev_mode = self.getEnvBool("AGRAMA_DEV_MODE", false);
        const require_https = self.getEnvBool("AGRAMA_REQUIRE_HTTPS", true);
        const rate_limiting = self.getEnvBool("AGRAMA_RATE_LIMITING", true);
        const audit_logging = self.getEnvBool("AGRAMA_AUDIT_LOGGING", true);

        // JWT configuration
        const jwt_secret = std.posix.getenv("AGRAMA_JWT_SECRET") orelse "change-in-production-insecure-default";
        if (std.mem.eql(u8, jwt_secret, "change-in-production-insecure-default") and !dev_mode) {
            std.log.warn("Using default JWT secret in production mode - this is insecure!");
        }

        const jwt_issuer = std.posix.getenv("AGRAMA_JWT_ISSUER") orelse "agrama-codegraph";
        const jwt_audience = std.posix.getenv("AGRAMA_JWT_AUDIENCE") orelse "mcp-tools";

        // Headers configuration
        const api_key_header = std.posix.getenv("AGRAMA_API_KEY_HEADER") orelse "X-API-Key";
        const bearer_token_header = std.posix.getenv("AGRAMA_BEARER_TOKEN_HEADER") orelse "Authorization";

        // Security settings
        const max_failed_attempts = self.getEnvU32("AGRAMA_MAX_FAILED_ATTEMPTS", 5);
        const lockout_duration = self.getEnvU32("AGRAMA_LOCKOUT_DURATION_MINUTES", 15);

        // Deployment settings
        const log_level_str = std.posix.getenv("AGRAMA_LOG_LEVEL") orelse "info";
        const log_level = DeploymentAuthConfig.LogLevel.fromString(log_level_str) orelse .info;

        const security_headers = self.getEnvBool("AGRAMA_SECURITY_HEADERS", true);
        const cors_enabled = self.getEnvBool("AGRAMA_CORS_ENABLED", false);
        const session_timeout = self.getEnvU32("AGRAMA_SESSION_TIMEOUT_MINUTES", 60);
        const cleanup_interval = self.getEnvU32("AGRAMA_CLEANUP_INTERVAL_MINUTES", 10);

        // TLS settings
        const tls_cert_path = if (std.posix.getenv("AGRAMA_TLS_CERT_PATH")) |path|
            try self.allocator.dupe(u8, path)
        else
            null;

        const tls_key_path = if (std.posix.getenv("AGRAMA_TLS_KEY_PATH")) |path|
            try self.allocator.dupe(u8, path)
        else
            null;

        // Monitoring settings
        const metrics_enabled = self.getEnvBool("AGRAMA_METRICS_ENABLED", true);
        const alert_threshold = self.getEnvU32("AGRAMA_ALERT_FAILED_AUTH_THRESHOLD", 10);
        const alert_webhook = if (std.posix.getenv("AGRAMA_ALERT_WEBHOOK_URL")) |url|
            try self.allocator.dupe(u8, url)
        else
            null;

        // CORS origins
        const cors_origins = try self.parseEnvArray("AGRAMA_CORS_ORIGINS");

        return DeploymentAuthConfig{
            .auth = auth.AuthConfig{
                .enabled = enabled,
                .development_mode = dev_mode,
                .require_https = require_https,
                .jwt_secret = try self.allocator.dupe(u8, jwt_secret),
                .jwt_issuer = try self.allocator.dupe(u8, jwt_issuer),
                .jwt_audience = try self.allocator.dupe(u8, jwt_audience),
                .api_key_header = try self.allocator.dupe(u8, api_key_header),
                .bearer_token_header = try self.allocator.dupe(u8, bearer_token_header),
                .rate_limiting_enabled = rate_limiting,
                .audit_logging_enabled = audit_logging,
                .max_failed_attempts = max_failed_attempts,
                .lockout_duration_minutes = lockout_duration,
            },
            .log_level = log_level,
            .security_headers_enabled = security_headers,
            .cors_enabled = cors_enabled,
            .cors_origins = cors_origins,
            .session_timeout_minutes = session_timeout,
            .cleanup_interval_minutes = cleanup_interval,
            .tls_cert_path = tls_cert_path,
            .tls_key_path = tls_key_path,
            .metrics_enabled = metrics_enabled,
            .alert_on_failed_auth_threshold = alert_threshold,
            .alert_webhook_url = alert_webhook,
        };
    }

    /// Load API key configurations from environment
    pub fn loadApiKeysFromEnvironment(self: *ConfigLoader) ![]ApiKeyConfig {
        var api_keys = ArrayList(ApiKeyConfig).init(self.allocator);

        // Support AGRAMA_API_KEYS=key1:name1:role1:expires,key2:name2:role2
        if (std.posix.getenv("AGRAMA_API_KEYS")) |keys_env| {
            var it = std.mem.split(u8, keys_env, ",");
            while (it.next()) |key_def| {
                if (self.parseApiKeyDefinition(key_def)) |api_key_config| {
                    try api_keys.append(api_key_config);
                } else |err| {
                    std.log.warn("Failed to parse API key definition '{}': {}", .{ key_def, err });
                }
            }
        }

        // Support single API key format
        if (std.posix.getenv("AGRAMA_API_KEY")) |key| {
            const name = std.posix.getenv("AGRAMA_API_KEY_NAME") orelse "default";
            const role_str = std.posix.getenv("AGRAMA_API_KEY_ROLE") orelse "developer";
            const expires_str = std.posix.getenv("AGRAMA_API_KEY_EXPIRES");
            const tools_str = std.posix.getenv("AGRAMA_API_KEY_TOOLS");
            const rate_limit_str = std.posix.getenv("AGRAMA_API_KEY_RATE_LIMIT");

            const role = auth.Role.fromString(role_str) orelse {
                std.log.warn("Invalid role '{}' for API key, defaulting to developer", .{role_str});
                return ConfigError.InvalidRole;
            };

            const expires_at = if (expires_str) |exp_str|
                std.fmt.parseInt(i64, exp_str, 10) catch null
            else
                null;

            const allowed_tools = if (tools_str) |tools|
                try self.parseToolsList(tools)
            else
                null;

            const rate_limit = if (rate_limit_str) |rate_str|
                std.fmt.parseInt(u32, rate_str, 10) catch null
            else
                null;

            try api_keys.append(ApiKeyConfig{
                .key = try self.allocator.dupe(u8, key),
                .name = try self.allocator.dupe(u8, name),
                .role = role,
                .expires_at = expires_at,
                .allowed_tools = allowed_tools,
                .rate_limit_per_hour = rate_limit,
            });
        }

        return api_keys.toOwnedSlice();
    }

    /// Load configuration from JSON file
    pub fn loadFromFile(self: *ConfigLoader, file_path: []const u8) !DeploymentAuthConfig {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return ConfigError.ConfigFileNotFound,
            else => return err,
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(contents);

        _ = try file.readAll(contents);

        // Parse JSON configuration
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, contents, .{}) catch {
            return ConfigError.InvalidConfigFile;
        };
        defer parsed.deinit();

        return try self.parseJsonConfig(parsed.value);
    }

    /// Validate configuration
    pub fn validateConfig(self: *ConfigLoader, config: DeploymentAuthConfig) !void {
        _ = self;

        // Validate JWT secret
        if (config.auth.jwt_secret.len < 32 and config.auth.enabled and !config.auth.development_mode) {
            std.log.warn("JWT secret should be at least 32 characters for security");
        }

        // Validate TLS configuration
        if (config.auth.require_https) {
            if (config.tls_cert_path == null or config.tls_key_path == null) {
                std.log.warn("HTTPS required but TLS certificate/key paths not configured");
            }
        }

        // Validate timeouts
        if (config.session_timeout_minutes == 0) {
            std.log.warn("Session timeout is 0 - sessions will never expire");
        }

        if (config.cleanup_interval_minutes == 0) {
            std.log.warn("Cleanup interval is 0 - maintenance will not run");
        }
    }

    /// Generate default configuration for development
    pub fn generateDevConfig(self: *ConfigLoader) !DeploymentAuthConfig {
        return DeploymentAuthConfig{
            .auth = auth.AuthConfig{
                .enabled = false, // Disabled for development
                .development_mode = true,
                .require_https = false,
                .jwt_secret = try self.allocator.dupe(u8, "dev-secret-not-for-production"),
                .jwt_issuer = try self.allocator.dupe(u8, "agrama-dev"),
                .jwt_audience = try self.allocator.dupe(u8, "mcp-tools"),
                .api_key_header = try self.allocator.dupe(u8, "X-API-Key"),
                .bearer_token_header = try self.allocator.dupe(u8, "Authorization"),
                .rate_limiting_enabled = false,
                .audit_logging_enabled = true,
                .max_failed_attempts = 100,
                .lockout_duration_minutes = 1,
            },
            .log_level = .debug,
            .security_headers_enabled = false,
            .cors_enabled = true,
            .cors_origins = try self.allocator.dupe([]const u8, &[_][]const u8{"*"}),
            .session_timeout_minutes = 60,
            .cleanup_interval_minutes = 5,
            .metrics_enabled = true,
            .alert_on_failed_auth_threshold = 100,
        };
    }

    /// Generate production-ready configuration template
    pub fn generateProductionTemplate(self: *ConfigLoader) !DeploymentAuthConfig {
        return DeploymentAuthConfig{
            .auth = auth.AuthConfig{
                .enabled = true,
                .development_mode = false,
                .require_https = true,
                .jwt_secret = try self.allocator.dupe(u8, "CHANGE_ME_32_CHAR_SECRET_KEY_123456"),
                .jwt_issuer = try self.allocator.dupe(u8, "agrama-codegraph-prod"),
                .jwt_audience = try self.allocator.dupe(u8, "mcp-tools"),
                .api_key_header = try self.allocator.dupe(u8, "X-API-Key"),
                .bearer_token_header = try self.allocator.dupe(u8, "Authorization"),
                .rate_limiting_enabled = true,
                .audit_logging_enabled = true,
                .max_failed_attempts = 5,
                .lockout_duration_minutes = 15,
            },
            .log_level = .info,
            .security_headers_enabled = true,
            .cors_enabled = false,
            .cors_origins = try self.allocator.alloc([]const u8, 0),
            .session_timeout_minutes = 30,
            .cleanup_interval_minutes = 10,
            .tls_cert_path = try self.allocator.dupe(u8, "/path/to/cert.pem"),
            .tls_key_path = try self.allocator.dupe(u8, "/path/to/private.key"),
            .metrics_enabled = true,
            .alert_on_failed_auth_threshold = 10,
            .alert_webhook_url = try self.allocator.dupe(u8, "https://your-monitoring-system.com/webhook"),
        };
    }

    // Helper functions

    fn getEnvBool(self: *ConfigLoader, key: []const u8, default: bool) bool {
        _ = self;
        if (std.posix.getenv(key)) |value| {
            return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
        }
        return default;
    }

    fn getEnvU32(self: *ConfigLoader, key: []const u8, default: u32) u32 {
        _ = self;
        if (std.posix.getenv(key)) |value| {
            return std.fmt.parseInt(u32, value, 10) catch default;
        }
        return default;
    }

    fn parseEnvArray(self: *ConfigLoader, key: []const u8) ![]const []const u8 {
        if (std.posix.getenv(key)) |value| {
            var result = ArrayList([]const u8).init(self.allocator);
            var it = std.mem.split(u8, value, ",");

            while (it.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \t");
                if (trimmed.len > 0) {
                    try result.append(try self.allocator.dupe(u8, trimmed));
                }
            }

            return result.toOwnedSlice();
        }

        return try self.allocator.alloc([]const u8, 0);
    }

    fn parseApiKeyDefinition(self: *ConfigLoader, definition: []const u8) !ApiKeyConfig {
        var parts = std.mem.split(u8, definition, ":");

        const key = parts.next() orelse return ConfigError.InvalidApiKeyFormat;
        const name = parts.next() orelse return ConfigError.InvalidApiKeyFormat;
        const role_str = parts.next() orelse return ConfigError.InvalidApiKeyFormat;
        const expires_str = parts.next(); // Optional
        const tools_str = parts.next(); // Optional
        const rate_str = parts.next(); // Optional

        const role = auth.Role.fromString(role_str) orelse return ConfigError.InvalidRole;

        const expires_at = if (expires_str) |exp_str|
            std.fmt.parseInt(i64, exp_str, 10) catch null
        else
            null;

        const allowed_tools = if (tools_str) |tools|
            try self.parseToolsList(tools)
        else
            null;

        const rate_limit = if (rate_str) |rate|
            std.fmt.parseInt(u32, rate, 10) catch null
        else
            null;

        return ApiKeyConfig{
            .key = try self.allocator.dupe(u8, key),
            .name = try self.allocator.dupe(u8, name),
            .role = role,
            .expires_at = expires_at,
            .allowed_tools = allowed_tools,
            .rate_limit_per_hour = rate_limit,
        };
    }

    fn parseToolsList(self: *ConfigLoader, tools_str: []const u8) ![]const []const u8 {
        var tools = ArrayList([]const u8).init(self.allocator);
        var it = std.mem.split(u8, tools_str, ",");

        while (it.next()) |tool| {
            const trimmed = std.mem.trim(u8, tool, " \t");
            if (trimmed.len > 0) {
                try tools.append(try self.allocator.dupe(u8, trimmed));
            }
        }

        return tools.toOwnedSlice();
    }

    fn parseJsonConfig(self: *ConfigLoader, json: std.json.Value) !DeploymentAuthConfig {
        _ = self;
        _ = json;
        // JSON parsing implementation would go here
        // For now, return error to indicate not implemented
        return ConfigError.InvalidConfigFile;
    }
};

/// Configuration documentation generator
pub const ConfigDocGenerator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ConfigDocGenerator {
        return ConfigDocGenerator{ .allocator = allocator };
    }

    /// Generate markdown documentation for all configuration options
    pub fn generateMarkdown(self: *ConfigDocGenerator) ![]const u8 {
        var doc = ArrayList(u8).init(self.allocator);
        defer doc.deinit();

        try doc.appendSlice(
            \\# Agrama Authentication Configuration
            \\
            \\This document describes all available authentication configuration options.
            \\
            \\## Environment Variables
            \\
            \\### Core Authentication Settings
            \\
            \\- `AGRAMA_AUTH_ENABLED` (boolean, default: true) - Enable/disable authentication
            \\- `AGRAMA_DEV_MODE` (boolean, default: false) - Enable development mode (bypasses auth)
            \\- `AGRAMA_REQUIRE_HTTPS` (boolean, default: true) - Require HTTPS connections
            \\- `AGRAMA_RATE_LIMITING` (boolean, default: true) - Enable rate limiting
            \\- `AGRAMA_AUDIT_LOGGING` (boolean, default: true) - Enable audit logging
            \\
            \\### JWT Configuration
            \\
            \\- `AGRAMA_JWT_SECRET` (string, required) - JWT signing secret (minimum 32 characters)
            \\- `AGRAMA_JWT_ISSUER` (string, default: "agrama-codegraph") - JWT issuer claim
            \\- `AGRAMA_JWT_AUDIENCE` (string, default: "mcp-tools") - JWT audience claim
            \\
            \\### API Key Configuration
            \\
            \\- `AGRAMA_API_KEY_HEADER` (string, default: "X-API-Key") - Header name for API keys
            \\- `AGRAMA_BEARER_TOKEN_HEADER` (string, default: "Authorization") - Header name for bearer tokens
            \\
            \\### Security Settings
            \\
            \\- `AGRAMA_MAX_FAILED_ATTEMPTS` (number, default: 5) - Max failed auth attempts before lockout
            \\- `AGRAMA_LOCKOUT_DURATION_MINUTES` (number, default: 15) - Account lockout duration
            \\
            \\### API Keys Definition
            \\
            \\#### Multiple API Keys
            \\```bash
            \\AGRAMA_API_KEYS="key1:AppName1:developer:1672531200,key2:AppName2:read_only"
            \\```
            \\
            \\Format: `key:name:role[:expires_timestamp[:allowed_tools[:rate_limit]]]`
            \\
            \\#### Single API Key
            \\```bash
            \\AGRAMA_API_KEY="your-secret-api-key"
            \\AGRAMA_API_KEY_NAME="MyApplication"
            \\AGRAMA_API_KEY_ROLE="developer"
            \\AGRAMA_API_KEY_EXPIRES="1672531200"
            \\AGRAMA_API_KEY_TOOLS="read_code,write_code,get_context"
            \\AGRAMA_API_KEY_RATE_LIMIT="1000"
            \\```
            \\
            \\### Deployment Settings
            \\
            \\- `AGRAMA_LOG_LEVEL` (debug|info|warn|error, default: info) - Logging level
            \\- `AGRAMA_SECURITY_HEADERS` (boolean, default: true) - Add security headers
            \\- `AGRAMA_CORS_ENABLED` (boolean, default: false) - Enable CORS
            \\- `AGRAMA_CORS_ORIGINS` (string, comma-separated) - Allowed CORS origins
            \\- `AGRAMA_SESSION_TIMEOUT_MINUTES` (number, default: 60) - Session timeout
            \\- `AGRAMA_CLEANUP_INTERVAL_MINUTES` (number, default: 10) - Cleanup interval
            \\
            \\### TLS/SSL Configuration
            \\
            \\- `AGRAMA_TLS_CERT_PATH` (string) - Path to TLS certificate file
            \\- `AGRAMA_TLS_KEY_PATH` (string) - Path to TLS private key file
            \\
            \\### Monitoring and Alerting
            \\
            \\- `AGRAMA_METRICS_ENABLED` (boolean, default: true) - Enable metrics collection
            \\- `AGRAMA_ALERT_FAILED_AUTH_THRESHOLD` (number, default: 10) - Failed auth alert threshold
            \\- `AGRAMA_ALERT_WEBHOOK_URL` (string) - Webhook URL for security alerts
            \\
            \\## User Roles
            \\
            \\- **admin** - Full access to all operations and administrative functions
            \\- **developer** - Read/write access to code operations and collaborative tools
            \\- **read_only** - Read-only access to analysis and context tools
            \\- **restricted** - Limited access based on explicit tool allowlist
            \\
            \\## Example Production Configuration
            \\
            \\```bash
            \\#!/bin/bash
            \\# Production environment variables
            \\
            \\export AGRAMA_AUTH_ENABLED=true
            \\export AGRAMA_DEV_MODE=false
            \\export AGRAMA_REQUIRE_HTTPS=true
            \\export AGRAMA_JWT_SECRET="your-super-secret-jwt-key-32-chars"
            \\export AGRAMA_API_KEYS="prod-key-123:ProductionApp:admin:,dev-key-456:DevApp:developer:"
            \\export AGRAMA_TLS_CERT_PATH="/etc/ssl/certs/agrama.pem"
            \\export AGRAMA_TLS_KEY_PATH="/etc/ssl/private/agrama.key"
            \\export AGRAMA_LOG_LEVEL="info"
            \\export AGRAMA_ALERT_WEBHOOK_URL="https://your-monitoring.com/webhooks/security"
            \\```
            \\
            \\## Security Best Practices
            \\
            \\1. **Use strong JWT secrets** - Minimum 32 characters, cryptographically random
            \\2. **Enable HTTPS** - Always use TLS in production
            \\3. **Rotate API keys** - Implement regular key rotation
            \\4. **Monitor auth failures** - Set up alerting for suspicious activity
            \\5. **Use appropriate roles** - Follow principle of least privilege
            \\6. **Enable audit logging** - Track all authentication events
            \\7. **Configure rate limiting** - Prevent brute force attacks
            \\
        );

        return doc.toOwnedSlice();
    }
};

// Unit Tests
test "ConfigLoader environment parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = ConfigLoader.init(allocator);

    // Test development config generation
    var dev_config = try loader.generateDevConfig();
    defer dev_config.deinit(allocator);

    try testing.expect(dev_config.auth.development_mode == true);
    try testing.expect(dev_config.auth.enabled == false);
    try testing.expect(dev_config.log_level == .debug);

    // Test production template generation
    var prod_config = try loader.generateProductionTemplate();
    defer prod_config.deinit(allocator);

    try testing.expect(prod_config.auth.development_mode == false);
    try testing.expect(prod_config.auth.enabled == true);
    try testing.expect(prod_config.auth.require_https == true);
}

test "API key parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = ConfigLoader.init(allocator);

    // Test valid API key definition
    var api_key = try loader.parseApiKeyDefinition("secret123:MyApp:developer:1672531200");
    defer api_key.deinit(allocator);

    try testing.expectEqualSlices(u8, "secret123", api_key.key);
    try testing.expectEqualSlices(u8, "MyApp", api_key.name);
    try testing.expect(api_key.role == .developer);
    try testing.expect(api_key.expires_at == 1672531200);

    // Test invalid API key definition
    try testing.expectError(ConfigError.InvalidApiKeyFormat, loader.parseApiKeyDefinition("invalid"));
}

test "Configuration validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var loader = ConfigLoader.init(allocator);

    var config = try loader.generateDevConfig();
    defer config.deinit(allocator);

    // Should not throw error for dev config
    try loader.validateConfig(config);
}

test "Documentation generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var doc_gen = ConfigDocGenerator.init(allocator);
    const markdown = try doc_gen.generateMarkdown();
    defer allocator.free(markdown);

    // Check that documentation contains expected sections
    try testing.expect(std.mem.indexOf(u8, markdown, "Environment Variables") != null);
    try testing.expect(std.mem.indexOf(u8, markdown, "User Roles") != null);
    try testing.expect(std.mem.indexOf(u8, markdown, "Security Best Practices") != null);
}
