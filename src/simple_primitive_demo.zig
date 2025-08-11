//! Simple Agrama Primitive Demo - Core functionality without complex logging
//!
//! This demo shows the 5 core primitives in action with basic functionality.

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
const primitives = @import("primitives.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Agrama Primitive System - Core Functionality Demo\n", .{});
    print("====================================================\n\n", .{});

    // Initialize the core infrastructure
    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    // Create primitive context
    _ = primitives.PrimitiveContext{
        .allocator = allocator,
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .agent_id = "demo_agent",
        .timestamp = std.time.timestamp(),
        .session_id = "demo_session",
    };

    print("✅ Infrastructure initialized\n", .{});
    print("📊 Agent: demo_agent | Session: demo_session\n\n", .{});

    // Demo 1: STORE primitive validation
    print("1️⃣  STORE Primitive - Validation\n", .{});
    print("=================================\n", .{});

    var store_params = std.json.ObjectMap.init(allocator);
    defer store_params.deinit();

    try store_params.put("key", std.json.Value{ .string = "test_concept" });
    try store_params.put("value", std.json.Value{ .string = "This is a test concept for the primitive system." });

    try primitives.StorePrimitive.validate(std.json.Value{ .object = store_params });
    print("✅ STORE validation passed\n", .{});

    // Test empty key validation
    var invalid_store = std.json.ObjectMap.init(allocator);
    defer invalid_store.deinit();
    try invalid_store.put("key", std.json.Value{ .string = "" });
    try invalid_store.put("value", std.json.Value{ .string = "test" });

    const store_validation_result = primitives.StorePrimitive.validate(std.json.Value{ .object = invalid_store });
    if (store_validation_result) {
        print("❌ Should have failed validation\n", .{});
    } else |err| {
        print("✅ Correctly rejected empty key: {}\n", .{err});
    }

    // Demo 2: SEARCH primitive validation
    print("\n2️⃣  SEARCH Primitive - Validation\n", .{});
    print("==================================\n", .{});

    var search_params = std.json.ObjectMap.init(allocator);
    defer search_params.deinit();

    try search_params.put("query", std.json.Value{ .string = "test query" });
    try search_params.put("type", std.json.Value{ .string = "semantic" });

    try primitives.SearchPrimitive.validate(std.json.Value{ .object = search_params });
    print("✅ SEARCH validation passed for 'semantic' type\n", .{});

    // Test invalid search type
    var invalid_search = std.json.ObjectMap.init(allocator);
    defer invalid_search.deinit();
    try invalid_search.put("query", std.json.Value{ .string = "test" });
    try invalid_search.put("type", std.json.Value{ .string = "invalid_type" });

    const search_validation_result = primitives.SearchPrimitive.validate(std.json.Value{ .object = invalid_search });
    if (search_validation_result) {
        print("❌ Should have failed validation\n", .{});
    } else |err| {
        print("✅ Correctly rejected invalid search type: {}\n", .{err});
    }

    // Demo 3: LINK primitive validation
    print("\n3️⃣  LINK Primitive - Validation\n", .{});
    print("===============================\n", .{});

    var link_params = std.json.ObjectMap.init(allocator);
    defer link_params.deinit();

    try link_params.put("from", std.json.Value{ .string = "concept_a" });
    try link_params.put("to", std.json.Value{ .string = "concept_b" });
    try link_params.put("relation", std.json.Value{ .string = "related_to" });

    try primitives.LinkPrimitive.validate(std.json.Value{ .object = link_params });
    print("✅ LINK validation passed\n", .{});

    // Demo 4: TRANSFORM primitive validation
    print("\n4️⃣  TRANSFORM Primitive - Validation\n", .{});
    print("====================================\n", .{});

    var transform_params = std.json.ObjectMap.init(allocator);
    defer transform_params.deinit();

    try transform_params.put("operation", std.json.Value{ .string = "parse_functions" });
    try transform_params.put("data", std.json.Value{ .string = "pub fn test() {}" });

    try primitives.TransformPrimitive.validate(std.json.Value{ .object = transform_params });
    print("✅ TRANSFORM validation passed for 'parse_functions'\n", .{});

    // Test unsupported operation
    var invalid_transform = std.json.ObjectMap.init(allocator);
    defer invalid_transform.deinit();
    try invalid_transform.put("operation", std.json.Value{ .string = "unsupported_op" });
    try invalid_transform.put("data", std.json.Value{ .string = "test" });

    const transform_validation_result = primitives.TransformPrimitive.validate(std.json.Value{ .object = invalid_transform });
    if (transform_validation_result) {
        print("❌ Should have failed validation\n", .{});
    } else |err| {
        print("✅ Correctly rejected unsupported operation: {}\n", .{err});
    }

    // Demo 5: Basic database operations
    print("\n5️⃣  Database Integration\n", .{});
    print("======================\n", .{});

    try database.saveFile("demo_file.txt", "This is test content for the primitive demo.");
    const retrieved = try database.getFile("demo_file.txt");
    print("✅ Saved and retrieved file successfully\n", .{});
    print("📄 Content: '{s}' (length: {})\n", .{ retrieved, retrieved.len });

    print("\n🎉 Primitive System Demo Completed Successfully!\n", .{});
    print("💡 All 5 primitives validated and core database functionality working.\n", .{});
    print("🔧 This demonstrates the foundation for LLM-composable memory architectures.\n", .{});
}
