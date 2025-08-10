//! MCP Utility Functions for Memory Management
//! Provides utilities for proper memory management in MCP tool responses

const std = @import("std");

/// Recursively deallocates a JSON Value and all its nested content
pub fn deinitJsonValue(allocator: std.mem.Allocator, value: std.json.Value) void {
    switch (value) {
        .string => |str| allocator.free(str),
        .array => |arr| {
            for (arr.items) |item| {
                deinitJsonValue(allocator, item);
            }
            arr.deinit();
        },
        .object => |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                deinitJsonValue(allocator, entry.value_ptr.*);
            }
            obj.deinit();
        },
        else => {
            // Other types (bool, integer, float, null) don't need deallocation
        },
    }
}

/// Create a string copy in JSON value format
pub fn createJsonString(allocator: std.mem.Allocator, str: []const u8) !std.json.Value {
    return std.json.Value{ .string = try allocator.dupe(u8, str) };
}

/// Create a JSON object with automatic memory management
pub fn createJsonObject(allocator: std.mem.Allocator) std.json.ObjectMap {
    return std.json.ObjectMap.init(allocator);
}

/// Create a JSON array with automatic memory management
pub fn createJsonArray(allocator: std.mem.Allocator) std.json.Array {
    return std.json.Array.init(allocator);
}

/// Response wrapper that tracks allocated memory for proper cleanup
pub const MCPResponse = struct {
    allocator: std.mem.Allocator,
    value: std.json.Value,

    pub fn init(allocator: std.mem.Allocator, value: std.json.Value) MCPResponse {
        return .{
            .allocator = allocator,
            .value = value,
        };
    }

    pub fn deinit(self: MCPResponse) void {
        deinitJsonValue(self.allocator, self.value);
    }
};
