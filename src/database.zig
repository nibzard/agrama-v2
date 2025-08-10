const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// Represents a single change in file history
pub const Change = struct {
    timestamp: i64,
    path: []const u8,
    content: []const u8,

    pub fn init(allocator: Allocator, path: []const u8, content: []const u8) !Change {
        const owned_path = try allocator.dupe(u8, path);
        const owned_content = try allocator.dupe(u8, content);

        return Change{
            .timestamp = std.time.timestamp(),
            .path = owned_path,
            .content = owned_content,
        };
    }

    pub fn deinit(self: *Change, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
    }
};

/// Core Agrama temporal database - Phase 1 implementation
/// Provides basic file storage with temporal tracking capabilities
pub const Database = struct {
    allocator: Allocator,
    // Current file contents stored as path -> content mapping
    current_files: HashMap([]const u8, []const u8, HashContext, std.hash_map.default_max_load_percentage),
    // History of all changes stored as path -> list of changes
    file_histories: HashMap([]const u8, ArrayList(Change), HashContext, std.hash_map.default_max_load_percentage),

    // Optional FRE integration for advanced graph operations
    fre: ?@import("fre_true.zig").TrueFrontierReductionEngine,

    const HashContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    /// Initialize a new Database instance
    pub fn init(allocator: Allocator) Database {
        return Database{
            .allocator = allocator,
            .current_files = HashMap([]const u8, []const u8, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .file_histories = HashMap([]const u8, ArrayList(Change), HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .fre = null,
        };
    }

    /// Initialize database with FRE integration
    pub fn initWithFRE(allocator: Allocator) !Database {
        const fre = @import("fre_true.zig").TrueFrontierReductionEngine.init(allocator);
        return Database{
            .allocator = allocator,
            .current_files = HashMap([]const u8, []const u8, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .file_histories = HashMap([]const u8, ArrayList(Change), HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .fre = fre,
        };
    }

    /// Clean up database resources
    pub fn deinit(self: *Database) void {
        // Clean up FRE if present
        if (self.fre) |*fre| {
            fre.deinit();
        }

        // Clean up current files
        var current_iterator = self.current_files.iterator();
        while (current_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.current_files.deinit();

        // Clean up file histories
        var history_iterator = self.file_histories.iterator();
        while (history_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var changes = entry.value_ptr;
            for (changes.items) |*change| {
                change.deinit(self.allocator);
            }
            changes.deinit();
        }
        self.file_histories.deinit();
    }

    /// Validate a file path for security
    /// Prevents path traversal attacks and restricts access to allowed directories
    fn validatePath(path: []const u8) !void {
        // Basic validation - empty path
        if (path.len == 0) {
            return error.InvalidPath;
        }

        // Block absolute paths (Unix and Windows)
        if (path[0] == '/' or (path.len >= 2 and path[1] == ':')) {
            return error.AbsolutePathNotAllowed;
        }

        // Check for directory traversal sequences
        var i: usize = 0;
        while (i < path.len) {
            // Check for "../" sequences (including encoded variants)
            if (i + 2 < path.len and path[i] == '.' and path[i + 1] == '.' and
                (path[i + 2] == '/' or path[i + 2] == '\\'))
            {
                return error.PathTraversalAttempt;
            }

            // Check for "/.." at end or followed by separator
            if (i > 0 and path[i - 1] == '/' and i + 1 < path.len and
                path[i] == '.' and path[i + 1] == '.' and
                (i + 2 >= path.len or path[i + 2] == '/' or path[i + 2] == '\\'))
            {
                return error.PathTraversalAttempt;
            }

            // Check for backslash (Windows path separator - could be used for traversal)
            if (path[i] == '\\') {
                return error.InvalidPathSeparator;
            }

            // Check for URL-encoded traversal sequences
            if (i + 5 < path.len and path[i] == '%' and path[i + 1] == '2' and
                (path[i + 2] == 'e' or path[i + 2] == 'E') and
                path[i + 3] == '%' and path[i + 4] == '2' and
                (path[i + 5] == 'e' or path[i + 5] == 'E'))
            {
                return error.EncodedTraversalAttempt;
            }

            // Check for null bytes (could be used to bypass validation)
            if (path[i] == 0) {
                return error.NullByteInPath;
            }

            i += 1;
        }

        // Additional security: only allow paths within specific prefixes
        const allowed_prefixes = [_][]const u8{
            "src/",
            "tests/",
            "docs/",
            "data/",
            "temp/",
            "user_files/",
        };

        var is_allowed = false;
        for (allowed_prefixes) |prefix| {
            if (std.mem.startsWith(u8, path, prefix)) {
                is_allowed = true;
                break;
            }
        }

        // Also allow simple filenames without directories (for backward compatibility)
        if (!is_allowed and std.mem.indexOf(u8, path, "/") == null) {
            is_allowed = true;
        }

        if (!is_allowed) {
            return error.PathNotInAllowedDirectory;
        }
    }

    /// Save a file with the given path and content
    /// Creates a new entry in history and updates current content
    pub fn saveFile(self: *Database, path: []const u8, content: []const u8) !void {
        // Validate inputs
        if (content.len == 0) {
            return error.InvalidInput;
        }

        // Comprehensive path validation to prevent security vulnerabilities
        try validatePath(path);

        // Create owned copies of path and content for current files
        const owned_path_current = self.allocator.dupe(u8, path) catch |err| {
            std.log.err("Failed to duplicate path for current files: {}", .{err});
            return err;
        };
        errdefer self.allocator.free(owned_path_current);

        const owned_content = self.allocator.dupe(u8, content) catch |err| {
            std.log.err("Failed to duplicate content for current files: {}", .{err});
            return err;
        };
        errdefer self.allocator.free(owned_content);

        // Update current files map - free old key and content if they exist
        if (self.current_files.fetchRemove(path)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        // Store the new content
        self.current_files.put(owned_path_current, owned_content) catch |err| {
            std.log.err("Failed to store file in current files map: {}", .{err});
            return err;
        };

        // Create change record for history
        var change = Change.init(self.allocator, path, content) catch |err| {
            std.log.err("Failed to create change record: {}", .{err});
            return err;
        };
        errdefer change.deinit(self.allocator);

        // Add to file history - use the path that's already owned by the current_files map
        const history_gop = self.file_histories.getOrPut(path) catch |err| {
            std.log.err("Failed to get or put in file histories: {}", .{err});
            return err;
        };

        if (!history_gop.found_existing) {
            // Create owned path for history key
            const owned_path_history = self.allocator.dupe(u8, path) catch |err| {
                std.log.err("Failed to duplicate path for history: {}", .{err});
                return err;
            };
            history_gop.key_ptr.* = owned_path_history;
            history_gop.value_ptr.* = ArrayList(Change).init(self.allocator);
        }

        history_gop.value_ptr.append(change) catch |err| {
            std.log.err("Failed to append change to history: {}", .{err});
            return err;
        };
    }

    /// Retrieve the current content of a file
    /// Returns error if file doesn't exist
    pub fn getFile(self: *Database, path: []const u8) ![]const u8 {
        // Validate path for security
        try validatePath(path);

        if (self.current_files.get(path)) |content| {
            return content;
        }
        return error.FileNotFound;
    }

    /// Get the history of changes for a file, limited to the specified number of entries
    /// Returns the most recent changes first (reverse chronological order)
    pub fn getHistory(self: *Database, path: []const u8, limit: usize) ![]Change {
        // Validate path for security
        try validatePath(path);

        if (self.file_histories.get(path)) |history| {
            const changes = history.items;
            const actual_limit = @min(limit, changes.len);

            // Allocate result array
            const result = try self.allocator.alloc(Change, actual_limit);

            // Copy the most recent changes (from the end of the list)
            for (0..actual_limit) |i| {
                const source_index = changes.len - 1 - i; // Reverse order (most recent first)
                result[i] = changes[source_index];
            }

            return result;
        }
        return error.FileNotFound;
    }

    /// Get FRE instance if available
    pub fn getFRE(self: *Database) ?*@import("fre_true.zig").TrueFrontierReductionEngine {
        if (self.fre) |*fre| {
            return fre;
        }
        return null;
    }

    /// Enable FRE functionality
    pub fn enableFRE(self: *Database) !void {
        if (self.fre == null) {
            self.fre = @import("fre_true.zig").TrueFrontierReductionEngine.init(self.allocator);
        }
    }
};

// Unit Tests
test "Database initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in database initialization test", .{});
        }
    }
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Database should initialize without errors
    try testing.expect(db.current_files.count() == 0);
    try testing.expect(db.file_histories.count() == 0);
}

test "saveFile and getFile basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in saveFile/getFile test", .{});
        }
    }
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "tests/file.txt"; // Use allowed prefix
    const test_content = "Hello, World!";

    // Save a file
    try db.saveFile(test_path, test_content);

    // Retrieve the file
    const retrieved_content = try db.getFile(test_path);
    try testing.expectEqualSlices(u8, test_content, retrieved_content);
}

test "getFile returns error for non-existent file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Try to get a file that doesn't exist (but uses valid path format)
    const result = db.getFile("tests/nonexistent.txt");
    try testing.expectError(error.FileNotFound, result);
}

test "file history tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "tests/history.txt";

    // Save multiple versions
    try db.saveFile(test_path, "Version 1");
    // Small delay to ensure different timestamps
    std.time.sleep(1000000); // 1ms
    try db.saveFile(test_path, "Version 2");
    std.time.sleep(1000000); // 1ms
    try db.saveFile(test_path, "Version 3");

    // Get history (limit to 2)
    const history = try db.getHistory(test_path, 2);
    defer allocator.free(history);

    try testing.expect(history.len == 2);

    // Should be in reverse chronological order (most recent first)
    try testing.expectEqualSlices(u8, "Version 3", history[0].content);
    try testing.expectEqualSlices(u8, "Version 2", history[1].content);

    // Verify timestamps are in descending order (most recent first)
    try testing.expect(history[0].timestamp >= history[1].timestamp);
}

test "getHistory returns error for non-existent file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Try to get history for a file that doesn't exist (but uses valid path format)
    const result = db.getHistory("tests/nonexistent.txt", 10);
    try testing.expectError(error.FileNotFound, result);
}

test "file content updates correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "tests/update.txt";

    // Save initial content
    try db.saveFile(test_path, "Initial content");
    var content = try db.getFile(test_path);
    try testing.expectEqualSlices(u8, "Initial content", content);

    // Update content
    try db.saveFile(test_path, "Updated content");
    content = try db.getFile(test_path);
    try testing.expectEqualSlices(u8, "Updated content", content);

    // Verify history contains both versions
    const history = try db.getHistory(test_path, 10);
    defer allocator.free(history);

    try testing.expect(history.len == 2);
    try testing.expectEqualSlices(u8, "Updated content", history[0].content);
    try testing.expectEqualSlices(u8, "Initial content", history[1].content);
}

test "Database FRE integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Initially no FRE
    try testing.expect(db.getFRE() == null);

    // Enable FRE
    try db.enableFRE();
    try testing.expect(db.getFRE() != null);

    // Test FRE functionality
    if (db.getFRE()) |fre| {
        const stats = fre.getGraphStats();
        try testing.expect(stats.nodes == 0);
        try testing.expect(stats.edges == 0);
    }
}

// Security Tests - Path Traversal Protection

test "path validation - directory traversal attacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const traversal_attacks = [_][]const u8{
        "../../../etc/passwd",
        "src/../../../etc/passwd",
        "../config.json",
        "docs/../../secret.txt",
        "..\\..\\windows\\system32",
        "src/..\\..\\config",
        "/etc/passwd",
        "/var/log/auth.log",
        "C:\\Windows\\System32",
        "\\\\server\\share",
    };

    for (traversal_attacks) |attack_path| {
        const result = db.saveFile(attack_path, "malicious content");
        try testing.expect(std.meta.isError(result));
    }
}

test "path validation - encoded traversal attacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const encoded_attacks = [_][]const u8{
        "src/%2e%2e/config.json",
        "%2e%2e%2fpasswd",
        "docs%2f%2e%2e%2fconfig",
    };

    for (encoded_attacks) |attack_path| {
        const result = db.saveFile(attack_path, "encoded attack");
        try testing.expect(std.meta.isError(result));
    }
}

test "path validation - null byte attacks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const null_byte_path = "src/file.txt\x00../../../etc/passwd";
    const result = db.saveFile(null_byte_path, "null byte attack");
    try testing.expectError(error.NullByteInPath, result);
}

test "path validation - legitimate paths allowed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const legitimate_paths = [_][]const u8{
        "src/main.zig",
        "tests/unit_test.zig",
        "docs/README.md",
        "data/config.json",
        "temp/cache.tmp",
        "user_files/document.txt",
        "simple_file.txt", // Simple filename without directory
    };

    for (legitimate_paths) |path| {
        try db.saveFile(path, "legitimate content");
        const content = try db.getFile(path);
        try testing.expectEqualSlices(u8, "legitimate content", content);
    }
}

test "path validation - empty and invalid paths" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Empty path should be rejected
    try testing.expectError(error.InvalidPath, db.saveFile("", "content"));

    // Paths outside allowed directories should be rejected
    const disallowed_paths = [_][]const u8{
        "forbidden/file.txt",
        "system/config.conf",
        "root/secret.key",
    };

    for (disallowed_paths) |path| {
        try testing.expectError(error.PathNotInAllowedDirectory, db.saveFile(path, "content"));
    }
}

test "path validation consistency across methods" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const malicious_path = "../../../etc/passwd";

    // All methods should reject malicious paths consistently
    try testing.expectError(error.PathTraversalAttempt, db.saveFile(malicious_path, "content"));
    try testing.expectError(error.PathTraversalAttempt, db.getFile(malicious_path));
    try testing.expectError(error.PathTraversalAttempt, db.getHistory(malicious_path, 10));
}
