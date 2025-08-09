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
    fre: ?@import("fre.zig").FrontierReductionEngine,

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
        const fre = @import("fre.zig").FrontierReductionEngine.init(allocator);
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

    /// Save a file with the given path and content
    /// Creates a new entry in history and updates current content
    pub fn saveFile(self: *Database, path: []const u8, content: []const u8) !void {
        // Create owned copies of path and content for current files
        const owned_path_current = try self.allocator.dupe(u8, path);
        const owned_content = try self.allocator.dupe(u8, content);

        // Update current files map - free old key and content if they exist
        if (self.current_files.fetchRemove(path)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }

        // Store the new content
        try self.current_files.put(owned_path_current, owned_content);

        // Create change record for history
        const change = try Change.init(self.allocator, path, content);

        // Add to file history
        const history_gop = try self.file_histories.getOrPut(path);
        if (!history_gop.found_existing) {
            // Create owned path for history key
            const owned_path_history = try self.allocator.dupe(u8, path);
            history_gop.key_ptr.* = owned_path_history;
            history_gop.value_ptr.* = ArrayList(Change).init(self.allocator);
        }
        try history_gop.value_ptr.append(change);
    }

    /// Retrieve the current content of a file
    /// Returns error if file doesn't exist
    pub fn getFile(self: *Database, path: []const u8) ![]const u8 {
        if (self.current_files.get(path)) |content| {
            return content;
        }
        return error.FileNotFound;
    }

    /// Get the history of changes for a file, limited to the specified number of entries
    /// Returns the most recent changes first (reverse chronological order)
    pub fn getHistory(self: *Database, path: []const u8, limit: usize) ![]Change {
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
    pub fn getFRE(self: *Database) ?*@import("fre.zig").FrontierReductionEngine {
        if (self.fre) |*fre| {
            return fre;
        }
        return null;
    }

    /// Enable FRE functionality
    pub fn enableFRE(self: *Database) !void {
        if (self.fre == null) {
            self.fre = @import("fre.zig").FrontierReductionEngine.init(self.allocator);
        }
    }
};

// Unit Tests
test "Database initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    // Database should initialize without errors
    try testing.expect(db.current_files.count() == 0);
    try testing.expect(db.file_histories.count() == 0);
}

test "saveFile and getFile basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "test/file.txt";
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

    // Try to get a file that doesn't exist
    const result = db.getFile("non/existent/file.txt");
    try testing.expectError(error.FileNotFound, result);
}

test "file history tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "test/history.txt";

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

    // Try to get history for a file that doesn't exist
    const result = db.getHistory("non/existent/file.txt", 10);
    try testing.expectError(error.FileNotFound, result);
}

test "file content updates correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = Database.init(allocator);
    defer db.deinit();

    const test_path = "test/update.txt";

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
