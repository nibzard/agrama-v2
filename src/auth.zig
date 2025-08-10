//! Agrama MCP Authentication and Authorization Framework
//! Provides secure API key and JWT token authentication for MCP operations
//! Supports role-based access control and comprehensive audit logging

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Mutex = std.Thread.Mutex;
const crypto = std.crypto;
const base64 = std.base64;
const json = std.json;

/// Authentication error types
pub const AuthError = error{
    InvalidCredentials,
    InvalidToken,
    TokenExpired,
    InsufficientPermissions,
    RateLimitExceeded,
    InvalidApiKey,
    MissingAuthHeader,
    UnsupportedAuthMethod,
    AuthenticationDisabled,
};

/// User roles for role-based access control
pub const Role = enum {
    admin, // Full access to all operations
    developer, // Read/write access to code operations
    read_only, // Read-only access to analysis tools
    restricted, // Limited access to specific tools only

    pub fn fromString(str: []const u8) ?Role {
        if (std.mem.eql(u8, str, "admin")) return .admin;
        if (std.mem.eql(u8, str, "developer")) return .developer;
        if (std.mem.eql(u8, str, "read_only")) return .read_only;
        if (std.mem.eql(u8, str, "restricted")) return .restricted;
        return null;
    }

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .admin => "admin",
            .developer => "developer",
            .read_only => "read_only",
            .restricted => "restricted",
        };
    }
};

/// Authentication method types
pub const AuthMethod = enum {
    api_key,
    bearer_token,
    jwt,
    none, // Development mode only
};

/// API key information with permissions
pub const ApiKey = struct {
    key: []const u8,
    name: []const u8,
    role: Role,
    created_at: i64,
    last_used: ?i64,
    rate_limit_per_hour: u32,
    allowed_tools: ?[]const []const u8, // null = all tools allowed
    expires_at: ?i64, // null = no expiration

    pub fn init(allocator: Allocator, key: []const u8, name: []const u8, role: Role) !ApiKey {
        return ApiKey{
            .key = try allocator.dupe(u8, key),
            .name = try allocator.dupe(u8, name),
            .role = role,
            .created_at = std.time.timestamp(),
            .last_used = null,
            .rate_limit_per_hour = switch (role) {
                .admin => 10000,
                .developer => 1000,
                .read_only => 500,
                .restricted => 100,
            },
            .allowed_tools = null,
            .expires_at = null,
        };
    }

    pub fn deinit(self: *ApiKey, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.name);
        if (self.allowed_tools) |tools| {
            for (tools) |tool| {
                allocator.free(tool);
            }
            allocator.free(tools);
        }
    }

    pub fn isExpired(self: ApiKey) bool {
        if (self.expires_at) |expires| {
            return std.time.timestamp() >= expires;
        }
        return false;
    }

    pub fn canAccessTool(self: ApiKey, tool_name: []const u8) bool {
        // Admin has access to all tools
        if (self.role == .admin) return true;

        // If no specific tools restrictions, check role-based access
        if (self.allowed_tools == null) {
            return switch (self.role) {
                .admin => true,
                .developer => true, // Developers get access to all standard tools
                .read_only => std.mem.eql(u8, tool_name, "read_code") or
                    std.mem.eql(u8, tool_name, "get_context") or
                    std.mem.startsWith(u8, tool_name, "read_"),
                .restricted => false, // Must have explicit tool allowlist
            };
        }

        // Check explicit allowlist
        for (self.allowed_tools.?) |allowed| {
            if (std.mem.eql(u8, allowed, tool_name)) return true;
        }

        return false;
    }
};

/// JWT token claims structure
pub const JwtClaims = struct {
    sub: []const u8, // Subject (user ID)
    iss: []const u8, // Issuer
    aud: []const u8, // Audience
    exp: i64, // Expiration time
    iat: i64, // Issued at time
    role: Role, // User role
    tools: ?[]const []const u8, // Allowed tools (null = all)

    pub fn isExpired(self: JwtClaims) bool {
        return std.time.timestamp() >= self.exp;
    }
};

/// Rate limiting tracker
const RateLimitEntry = struct {
    count: u32,
    window_start: i64,
    last_reset: i64,
};

/// Authentication event for audit logging
pub const AuthEvent = struct {
    timestamp: i64,
    auth_method: AuthMethod,
    user_id: []const u8,
    source_ip: ?[]const u8,
    tool_name: ?[]const u8,
    success: bool,
    error_message: ?[]const u8,

    pub fn init(allocator: Allocator, auth_method: AuthMethod, user_id: []const u8, success: bool) !AuthEvent {
        return AuthEvent{
            .timestamp = std.time.timestamp(),
            .auth_method = auth_method,
            .user_id = try allocator.dupe(u8, user_id),
            .source_ip = null,
            .tool_name = null,
            .success = success,
            .error_message = null,
        };
    }

    pub fn deinit(self: *AuthEvent, allocator: Allocator) void {
        allocator.free(self.user_id);
        if (self.source_ip) |ip| allocator.free(ip);
        if (self.tool_name) |tool| allocator.free(tool);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

/// Configuration for authentication system
pub const AuthConfig = struct {
    enabled: bool = true,
    development_mode: bool = false,
    require_https: bool = true,
    jwt_secret: []const u8,
    jwt_issuer: []const u8 = "agrama-codegraph",
    jwt_audience: []const u8 = "mcp-tools",
    api_key_header: []const u8 = "X-API-Key",
    bearer_token_header: []const u8 = "Authorization",
    rate_limiting_enabled: bool = true,
    audit_logging_enabled: bool = true,
    max_failed_attempts: u32 = 5,
    lockout_duration_minutes: u32 = 15,
};

/// Main authentication and authorization system
pub const AuthSystem = struct {
    allocator: Allocator,
    config: AuthConfig,
    api_keys: HashMap([]const u8, ApiKey, StringContext, std.hash_map.default_max_load_percentage),
    rate_limits: HashMap([]const u8, RateLimitEntry, StringContext, std.hash_map.default_max_load_percentage),
    audit_log: ArrayList(AuthEvent),
    failed_attempts: HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage),
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

    /// Initialize authentication system
    pub fn init(allocator: Allocator, config: AuthConfig) AuthSystem {
        return AuthSystem{
            .allocator = allocator,
            .config = config,
            .api_keys = HashMap([]const u8, ApiKey, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .rate_limits = HashMap([]const u8, RateLimitEntry, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .audit_log = ArrayList(AuthEvent).init(allocator),
            .failed_attempts = HashMap([]const u8, u32, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .mutex = Mutex{},
        };
    }

    /// Clean up authentication system
    pub fn deinit(self: *AuthSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up API keys
        var api_key_iterator = self.api_keys.iterator();
        while (api_key_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.api_keys.deinit();

        // Clean up rate limits
        self.rate_limits.deinit();

        // Clean up audit log
        for (self.audit_log.items) |*event| {
            event.deinit(self.allocator);
        }
        self.audit_log.deinit();

        // Clean up failed attempts
        self.failed_attempts.deinit();
    }

    /// Add API key to the system
    pub fn addApiKey(self: *AuthSystem, key: []const u8, name: []const u8, role: Role) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var api_key = try ApiKey.init(self.allocator, key, name, role);
        try self.api_keys.put(api_key.key, api_key);

        std.log.info("Added API key: {} role={s} rate_limit={}/hour", .{ name, role.toString(), api_key.rate_limit_per_hour });
    }

    /// Remove API key from the system
    pub fn removeApiKey(self: *AuthSystem, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.api_keys.fetchRemove(key)) |kv| {
            var api_key = kv.value;
            api_key.deinit(self.allocator);
            std.log.info("Removed API key: {s}", .{api_key.name});
            return true;
        }
        return false;
    }

    /// Authenticate request and return user context
    pub fn authenticate(self: *AuthSystem, headers: std.StringHashMap([]const u8), source_ip: ?[]const u8) !AuthContext {
        if (!self.config.enabled or self.config.development_mode) {
            return AuthContext{
                .authenticated = true,
                .user_id = "dev-user",
                .role = .admin,
                .auth_method = .none,
                .allowed_tools = null,
            };
        }

        // Try API key authentication first
        if (headers.get(self.config.api_key_header)) |api_key| {
            return self.authenticateApiKey(api_key, source_ip);
        }

        // Try Bearer token authentication
        if (headers.get(self.config.bearer_token_header)) |auth_header| {
            if (std.mem.startsWith(u8, auth_header, "Bearer ")) {
                const token = auth_header[7..]; // Skip "Bearer " prefix
                return self.authenticateBearerToken(token, source_ip);
            }
        }

        // No valid authentication found
        try self.logAuthEvent(.none, "anonymous", source_ip, null, false, "Missing authentication");
        return AuthError.MissingAuthHeader;
    }

    /// Authenticate using API key
    fn authenticateApiKey(self: *AuthSystem, key: []const u8, source_ip: ?[]const u8) !AuthContext {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check failed attempts for this key/IP combination
        const identifier = key; // Could combine with IP for more granular tracking
        if (self.failed_attempts.get(identifier)) |attempts| {
            if (attempts >= self.config.max_failed_attempts) {
                try self.logAuthEvent(.api_key, identifier, source_ip, null, false, "Account locked due to too many failed attempts");
                return AuthError.RateLimitExceeded;
            }
        }

        if (self.api_keys.getPtr(key)) |api_key| {
            // Check if key is expired
            if (api_key.isExpired()) {
                try self.incrementFailedAttempts(identifier);
                try self.logAuthEvent(.api_key, api_key.name, source_ip, null, false, "API key expired");
                return AuthError.TokenExpired;
            }

            // Check rate limiting
            if (self.config.rate_limiting_enabled) {
                try self.checkRateLimit(api_key.key, api_key.rate_limit_per_hour);
            }

            // Update last used timestamp
            api_key.last_used = std.time.timestamp();

            // Reset failed attempts on successful auth
            _ = self.failed_attempts.remove(identifier);

            try self.logAuthEvent(.api_key, api_key.name, source_ip, null, true, null);

            return AuthContext{
                .authenticated = true,
                .user_id = api_key.name,
                .role = api_key.role,
                .auth_method = .api_key,
                .allowed_tools = api_key.allowed_tools,
            };
        }

        try self.incrementFailedAttempts(identifier);
        try self.logAuthEvent(.api_key, "unknown", source_ip, null, false, "Invalid API key");
        return AuthError.InvalidApiKey;
    }

    /// Authenticate using Bearer token (JWT)
    fn authenticateBearerToken(self: *AuthSystem, token: []const u8, source_ip: ?[]const u8) !AuthContext {
        // Parse JWT token (simplified implementation)
        const claims = try self.parseJwtToken(token);

        // Check if token is expired
        if (claims.isExpired()) {
            try self.logAuthEvent(.jwt, claims.sub, source_ip, null, false, "JWT token expired");
            return AuthError.TokenExpired;
        }

        // Verify issuer and audience
        if (!std.mem.eql(u8, claims.iss, self.config.jwt_issuer) or
            !std.mem.eql(u8, claims.aud, self.config.jwt_audience))
        {
            try self.logAuthEvent(.jwt, claims.sub, source_ip, null, false, "Invalid JWT issuer or audience");
            return AuthError.InvalidToken;
        }

        try self.logAuthEvent(.jwt, claims.sub, source_ip, null, true, null);

        return AuthContext{
            .authenticated = true,
            .user_id = claims.sub,
            .role = claims.role,
            .auth_method = .jwt,
            .allowed_tools = claims.tools,
        };
    }

    /// Check if user is authorized for specific tool access
    pub fn authorize(self: *AuthSystem, context: AuthContext, tool_name: []const u8) !void {
        if (!context.authenticated) {
            return AuthError.InvalidCredentials;
        }

        // Admin role has access to everything
        if (context.role == .admin) {
            return;
        }

        // Check tool-specific permissions
        const has_access = if (context.allowed_tools) |tools| blk: {
            for (tools) |allowed_tool| {
                if (std.mem.eql(u8, allowed_tool, tool_name)) break :blk true;
            }
            break :blk false;
        } else switch (context.role) {
            .admin => true,
            .developer => true,
            .read_only => std.mem.eql(u8, tool_name, "read_code") or
                std.mem.eql(u8, tool_name, "get_context") or
                std.mem.startsWith(u8, tool_name, "read_"),
            .restricted => false,
        };

        if (!has_access) {
            try self.logAuthEvent(context.auth_method, context.user_id, null, tool_name, false, "Insufficient permissions");
            return AuthError.InsufficientPermissions;
        }

        try self.logAuthEvent(context.auth_method, context.user_id, null, tool_name, true, null);
    }

    /// Parse JWT token and extract claims (simplified implementation)
    fn parseJwtToken(self: *AuthSystem, token: []const u8) !JwtClaims {
        // This is a simplified JWT parser for demonstration
        // In production, use a proper JWT library with signature verification

        var it = std.mem.split(u8, token, ".");
        _ = it.first(); // Skip header

        const payload_b64 = it.next() orelse return AuthError.InvalidToken;

        // Decode base64 payload
        var payload_buf: [1024]u8 = undefined;
        const payload = base64.standard.Decoder.decode(payload_buf[0..], payload_b64) catch {
            return AuthError.InvalidToken;
        };

        // Parse JSON payload
        var parsed = json.parseFromSlice(json.Value, self.allocator, payload, .{}) catch {
            return AuthError.InvalidToken;
        };
        defer parsed.deinit();

        const claims_obj = parsed.value.object;

        const sub = claims_obj.get("sub").?.string;
        const iss = claims_obj.get("iss").?.string;
        const aud = claims_obj.get("aud").?.string;
        const exp = @as(i64, @intCast(claims_obj.get("exp").?.integer));
        const iat = @as(i64, @intCast(claims_obj.get("iat").?.integer));

        const role_str = claims_obj.get("role").?.string;
        const role = Role.fromString(role_str) orelse return AuthError.InvalidToken;

        return JwtClaims{
            .sub = sub,
            .iss = iss,
            .aud = aud,
            .exp = exp,
            .iat = iat,
            .role = role,
            .tools = null, // TODO: Parse tools array from claims
        };
    }

    /// Check rate limiting for user
    fn checkRateLimit(self: *AuthSystem, identifier: []const u8, limit_per_hour: u32) !void {
        const current_time = std.time.timestamp();
        const hour_start = current_time - (current_time % 3600);

        if (self.rate_limits.getPtr(identifier)) |entry| {
            // Reset counter if new hour
            if (entry.window_start != hour_start) {
                entry.count = 0;
                entry.window_start = hour_start;
                entry.last_reset = current_time;
            }

            if (entry.count >= limit_per_hour) {
                return AuthError.RateLimitExceeded;
            }

            entry.count += 1;
        } else {
            try self.rate_limits.put(identifier, RateLimitEntry{
                .count = 1,
                .window_start = hour_start,
                .last_reset = current_time,
            });
        }
    }

    /// Increment failed authentication attempts
    fn incrementFailedAttempts(self: *AuthSystem, identifier: []const u8) !void {
        const gop = try self.failed_attempts.getOrPut(identifier);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
    }

    /// Log authentication event for audit trail
    fn logAuthEvent(self: *AuthSystem, auth_method: AuthMethod, user_id: []const u8, source_ip: ?[]const u8, tool_name: ?[]const u8, success: bool, error_message: ?[]const u8) !void {
        if (!self.config.audit_logging_enabled) return;

        var event = try AuthEvent.init(self.allocator, auth_method, user_id, success);

        if (source_ip) |ip| {
            event.source_ip = try self.allocator.dupe(u8, ip);
        }

        if (tool_name) |tool| {
            event.tool_name = try self.allocator.dupe(u8, tool);
        }

        if (error_message) |msg| {
            event.error_message = try self.allocator.dupe(u8, msg);
        }

        try self.audit_log.append(event);

        // Log to system logger
        if (success) {
            std.log.info("AUTH_SUCCESS: method={s} user={s} tool={s} ip={s}", .{ @tagName(auth_method), user_id, tool_name orelse "none", source_ip orelse "unknown" });
        } else {
            std.log.warn("AUTH_FAILURE: method={s} user={s} error={s} ip={s}", .{ @tagName(auth_method), user_id, error_message orelse "unknown", source_ip orelse "unknown" });
        }
    }

    /// Get authentication statistics
    pub fn getStats(self: *AuthSystem) AuthStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var successful_auths: u32 = 0;
        var failed_auths: u32 = 0;

        for (self.audit_log.items) |event| {
            if (event.success) {
                successful_auths += 1;
            } else {
                failed_auths += 1;
            }
        }

        return AuthStats{
            .total_api_keys = @as(u32, @intCast(self.api_keys.count())),
            .successful_authentications = successful_auths,
            .failed_authentications = failed_auths,
            .active_rate_limits = @as(u32, @intCast(self.rate_limits.count())),
            .locked_accounts = @as(u32, @intCast(self.failed_attempts.count())),
            .audit_events = @as(u32, @intCast(self.audit_log.items.len)),
        };
    }

    /// Get recent audit events
    pub fn getAuditLog(self: *AuthSystem, allocator: Allocator, limit: u32) ![]AuthEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        const actual_limit = @min(limit, self.audit_log.items.len);
        var events = try allocator.alloc(AuthEvent, actual_limit);

        // Return most recent events
        const start_idx = self.audit_log.items.len - actual_limit;
        for (self.audit_log.items[start_idx..], 0..) |event, i| {
            events[i] = event; // Shallow copy - caller must not free inner fields
        }

        return events;
    }

    /// Clean up expired entries and old audit logs
    pub fn performMaintenance(self: *AuthSystem) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const current_time = std.time.timestamp();
        const cleanup_threshold = current_time - (24 * 3600); // 24 hours ago

        // Clean up old rate limit entries
        var rate_limit_keys = std.ArrayList([]const u8).init(self.allocator);
        defer rate_limit_keys.deinit();

        var rate_limit_iterator = self.rate_limits.iterator();
        while (rate_limit_iterator.next()) |entry| {
            if (entry.value_ptr.last_reset < cleanup_threshold) {
                rate_limit_keys.append(entry.key_ptr.*) catch continue;
            }
        }

        for (rate_limit_keys.items) |key| {
            _ = self.rate_limits.remove(key);
        }

        // Clean up old audit log entries (keep last 1000)
        if (self.audit_log.items.len > 1000) {
            const items_to_remove = self.audit_log.items.len - 1000;
            for (self.audit_log.items[0..items_to_remove]) |*event| {
                event.deinit(self.allocator);
            }

            // Move remaining items to front
            std.mem.copy(AuthEvent, self.audit_log.items[0..1000], self.audit_log.items[items_to_remove..]);
            self.audit_log.shrinkAndFree(1000);
        }

        std.log.debug("Auth maintenance: cleaned {} rate limit entries, audit log size: {}", .{ rate_limit_keys.items.len, self.audit_log.items.len });
    }
};

/// Authentication context returned after successful authentication
pub const AuthContext = struct {
    authenticated: bool,
    user_id: []const u8,
    role: Role,
    auth_method: AuthMethod,
    allowed_tools: ?[]const []const u8,
};

/// Authentication system statistics
pub const AuthStats = struct {
    total_api_keys: u32,
    successful_authentications: u32,
    failed_authentications: u32,
    active_rate_limits: u32,
    locked_accounts: u32,
    audit_events: u32,
};

/// Utility functions for environment-based configuration
pub fn loadConfigFromEnv(allocator: Allocator) !AuthConfig {
    const enabled = if (std.posix.getenv("AGRAMA_AUTH_ENABLED")) |val|
        std.mem.eql(u8, val, "true")
    else
        true;

    const dev_mode = if (std.posix.getenv("AGRAMA_DEV_MODE")) |val|
        std.mem.eql(u8, val, "true")
    else
        false;

    const jwt_secret = std.posix.getenv("AGRAMA_JWT_SECRET") orelse
        "default-secret-change-in-production";

    return AuthConfig{
        .enabled = enabled,
        .development_mode = dev_mode,
        .require_https = true,
        .jwt_secret = try allocator.dupe(u8, jwt_secret),
        .rate_limiting_enabled = true,
        .audit_logging_enabled = true,
    };
}

/// Load API keys from environment variables
pub fn loadApiKeysFromEnv(auth_system: *AuthSystem) !void {
    // Support multiple API keys via environment variables
    // AGRAMA_API_KEYS=key1:name1:role1,key2:name2:role2
    if (std.posix.getenv("AGRAMA_API_KEYS")) |keys_env| {
        var it = std.mem.split(u8, keys_env, ",");
        while (it.next()) |key_def| {
            var parts = std.mem.split(u8, key_def, ":");
            const key = parts.next() orelse continue;
            const name = parts.next() orelse continue;
            const role_str = parts.next() orelse continue;

            if (Role.fromString(role_str)) |role| {
                try auth_system.addApiKey(key, name, role);
            }
        }
    }

    // Support single API key for quick setup
    // AGRAMA_API_KEY=your-key-here
    // AGRAMA_API_KEY_NAME=MyApp
    // AGRAMA_API_KEY_ROLE=developer
    if (std.posix.getenv("AGRAMA_API_KEY")) |key| {
        const name = std.posix.getenv("AGRAMA_API_KEY_NAME") orelse "default";
        const role_str = std.posix.getenv("AGRAMA_API_KEY_ROLE") orelse "developer";

        if (Role.fromString(role_str)) |role| {
            try auth_system.addApiKey(key, name, role);
        }
    }
}

// Unit Tests
test "AuthSystem initialization and API key management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var auth_system = AuthSystem.init(allocator, config);
    defer auth_system.deinit();

    // Test API key addition
    try auth_system.addApiKey("test-key-123", "Test App", .developer);

    var stats = auth_system.getStats();
    try testing.expect(stats.total_api_keys == 1);

    // Test API key removal
    const removed = auth_system.removeApiKey("test-key-123");
    try testing.expect(removed == true);

    stats = auth_system.getStats();
    try testing.expect(stats.total_api_keys == 0);
}

test "API key authentication and authorization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuthConfig{
        .enabled = true,
        .development_mode = false,
        .jwt_secret = "test-secret",
        .rate_limiting_enabled = false,
        .audit_logging_enabled = false,
    };

    var auth_system = AuthSystem.init(allocator, config);
    defer auth_system.deinit();

    try auth_system.addApiKey("dev-key-456", "Developer App", .developer);
    try auth_system.addApiKey("read-key-789", "Read Only App", .read_only);

    // Create headers for authentication
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    // Test developer API key authentication
    try headers.put("X-API-Key", "dev-key-456");

    const dev_context = try auth_system.authenticate(headers, null);
    try testing.expect(dev_context.authenticated == true);
    try testing.expectEqualSlices(u8, "Developer App", dev_context.user_id);
    try testing.expect(dev_context.role == .developer);

    // Test developer can access write operations
    try auth_system.authorize(dev_context, "write_code");

    // Test read-only API key
    _ = headers.remove("X-API-Key");
    try headers.put("X-API-Key", "read-key-789");

    const readonly_context = try auth_system.authenticate(headers, null);
    try testing.expect(readonly_context.authenticated == true);
    try testing.expect(readonly_context.role == .read_only);

    // Test read-only can access read operations
    try auth_system.authorize(readonly_context, "read_code");

    // Test read-only cannot access write operations
    try testing.expectError(AuthError.InsufficientPermissions, auth_system.authorize(readonly_context, "write_code"));
}

test "Role-based tool access control" {
    const admin_role = Role.admin;
    const dev_role = Role.developer;
    const readonly_role = Role.read_only;
    const restricted_role = Role.restricted;

    // Test role to string conversion
    try testing.expectEqualSlices(u8, "admin", admin_role.toString());
    try testing.expectEqualSlices(u8, "developer", dev_role.toString());
    try testing.expectEqualSlices(u8, "read_only", readonly_role.toString());
    try testing.expectEqualSlices(u8, "restricted", restricted_role.toString());

    // Test role from string conversion
    try testing.expect(Role.fromString("admin") == .admin);
    try testing.expect(Role.fromString("developer") == .developer);
    try testing.expect(Role.fromString("invalid") == null);
}

test "Development mode bypass" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = AuthConfig{
        .enabled = true,
        .development_mode = true, // Development mode enabled
        .jwt_secret = "test-secret",
    };

    var auth_system = AuthSystem.init(allocator, config);
    defer auth_system.deinit();

    // Empty headers should still authenticate in dev mode
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    const context = try auth_system.authenticate(headers, null);
    try testing.expect(context.authenticated == true);
    try testing.expect(context.role == .admin);
    try testing.expect(context.auth_method == .none);
}
