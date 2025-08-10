const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello, Agrama MCP Server!\n", .{});
    
    // Test function
    const result = addNumbers(5, 10);
    std.debug.print("5 + 10 = {d}\n", .{result});
}

fn addNumbers(a: i32, b: i32) i32 {
    return a + b;
}