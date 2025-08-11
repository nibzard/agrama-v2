//! Agrama Primitive System Demo - Showcasing the 5 Core Primitives
//!
//! This demo shows how LLMs can compose their own memory patterns using the
//! primitive-based architecture for AI Memory Substrate.

const std = @import("std");
const print = std.debug.print;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
const PrimitiveEngine = @import("primitive_engine.zig").PrimitiveEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Agrama Primitive System Demo\n", .{});
    print("================================\n\n", .{});

    // Initialize the core infrastructure
    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    // Initialize the primitive engine
    var engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer engine.deinit();

    // Start an AI agent session
    try engine.startSession("demo_session_001");

    print("✅ Primitive engine initialized with 5 core primitives\n", .{});
    print("📊 Session: demo_session_001\n\n", .{});

    // Demo 1: STORE primitive - Universal storage with rich metadata
    print("1️⃣  STORE Primitive Demo\n", .{});
    print("=======================\n", .{});

    var store_params = std.json.ObjectMap.init(allocator);
    defer store_params.deinit();

    try store_params.put("key", std.json.Value{ .string = "ai_memory_concept" });
    try store_params.put("value", std.json.Value{ .string = "AI agents can compose their own memory architectures using primitive operations. This enables unprecedented flexibility in how AI systems manage and recall information." });

    var metadata = std.json.ObjectMap.init(allocator);
    try metadata.put("confidence", std.json.Value{ .float = 0.9 });
    try metadata.put("source", std.json.Value{ .string = "research_paper" });
    try store_params.put("metadata", std.json.Value{ .object = metadata });

    const store_result = try engine.executePrimitive("store", std.json.Value{ .object = store_params }, "demo_agent");
    print("📝 Stored concept with key 'ai_memory_concept'\n", .{});
    print("⚡ Execution time: {d:.2}ms\n\n", .{store_result.object.get("execution_time_ms").?.float});

    // Demo 2: RETRIEVE primitive - Get data with full context
    print("2️⃣  RETRIEVE Primitive Demo\n", .{});
    print("==========================\n", .{});

    var retrieve_params = std.json.ObjectMap.init(allocator);
    defer retrieve_params.deinit();

    try retrieve_params.put("key", std.json.Value{ .string = "ai_memory_concept" });
    try retrieve_params.put("include_history", std.json.Value{ .bool = false });

    const retrieve_result = try engine.executePrimitive("retrieve", std.json.Value{ .object = retrieve_params }, "demo_agent");
    print("📖 Retrieved concept successfully\n", .{});
    print("✅ Exists: {}\n", .{retrieve_result.object.get("exists").?.bool});
    print("⚡ Execution time: {d:.2}ms\n\n", .{retrieve_result.object.get("execution_time_ms").?.float});

    // Demo 3: SEARCH primitive - Unified search across all indices
    print("3️⃣  SEARCH Primitive Demo\n", .{});
    print("========================\n", .{});

    var search_params = std.json.ObjectMap.init(allocator);
    defer search_params.deinit();

    try search_params.put("query", std.json.Value{ .string = "memory" });
    try search_params.put("type", std.json.Value{ .string = "lexical" });

    var search_options = std.json.ObjectMap.init(allocator);
    try search_options.put("max_results", std.json.Value{ .integer = 5 });
    try search_params.put("options", std.json.Value{ .object = search_options });

    const search_result = try engine.executePrimitive("search", std.json.Value{ .object = search_params }, "demo_agent");
    print("🔍 Performed lexical search for 'memory'\n", .{});
    print("📊 Found {} results\n", .{search_result.object.get("count").?.integer});
    print("⚡ Execution time: {d:.2}ms\n\n", .{search_result.object.get("execution_time_ms").?.float});

    // Demo 4: LINK primitive - Create relationships in knowledge graph
    print("4️⃣  LINK Primitive Demo\n", .{});
    print("======================\n", .{});

    var link_params = std.json.ObjectMap.init(allocator);
    defer link_params.deinit();

    try link_params.put("from", std.json.Value{ .string = "ai_memory_concept" });
    try link_params.put("to", std.json.Value{ .string = "primitive_architecture" });
    try link_params.put("relation", std.json.Value{ .string = "implemented_by" });

    var link_metadata = std.json.ObjectMap.init(allocator);
    try link_metadata.put("strength", std.json.Value{ .float = 0.95 });
    try link_params.put("metadata", std.json.Value{ .object = link_metadata });

    const link_result = try engine.executePrimitive("link", std.json.Value{ .object = link_params }, "demo_agent");
    print("🔗 Created relationship: ai_memory_concept → implemented_by → primitive_architecture\n", .{});
    print("✅ Success: {}\n", .{link_result.object.get("success").?.bool});
    print("⚡ Execution time: {d:.2}ms\n\n", .{link_result.object.get("execution_time_ms").?.float});

    // Demo 5: TRANSFORM primitive - Apply operations to data
    print("5️⃣  TRANSFORM Primitive Demo\n", .{});
    print("===========================\n", .{});

    var transform_params = std.json.ObjectMap.init(allocator);
    defer transform_params.deinit();

    const code_sample =
        \\pub fn calculateDistance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
        \\    const dx = x2 - x1;
        \\    const dy = y2 - y1;
        \\    return @sqrt(dx * dx + dy * dy);
        \\}
        \\
        \\function processData(data) {
        \\    return data.map(x => x * 2);
        \\}
    ;

    try transform_params.put("operation", std.json.Value{ .string = "parse_functions" });
    try transform_params.put("data", std.json.Value{ .string = code_sample });

    var transform_options = std.json.ObjectMap.init(allocator);
    try transform_options.put("language", std.json.Value{ .string = "mixed" });
    try transform_params.put("options", std.json.Value{ .object = transform_options });

    const transform_result = try engine.executePrimitive("transform", std.json.Value{ .object = transform_params }, "demo_agent");
    print("🔧 Parsed functions from code sample\n", .{});
    print("📊 Input size: {} chars → Output size: {} chars\n", .{ 
        transform_result.object.get("input_size").?.integer,
        transform_result.object.get("output_size").?.integer 
    });
    print("⚡ Execution time: {d:.2}ms\n\n", .{transform_result.object.get("execution_time_ms").?.float});

    // Show overall performance statistics
    print("📊 Overall Performance Statistics\n", .{});
    print("================================\n", .{});

    const stats = try engine.getPerformanceStats();
    print("Total executions: {}\n", .{stats.object.get("total_executions").?.integer});
    print("Average execution time: {d:.2}ms\n", .{stats.object.get("avg_execution_time_ms").?.float});
    print("Session duration: {}s\n", .{stats.object.get("session_duration_seconds").?.integer});

    print("\n🎉 Demo completed successfully!\n", .{});
    print("💡 This shows how LLMs can compose primitive operations to build custom memory patterns.\n", .{});
}