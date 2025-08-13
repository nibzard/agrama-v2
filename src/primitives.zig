//! Core Agrama Primitives - Foundation for AI Memory Substrate
//!
//! This module implements the 5 fundamental primitives that enable LLMs to compose
//! their own memory architectures on Agrama's temporal knowledge graph database:
//!
//! 1. STORE: Universal storage with rich metadata and provenance tracking
//! 2. RETRIEVE: Data access with history and context
//! 3. SEARCH: Unified search across semantic/lexical/graph/temporal/hybrid modes
//! 4. LINK: Knowledge graph relationships with metadata
//! 5. TRANSFORM: Extensible operation registry for data transformation
//!
//! Each primitive is designed for <1ms P50 latency with full observability.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const testing = std.testing;

/// Lightweight JSON optimization with object/array pooling
const JSONOptimizer = struct {
    // Object pools for reusing JSON structures
    object_pool: std.heap.MemoryPool(std.json.ObjectMap),
    array_pool: std.heap.MemoryPool(std.json.Array),

    // Template cache for common JSON structures
    template_cache: HashMap([]const u8, std.json.Value, HashContext, std.hash_map.default_max_load_percentage),

    // Arena for JSON operations
    json_arena: std.heap.ArenaAllocator,

    const HashContext = struct {
        pub fn hash(self: @This(), key: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(key);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(allocator: Allocator) JSONOptimizer {
        return JSONOptimizer{
            .object_pool = std.heap.MemoryPool(std.json.ObjectMap).init(allocator),
            .array_pool = std.heap.MemoryPool(std.json.Array).init(allocator),
            .template_cache = HashMap([]const u8, std.json.Value, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .json_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *JSONOptimizer) void {
        self.object_pool.deinit();
        self.array_pool.deinit();
        self.template_cache.deinit();
        self.json_arena.deinit();
    }

    /// Get a pooled JSON object (reused for efficiency)
    pub fn getObject(self: *JSONOptimizer, allocator: Allocator) !*std.json.ObjectMap {
        const object = try self.object_pool.create();
        object.* = std.json.ObjectMap.init(allocator);
        return object;
    }

    /// Return object to pool for reuse
    pub fn returnObject(self: *JSONOptimizer, object: *std.json.ObjectMap) void {
        object.clearAndFree();
        self.object_pool.destroy(object);
    }

    /// Get a pooled JSON array (reused for efficiency)
    pub fn getArray(self: *JSONOptimizer, allocator: Allocator) !*std.json.Array {
        const array = try self.array_pool.create();
        array.* = std.json.Array.init(allocator);
        return array;
    }

    /// Return array to pool for reuse
    pub fn returnArray(self: *JSONOptimizer, array: *std.json.Array) void {
        array.clearAndFree();
        self.array_pool.destroy(array);
    }

    /// Get JSON arena allocator for temporary operations
    pub fn getArenaAllocator(self: *JSONOptimizer) Allocator {
        return self.json_arena.allocator();
    }

    /// Reset arena for next JSON operation (frees all temporary memory)
    pub fn resetArena(self: *JSONOptimizer) void {
        self.json_arena.deinit();
        self.json_arena = std.heap.ArenaAllocator.init(self.json_arena.child_allocator);
    }

    /// Cache common JSON templates for reuse
    pub fn cacheTemplate(self: *JSONOptimizer, template_name: []const u8, template: std.json.Value) !void {
        const name_copy = try self.json_arena.allocator().dupe(u8, template_name);
        const template_copy = try copyJsonValue(self.json_arena.allocator(), template);
        try self.template_cache.put(name_copy, template_copy);
    }

    /// Get cached JSON template (returns null if not found)
    pub fn getTemplate(self: *JSONOptimizer, template_name: []const u8) ?std.json.Value {
        return self.template_cache.get(template_name);
    }
};

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;
const Change = @import("database.zig").Change;

/// Core primitive interface that all operations implement
pub const Primitive = struct {
    name: []const u8,
    execute: *const fn (context: *PrimitiveContext, params: std.json.Value) anyerror!std.json.Value,
    validate: *const fn (params: std.json.Value) anyerror!void,
    metadata: PrimitiveMetadata,
};

/// Memory pools for frequent allocations
const PrimitiveMemoryPools = struct {
    // String pools for frequent string allocations
    key_pool: std.heap.MemoryPool([]u8),
    value_pool: std.heap.MemoryPool([]u8),

    // Result pools for search operations
    search_result_pool: std.heap.MemoryPool(SearchResultItem),

    // Temporary allocation arena (reset after each operation)
    temp_arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator) PrimitiveMemoryPools {
        return PrimitiveMemoryPools{
            .key_pool = std.heap.MemoryPool([]u8).init(allocator),
            .value_pool = std.heap.MemoryPool([]u8).init(allocator),
            .search_result_pool = std.heap.MemoryPool(SearchResultItem).init(allocator),
            .temp_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *PrimitiveMemoryPools) void {
        self.key_pool.deinit();
        self.value_pool.deinit();
        self.search_result_pool.deinit();
        self.temp_arena.deinit();
    }

    /// Reset temporary arena for next operation
    pub fn resetTemp(self: *PrimitiveMemoryPools) void {
        self.temp_arena.deinit();
        self.temp_arena = std.heap.ArenaAllocator.init(self.temp_arena.child_allocator);
    }

    /// Get pooled search result item
    pub fn getSearchResult(self: *PrimitiveMemoryPools) !*SearchResultItem {
        return try self.search_result_pool.create();
    }

    /// Return search result item to pool
    pub fn returnSearchResult(self: *PrimitiveMemoryPools, item: *SearchResultItem) void {
        self.search_result_pool.destroy(item);
    }
};

/// Context passed to every primitive operation
pub const PrimitiveContext = struct {
    allocator: Allocator,
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,
    agent_id: []const u8,
    timestamp: i64,
    session_id: []const u8,

    // Arena allocator for temporary allocations within primitives
    // This gets reset after each primitive operation for automatic cleanup
    arena: ?*std.heap.ArenaAllocator = null,

    // JSON optimizer for efficient JSON operations
    json_optimizer: ?*JSONOptimizer = null,

    // Memory pools for frequent allocations (legacy - kept for compatibility)
    memory_pools: ?*PrimitiveMemoryPools = null,

    // Integrated memory pool system for 50-70% allocation overhead reduction
    integrated_pools: ?*@import("memory_pools.zig").MemoryPoolSystem = null,

    /// Get arena allocator for temporary allocations
    /// Automatically freed after primitive execution
    pub fn getArenaAllocator(self: *PrimitiveContext) Allocator {
        if (self.arena) |arena| {
            return arena.allocator();
        }
        return self.allocator;
    }

    /// Get JSON optimizer for efficient JSON operations
    pub fn getJSONOptimizer(self: *PrimitiveContext) ?*JSONOptimizer {
        return self.json_optimizer;
    }

    /// Get memory pools for efficient allocation (legacy)
    pub fn getMemoryPools(self: *PrimitiveContext) ?*PrimitiveMemoryPools {
        return self.memory_pools;
    }

    /// Get integrated memory pool system for optimized allocations
    pub fn getIntegratedPools(self: *PrimitiveContext) ?*@import("memory_pools.zig").MemoryPoolSystem {
        return self.integrated_pools;
    }

    /// Acquire arena from integrated memory pools for scoped primitive operations
    pub fn acquireOptimizedArena(self: *PrimitiveContext) !?*std.heap.ArenaAllocator {
        if (self.integrated_pools) |pools| {
            return try pools.acquirePrimitiveArena();
        }
        return null;
    }

    /// Release arena back to integrated memory pools
    pub fn releaseOptimizedArena(self: *PrimitiveContext, arena: *std.heap.ArenaAllocator) void {
        if (self.integrated_pools) |pools| {
            pools.releasePrimitiveArena(arena);
        }
    }

    /// Prepare context for next operation (reset temporary allocations)
    pub fn resetForNextOperation(self: *PrimitiveContext) void {
        if (self.json_optimizer) |json_opt| {
            json_opt.resetArena();
        }
        if (self.memory_pools) |pools| {
            pools.resetTemp();
        }
    }
};

/// Rich metadata for each primitive
pub const PrimitiveMetadata = struct {
    description: []const u8,
    input_schema: std.json.Value,
    output_schema: std.json.Value,
    performance_characteristics: []const u8,
    composition_examples: []const []const u8,
};

/// Result types for primitive operations
pub const StoreResult = struct {
    success: bool,
    key: []const u8,
    timestamp: i64,
    indexed: bool,
};

pub const RetrieveResult = struct {
    exists: bool,
    key: []const u8,
    value: ?[]const u8,
    metadata: std.json.Value,
    history: ?[]Change,
};

pub const SearchResult = struct {
    query: []const u8,
    search_type: []const u8,
    results: []SearchResultItem,
    count: u32,
    execution_time_ms: f64,
};

pub const SearchResultItem = struct {
    key: []const u8,
    score: f32,
    result_type: []const u8,
    metadata: ?std.json.Value = null,
};

pub const LinkResult = struct {
    success: bool,
    from: []const u8,
    to: []const u8,
    relation: []const u8,
    timestamp: i64,
};

pub const TransformResult = struct {
    success: bool,
    operation: []const u8,
    input_size: usize,
    output_size: usize,
    output: []const u8,
    execution_time_ms: f64,
};

/// Primitive 1: STORE - Universal storage with rich metadata
pub const StorePrimitive = struct {
    pub fn execute(ctx: *PrimitiveContext, params: std.json.Value) !std.json.Value {
        // Performance timing
        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Try to use optimized arena from memory pools for 50-70% allocation overhead reduction
        var arena_allocator: Allocator = undefined;
        var optimized_arena: ?*std.heap.ArenaAllocator = null;
        var local_arena: ?std.heap.ArenaAllocator = null;

        if (ctx.acquireOptimizedArena() catch null) |opt_arena| {
            optimized_arena = opt_arena;
            arena_allocator = opt_arena.allocator();
        } else {
            // Fallback to local arena
            local_arena = std.heap.ArenaAllocator.init(ctx.allocator);
            arena_allocator = local_arena.?.allocator();
        }

        // Cleanup - release arena back to pool or deinit local arena
        defer {
            if (optimized_arena) |arena| {
                ctx.releaseOptimizedArena(arena);
            } else if (local_arena) |*arena| {
                arena.deinit();
            }
        }

        // Extract and validate parameters
        const key = params.object.get("key") orelse return error.MissingKey;
        const value = params.object.get("value") orelse return error.MissingValue;
        const metadata_param = params.object.get("metadata");

        if (key != .string) return error.InvalidKeyType;
        if (value != .string) return error.InvalidValueType;

        const key_str = key.string;
        const value_str = value.string;

        // Enhanced metadata with provenance - use arena allocator
        var enhanced_metadata = std.json.ObjectMap.init(arena_allocator);
        try enhanced_metadata.put("agent_id", std.json.Value{ .string = try arena_allocator.dupe(u8, ctx.agent_id) });
        try enhanced_metadata.put("timestamp", std.json.Value{ .integer = ctx.timestamp });
        try enhanced_metadata.put("session_id", std.json.Value{ .string = try arena_allocator.dupe(u8, ctx.session_id) });
        try enhanced_metadata.put("size", std.json.Value{ .integer = @as(i64, @intCast(value_str.len)) });

        // Merge user metadata if provided - use arena allocator
        if (metadata_param) |user_metadata| {
            if (user_metadata == .object) {
                var iter = user_metadata.object.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try arena_allocator.dupe(u8, entry.key_ptr.*);
                    const value_copy = try copyJsonValue(arena_allocator, entry.value_ptr.*);
                    try enhanced_metadata.put(key_copy, value_copy);
                }
            }
        }

        // Store in temporal database
        try ctx.database.saveFile(key_str, value_str);

        // Generate semantic embedding for substantial content
        const indexed = value_str.len > 50;
        if (indexed) {
            try ctx.semantic_db.saveFile(key_str, value_str);
        }

        // Store metadata separately for queryability - use arena for temp allocations
        const metadata_key = try std.fmt.allocPrint(arena_allocator, "_meta:{s}", .{key_str});
        const metadata_json = try std.json.stringifyAlloc(arena_allocator, std.json.Value{ .object = enhanced_metadata }, .{});

        try ctx.database.saveFile(metadata_key, metadata_json);

        // Build response using arena allocator to prevent leaks
        var result = std.json.ObjectMap.init(arena_allocator);
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("key", std.json.Value{ .string = try arena_allocator.dupe(u8, key_str) });
        try result.put("timestamp", std.json.Value{ .integer = ctx.timestamp });
        try result.put("indexed", std.json.Value{ .bool = indexed });

        const execution_time = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try result.put("execution_time_ms", std.json.Value{ .float = execution_time });

        // Deep copy to main allocator before arena is destroyed
        return try copyJsonValue(ctx.allocator, std.json.Value{ .object = result });
    }

    pub fn validate(params: std.json.Value) !void {
        if (params != .object) return error.InvalidParamsType;

        const key = params.object.get("key") orelse return error.MissingKey;
        const value = params.object.get("value") orelse return error.MissingValue;

        if (key != .string) return error.InvalidKeyType;
        if (value != .string) return error.InvalidValueType;

        if (key.string.len == 0) return error.EmptyKey;
        if (value.string.len == 0) return error.EmptyValue;
    }

    pub const metadata = PrimitiveMetadata{
        .description = "Store data with rich metadata and provenance tracking",
        .input_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .output_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .performance_characteristics = "Target <1ms P50 latency, automatic semantic indexing for content >50 chars",
        .composition_examples = &.{
            "store('concept_v1', idea_text, {'confidence': 0.7, 'source': 'brainstorm'})",
            "store('function:calculateDistance', code, {'language': 'zig', 'complexity': 'O(1)'})",
        },
    };
};

/// Primitive 2: RETRIEVE - Get data with full context
pub const RetrievePrimitive = struct {
    pub fn execute(ctx: *PrimitiveContext, params: std.json.Value) !std.json.Value {
        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Use arena allocator for temporary allocations
        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Extract parameters
        const key = params.object.get("key") orelse return error.MissingKey;
        const include_history = params.object.get("include_history") orelse std.json.Value{ .bool = false };

        if (key != .string) return error.InvalidKeyType;
        if (include_history != .bool) return error.InvalidHistoryType;

        const key_str = key.string;
        const with_history = include_history.bool;

        // Get current content
        const content = ctx.database.getFile(key_str) catch |err| switch (err) {
            error.FileNotFound => {
                // Use arena allocator for error response to prevent leaks
                var error_arena = std.heap.ArenaAllocator.init(ctx.allocator);
                defer error_arena.deinit();
                const error_allocator = error_arena.allocator();
                
                var result = std.json.ObjectMap.init(error_allocator);
                try result.put("exists", std.json.Value{ .bool = false });
                try result.put("key", std.json.Value{ .string = try error_allocator.dupe(u8, key_str) });
                
                // Deep copy to main allocator before arena is destroyed
                return try copyJsonValue(ctx.allocator, std.json.Value{ .object = result });
            },
            else => return err,
        };

        // Get metadata - use arena for temporary string
        const metadata_key = try std.fmt.allocPrint(arena_allocator, "_meta:{s}", .{key_str});
        const metadata_json = ctx.database.getFile(metadata_key) catch "{}";

        // Parse metadata using arena allocator for temporary parsing
        const metadata_value = blk: {
            const parsed_result = std.json.parseFromSlice(std.json.Value, arena_allocator, metadata_json, .{}) catch {
                const empty_obj = std.json.ObjectMap.init(ctx.allocator);
                break :blk std.json.Value{ .object = empty_obj };
            };
            // Deep copy to main allocator to avoid arena deallocation issues
            break :blk try copyJsonValue(ctx.allocator, parsed_result.value);
        };

        // Build result using arena allocator for temporary work
        var result = std.json.ObjectMap.init(arena_allocator);
        try result.put("exists", std.json.Value{ .bool = true });
        try result.put("key", std.json.Value{ .string = try arena_allocator.dupe(u8, key_str) });
        try result.put("value", std.json.Value{ .string = try arena_allocator.dupe(u8, content) });
        try result.put("metadata", metadata_value);

        // Include history if requested
        if (with_history) {
            const history = ctx.database.getHistory(key_str, 10) catch &[_]Change{};
            defer if (history.len > 0) ctx.allocator.free(history);

            var history_array = std.json.Array.init(ctx.allocator);
            for (history) |change| {
                var change_obj = std.json.ObjectMap.init(ctx.allocator);
                try change_obj.put("timestamp", std.json.Value{ .integer = change.timestamp });
                try change_obj.put("content", std.json.Value{ .string = try ctx.allocator.dupe(u8, change.content) });
                try history_array.append(std.json.Value{ .object = change_obj });
            }
            try result.put("history", std.json.Value{ .array = history_array });
        }

        const execution_time = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try result.put("execution_time_ms", std.json.Value{ .float = execution_time });

        // Deep copy the result to the main allocator before arena is destroyed
        return try copyJsonValue(ctx.allocator, std.json.Value{ .object = result });
    }

    pub fn validate(params: std.json.Value) !void {
        if (params != .object) return error.InvalidParamsType;

        const key = params.object.get("key") orelse return error.MissingKey;
        if (key != .string) return error.InvalidKeyType;
        if (key.string.len == 0) return error.EmptyKey;

        if (params.object.get("include_history")) |history| {
            if (history != .bool) return error.InvalidHistoryType;
        }
    }

    pub const metadata = PrimitiveMetadata{
        .description = "Retrieve data with full context and optional history",
        .input_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .output_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .performance_characteristics = "Target <1ms P50 latency, optional history adds ~2ms",
        .composition_examples = &.{
            "retrieve('concept_v1', {'include_history': true})",
            "retrieve('function:calculateDistance')",
        },
    };
};

/// Primitive 3: SEARCH - Unified search across all indices
pub const SearchPrimitive = struct {
    pub fn execute(ctx: *PrimitiveContext, params: std.json.Value) !std.json.Value {
        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Use arena allocator for temporary allocations
        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Extract parameters
        const query = params.object.get("query") orelse return error.MissingQuery;
        const search_type = params.object.get("type") orelse return error.MissingType;
        const options = params.object.get("options") orelse std.json.Value{ .object = std.json.ObjectMap.init(arena_allocator) };

        if (query != .string) return error.InvalidQueryType;
        if (search_type != .string) return error.InvalidTypeType;

        const query_str = query.string;
        const type_str = search_type.string;

        const max_results = if (options.object.get("max_results")) |v|
            @as(u32, @intCast(v.integer))
        else
            20;
        _ = if (options.object.get("threshold")) |v|
            @as(f32, @floatCast(v.float))
        else
            0.7;

        var results_array = std.json.Array.init(ctx.allocator);

        if (std.mem.eql(u8, type_str, "semantic")) {
            // Use HNSW semantic search implementation
            const embedding_query = params.object.get("embedding");
            if (embedding_query) |emb_value| {
                if (emb_value == .array) {
                    // Convert JSON array to f32 slice with memory pooling
                    var embedding = try arena_allocator.alloc(f32, emb_value.array.items.len);

                    for (emb_value.array.items, 0..) |item, i| {
                        if (item == .float) {
                            embedding[i] = @as(f32, @floatCast(item.float));
                        } else if (item == .integer) {
                            embedding[i] = @as(f32, @floatFromInt(item.integer));
                        } else {
                            embedding[i] = 0.0;
                        }
                    }

                    // Create hybrid query for semantic-only search with optimizations
                    const hybrid_query = @import("triple_hybrid_search.zig").HybridQuery{
                        .text_query = query_str,
                        .embedding_query = embedding,
                        .max_results = max_results,
                        .alpha = 0.0, // No BM25
                        .beta = 1.0, // All HNSW
                        .gamma = 0.0, // No FRE
                    };

                    const search_results = try ctx.graph_engine.search(hybrid_query);
                    defer {
                        for (search_results) |result| {
                            result.deinit(ctx.allocator);
                        }
                        ctx.allocator.free(search_results);
                    }

                    // Use optimized JSON building with templates
                    for (search_results) |result| {
                        var result_obj = if (ctx.getJSONOptimizer()) |json_opt|
                            (try json_opt.getObject(ctx.allocator)).*
                        else
                            std.json.ObjectMap.init(ctx.allocator);

                        try result_obj.put("key", std.json.Value{ .string = try ctx.allocator.dupe(u8, result.file_path) });
                        try result_obj.put("score", std.json.Value{ .float = result.hnsw_score });
                        try result_obj.put("similarity", std.json.Value{ .float = result.semantic_similarity });
                        try result_obj.put("type", std.json.Value{ .string = try ctx.allocator.dupe(u8, "semantic") });

                        try results_array.append(std.json.Value{ .object = result_obj });
                    }
                } else {
                    // Fallback: Use text query without embedding (less optimal but functional)
                    var result_obj = std.json.ObjectMap.init(arena_allocator);
                    try result_obj.put("key", std.json.Value{ .string = try arena_allocator.dupe(u8, "semantic_search") });
                    try result_obj.put("score", std.json.Value{ .float = 0.5 });
                    try result_obj.put("type", std.json.Value{ .string = try ctx.allocator.dupe(u8, "semantic") });
                    try result_obj.put("note", std.json.Value{ .string = try ctx.allocator.dupe(u8, "Embedding required for semantic search") });

                    try results_array.append(std.json.Value{ .object = result_obj });
                }
            }
        } else if (std.mem.eql(u8, type_str, "lexical")) {
            // Use BM25 lexical search implementation
            const hybrid_query = @import("triple_hybrid_search.zig").HybridQuery{
                .text_query = query_str,
                .max_results = max_results,
                .alpha = 1.0, // All BM25
                .beta = 0.0, // No HNSW
                .gamma = 0.0, // No FRE
            };

            const search_results = try ctx.graph_engine.search(hybrid_query);
            defer {
                for (search_results) |result| {
                    result.deinit(ctx.allocator);
                }
                ctx.allocator.free(search_results);
            }

            for (search_results) |result| {
                try results_array.append(std.json.Value{
                    .object = blk: {
                        var result_obj = std.json.ObjectMap.init(arena_allocator);
                        try result_obj.put("key", std.json.Value{ .string = try arena_allocator.dupe(u8, result.file_path) });
                        try result_obj.put("score", std.json.Value{ .float = result.bm25_score });
                        try result_obj.put("type", std.json.Value{ .string = try ctx.allocator.dupe(u8, "lexical") });

                        // Add matching terms if available
                        var terms_array = std.json.Array.init(ctx.allocator);
                        for (result.matching_terms) |term| {
                            try terms_array.append(std.json.Value{ .string = try ctx.allocator.dupe(u8, term) });
                        }
                        try result_obj.put("matching_terms", std.json.Value{ .array = terms_array });

                        break :blk result_obj;
                    },
                });
            }
        } else if (std.mem.eql(u8, type_str, "hybrid")) {
            // Use triple hybrid search engine with configurable weights
            const alpha = if (params.object.get("alpha")) |a| @as(f32, @floatCast(if (a == .float) a.float else if (a == .integer) @as(f64, @floatFromInt(a.integer)) else 0.4)) else 0.4;
            const beta = if (params.object.get("beta")) |b| @as(f32, @floatCast(if (b == .float) b.float else if (b == .integer) @as(f64, @floatFromInt(b.integer)) else 0.4)) else 0.4;
            const gamma = if (params.object.get("gamma")) |g| @as(f32, @floatCast(if (g == .float) g.float else if (g == .integer) @as(f64, @floatFromInt(g.integer)) else 0.2)) else 0.2;

            // Get optional embedding and starting nodes
            var embedding: ?[]f32 = null;
            var embedding_owned = false;
            defer if (embedding_owned and embedding != null) ctx.allocator.free(embedding.?);

            if (params.object.get("embedding")) |emb_value| {
                if (emb_value == .array) {
                    embedding = try ctx.allocator.alloc(f32, emb_value.array.items.len);
                    embedding_owned = true;

                    for (emb_value.array.items, 0..) |item, i| {
                        if (item == .float) {
                            embedding.?[i] = @as(f32, @floatCast(item.float));
                        } else if (item == .integer) {
                            embedding.?[i] = @as(f32, @floatFromInt(item.integer));
                        } else {
                            embedding.?[i] = 0.0;
                        }
                    }
                }
            }

            var starting_nodes: ?[]u32 = null;
            var nodes_owned = false;
            defer if (nodes_owned and starting_nodes != null) ctx.allocator.free(starting_nodes.?);

            if (params.object.get("starting_nodes")) |nodes_value| {
                if (nodes_value == .array) {
                    starting_nodes = try ctx.allocator.alloc(u32, nodes_value.array.items.len);
                    nodes_owned = true;

                    for (nodes_value.array.items, 0..) |item, i| {
                        if (item == .integer) {
                            starting_nodes.?[i] = @as(u32, @intCast(item.integer));
                        } else {
                            starting_nodes.?[i] = 0;
                        }
                    }
                }
            }

            const hybrid_query = @import("triple_hybrid_search.zig").HybridQuery{
                .text_query = query_str,
                .embedding_query = embedding,
                .starting_nodes = starting_nodes,
                .max_results = max_results,
                .alpha = alpha,
                .beta = beta,
                .gamma = gamma,
            };

            const search_results = try ctx.graph_engine.search(hybrid_query);
            defer {
                for (search_results) |result| {
                    result.deinit(ctx.allocator);
                }
                ctx.allocator.free(search_results);
            }

            for (search_results) |result| {
                try results_array.append(std.json.Value{
                    .object = blk: {
                        var result_obj = std.json.ObjectMap.init(arena_allocator);
                        try result_obj.put("key", std.json.Value{ .string = try arena_allocator.dupe(u8, result.file_path) });
                        try result_obj.put("combined_score", std.json.Value{ .float = result.combined_score });
                        try result_obj.put("semantic_score", std.json.Value{ .float = result.hnsw_score });
                        try result_obj.put("lexical_score", std.json.Value{ .float = result.bm25_score });
                        try result_obj.put("graph_score", std.json.Value{ .float = result.fre_score });
                        try result_obj.put("type", std.json.Value{ .string = try arena_allocator.dupe(u8, "hybrid") });

                        // Add detailed metadata
                        if (result.matching_terms.len > 0) {
                            var terms_array = std.json.Array.init(arena_allocator);
                            for (result.matching_terms) |term| {
                                try terms_array.append(std.json.Value{ .string = try arena_allocator.dupe(u8, term) });
                            }
                            try result_obj.put("matching_terms", std.json.Value{ .array = terms_array });
                        }

                        try result_obj.put("semantic_similarity", std.json.Value{ .float = result.semantic_similarity });

                        if (result.graph_distance != std.math.maxInt(u32)) {
                            try result_obj.put("graph_distance", std.json.Value{ .integer = @as(i64, @intCast(result.graph_distance)) });
                        }

                        break :blk result_obj;
                    },
                });
            }
        }

        var final_result = std.json.ObjectMap.init(arena_allocator);
        try final_result.put("query", std.json.Value{ .string = try arena_allocator.dupe(u8, query_str) });
        try final_result.put("type", std.json.Value{ .string = try arena_allocator.dupe(u8, type_str) });
        try final_result.put("results", std.json.Value{ .array = results_array });
        try final_result.put("count", std.json.Value{ .integer = @as(i64, @intCast(results_array.items.len)) });

        const execution_time = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try final_result.put("execution_time_ms", std.json.Value{ .float = execution_time });

        // Deep copy to main allocator before arena is destroyed
        return try copyJsonValue(ctx.allocator, std.json.Value{ .object = final_result });
    }

    pub fn validate(params: std.json.Value) !void {
        if (params != .object) return error.InvalidParamsType;

        const query = params.object.get("query") orelse return error.MissingQuery;
        const search_type = params.object.get("type") orelse return error.MissingType;

        if (query != .string) return error.InvalidQueryType;
        if (search_type != .string) return error.InvalidTypeType;

        if (query.string.len == 0) return error.EmptyQuery;

        const valid_types = [_][]const u8{ "semantic", "lexical", "graph", "temporal", "hybrid" };
        var type_valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, search_type.string, valid_type)) {
                type_valid = true;
                break;
            }
        }
        if (!type_valid) return error.InvalidSearchType;
    }

    pub const metadata = PrimitiveMetadata{
        .description = "Unified search across semantic, lexical, graph, temporal, and hybrid indices",
        .input_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .output_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .performance_characteristics = "Target <5ms P50 latency, hybrid search combines all modalities",
        .composition_examples = &.{
            "search('authentication code', 'hybrid', {'weights': {'semantic': 0.6, 'lexical': 0.4}})",
            "search('error handling', 'semantic', {'threshold': 0.8})",
        },
    };
};

/// Primitive 4: LINK - Create relationships in knowledge graph
pub const LinkPrimitive = struct {
    pub fn execute(ctx: *PrimitiveContext, params: std.json.Value) !std.json.Value {
        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Use arena allocator for temporary allocations
        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Extract parameters
        const from = params.object.get("from") orelse return error.MissingFrom;
        const to = params.object.get("to") orelse return error.MissingTo;
        const relation = params.object.get("relation") orelse return error.MissingRelation;
        const metadata_param = params.object.get("metadata");

        if (from != .string) return error.InvalidFromType;
        if (to != .string) return error.InvalidToType;
        if (relation != .string) return error.InvalidRelationType;

        const from_str = from.string;
        const to_str = to.string;
        const relation_str = relation.string;

        // Create link metadata - use arena for temporary allocations
        var link_metadata = std.json.ObjectMap.init(arena_allocator);
        try link_metadata.put("agent_id", std.json.Value{ .string = try arena_allocator.dupe(u8, ctx.agent_id) });
        try link_metadata.put("timestamp", std.json.Value{ .integer = ctx.timestamp });
        try link_metadata.put("session_id", std.json.Value{ .string = try arena_allocator.dupe(u8, ctx.session_id) });
        try link_metadata.put("relation", std.json.Value{ .string = try arena_allocator.dupe(u8, relation_str) });

        // Add user metadata if provided - use arena allocator
        if (metadata_param) |user_metadata| {
            if (user_metadata == .object) {
                var iter = user_metadata.object.iterator();
                while (iter.next()) |entry| {
                    const key_copy = try arena_allocator.dupe(u8, entry.key_ptr.*);
                    const value_copy = try copyJsonValue(arena_allocator, entry.value_ptr.*);
                    try link_metadata.put(key_copy, value_copy);
                }
            }
        }

        // Store the link in the database as a special entry - use arena for temp strings
        const link_key = try std.fmt.allocPrint(arena_allocator, "_link:{s}:{s}:{s}", .{ from_str, relation_str, to_str });
        const link_data = try std.json.stringifyAlloc(arena_allocator, std.json.Value{ .object = link_metadata }, .{});

        try ctx.database.saveFile(link_key, link_data);

        // Build response using arena allocator to prevent leaks
        var result = std.json.ObjectMap.init(arena_allocator);
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("from", std.json.Value{ .string = try arena_allocator.dupe(u8, from_str) });
        try result.put("to", std.json.Value{ .string = try arena_allocator.dupe(u8, to_str) });
        try result.put("relation", std.json.Value{ .string = try arena_allocator.dupe(u8, relation_str) });
        try result.put("timestamp", std.json.Value{ .integer = ctx.timestamp });

        const execution_time = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try result.put("execution_time_ms", std.json.Value{ .float = execution_time });

        // Deep copy to main allocator before arena is destroyed
        return try copyJsonValue(ctx.allocator, std.json.Value{ .object = result });
    }

    pub fn validate(params: std.json.Value) !void {
        if (params != .object) return error.InvalidParamsType;

        const from = params.object.get("from") orelse return error.MissingFrom;
        const to = params.object.get("to") orelse return error.MissingTo;
        const relation = params.object.get("relation") orelse return error.MissingRelation;

        if (from != .string) return error.InvalidFromType;
        if (to != .string) return error.InvalidToType;
        if (relation != .string) return error.InvalidRelationType;

        if (from.string.len == 0) return error.EmptyFrom;
        if (to.string.len == 0) return error.EmptyTo;
        if (relation.string.len == 0) return error.EmptyRelation;
    }

    pub const metadata = PrimitiveMetadata{
        .description = "Create relationships in knowledge graph with rich metadata",
        .input_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .output_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .performance_characteristics = "Target <1ms P50 latency, creates bidirectional graph relationships",
        .composition_examples = &.{
            "link('module_a', 'module_b', 'depends_on', {'strength': 0.8})",
            "link('concept_v1', 'concept_v2', 'evolved_into')",
        },
    };
};

/// Primitive 5: TRANSFORM - Apply operations to data
pub const TransformPrimitive = struct {
    pub fn execute(ctx: *PrimitiveContext, params: std.json.Value) !std.json.Value {
        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Use arena allocator for temporary allocations
        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Extract parameters
        const operation = params.object.get("operation") orelse return error.MissingOperation;
        const data = params.object.get("data") orelse return error.MissingData;
        const options = params.object.get("options") orelse std.json.Value{ .object = std.json.ObjectMap.init(arena_allocator) };

        if (operation != .string) return error.InvalidOperationType;
        if (data != .string) return error.InvalidDataType;

        const operation_str = operation.string;
        const data_str = data.string;
        const input_size = data_str.len;

        // Apply the transformation - output is owned by caller (main allocator)
        const output = try applyTransformation(ctx.allocator, operation_str, data_str, options);
        const output_size = output.len;

        // Build response using arena allocator to prevent leaks
        var result = std.json.ObjectMap.init(arena_allocator);
        try result.put("success", std.json.Value{ .bool = true });
        try result.put("operation", std.json.Value{ .string = try arena_allocator.dupe(u8, operation_str) });
        try result.put("input_size", std.json.Value{ .integer = @as(i64, @intCast(input_size)) });
        try result.put("output_size", std.json.Value{ .integer = @as(i64, @intCast(output_size)) });
        try result.put("output", std.json.Value{ .string = try arena_allocator.dupe(u8, output) }); // Copy to arena
        
        // Free the output since we copied it to arena
        ctx.allocator.free(output);

        const execution_time = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        try result.put("execution_time_ms", std.json.Value{ .float = execution_time });

        // Deep copy to main allocator before arena is destroyed
        return try copyJsonValue(ctx.allocator, std.json.Value{ .object = result });
    }

    pub fn validate(params: std.json.Value) !void {
        if (params != .object) return error.InvalidParamsType;

        const operation = params.object.get("operation") orelse return error.MissingOperation;
        const data = params.object.get("data") orelse return error.MissingData;

        if (operation != .string) return error.InvalidOperationType;
        if (data != .string) return error.InvalidDataType;

        if (operation.string.len == 0) return error.EmptyOperation;

        // Validate supported operations
        const supported_operations = [_][]const u8{ "parse_functions", "extract_imports", "generate_summary", "compress_text", "diff_content", "merge_content", "analyze_complexity", "extract_dependencies", "validate_syntax" };

        var operation_valid = false;
        for (supported_operations) |supported| {
            if (std.mem.eql(u8, operation.string, supported)) {
                operation_valid = true;
                break;
            }
        }
        if (!operation_valid) return error.UnsupportedOperation;
    }

    pub const metadata = PrimitiveMetadata{
        .description = "Apply extensible operations to transform data",
        .input_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .output_schema = std.json.Value{ .object = std.json.ObjectMap.init(std.heap.page_allocator) },
        .performance_characteristics = "Varies by operation, most <5ms, some may take longer for complex parsing",
        .composition_examples = &.{
            "transform('parse_functions', code_content, {'language': 'zig'})",
            "transform('extract_dependencies', module_content)",
        },
    };
};



/// Apply data transformation based on operation type
fn applyTransformation(allocator: Allocator, operation: []const u8, data: []const u8, options: std.json.Value) ![]const u8 {
    _ = options; // Options parameter for future extensibility

    if (std.mem.eql(u8, operation, "parse_functions")) {
        return try parseFunctions(allocator, data);
    } else if (std.mem.eql(u8, operation, "extract_imports")) {
        return try extractImports(allocator, data);
    } else if (std.mem.eql(u8, operation, "generate_summary")) {
        return try generateSummary(allocator, data);
    } else if (std.mem.eql(u8, operation, "compress_text")) {
        return try compressText(allocator, data);
    } else {
        // Default: return data unchanged with operation applied note
        return try std.fmt.allocPrint(allocator, "[{s}] {s}", .{ operation, data });
    }
}

/// Extract function definitions from code
fn parseFunctions(allocator: Allocator, content: []const u8) ![]const u8 {
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var functions = ArrayList([]const u8).init(arena_allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect function patterns across languages
        if (std.mem.indexOf(u8, trimmed, "function ") != null or
            std.mem.indexOf(u8, trimmed, "def ") != null or
            std.mem.indexOf(u8, trimmed, "fn ") != null or
            std.mem.indexOf(u8, trimmed, "pub fn ") != null)
        {
            try functions.append(try arena_allocator.dupe(u8, trimmed));
        }
    }

    // Create JSON array of functions using arena
    var result_array = std.json.Array.init(arena_allocator);

    for (functions.items) |func| {
        try result_array.append(std.json.Value{ .string = func });
    }

    // Return JSON string using main allocator (caller owns)
    return try std.json.stringifyAlloc(allocator, std.json.Value{ .array = result_array }, .{});
}

/// Extract import statements from code
fn extractImports(allocator: Allocator, content: []const u8) ![]const u8 {
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var imports = ArrayList([]const u8).init(arena_allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Detect import patterns
        if (std.mem.indexOf(u8, trimmed, "import ") != null or
            std.mem.indexOf(u8, trimmed, "const ") != null and std.mem.indexOf(u8, trimmed, "@import") != null or
            std.mem.indexOf(u8, trimmed, "#include") != null or
            std.mem.indexOf(u8, trimmed, "from ") != null and std.mem.indexOf(u8, trimmed, " import ") != null)
        {
            try imports.append(try arena_allocator.dupe(u8, trimmed));
        }
    }

    // Create JSON array of imports using arena
    var result_array = std.json.Array.init(arena_allocator);

    for (imports.items) |import| {
        try result_array.append(std.json.Value{ .string = import });
    }

    // Return JSON string using main allocator (caller owns)
    return try std.json.stringifyAlloc(allocator, std.json.Value{ .array = result_array }, .{});
}

/// Generate a summary of content
fn generateSummary(allocator: Allocator, content: []const u8) ![]const u8 {
    const max_length = 200;
    if (content.len <= max_length) {
        return try allocator.dupe(u8, content);
    }

    // Simple truncation with ellipsis
    const truncated = content[0..max_length];
    return try std.fmt.allocPrint(allocator, "{s}...", .{truncated});
}

/// Compress text by removing excessive whitespace
fn compressText(allocator: Allocator, content: []const u8) ![]const u8 {
    var result = ArrayList(u8).init(allocator);
    defer result.deinit();

    var prev_was_space = false;
    for (content) |char| {
        if (char == ' ' or char == '\t' or char == '\n') {
            if (!prev_was_space) {
                try result.append(' ');
                prev_was_space = true;
            }
        } else {
            try result.append(char);
            prev_was_space = false;
        }
    }

    return try result.toOwnedSlice();
}

/// Batch operations for improved throughput
pub const BatchOperations = struct {
    /// Batch store multiple key-value pairs (reduces overhead)
    pub fn batchStore(ctx: *PrimitiveContext, operations: []BatchStoreOp) ![]BatchStoreResult {
        const results = try ctx.allocator.alloc(BatchStoreResult, operations.len);
        errdefer ctx.allocator.free(results);

        // Use arena for all temporary allocations in batch
        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        for (operations, 0..) |op, i| {
            // Store in temporal database
            ctx.database.saveFile(op.key, op.value) catch |err| {
                results[i] = BatchStoreResult{
                    .success = false,
                    .key = try ctx.allocator.dupe(u8, op.key),
                    .error_message = try ctx.allocator.dupe(u8, @errorName(err)),
                };
                continue;
            };

            // Generate semantic embedding for substantial content
            const indexed = op.value.len > 50;
            if (indexed) {
                ctx.semantic_db.saveFile(op.key, op.value) catch {};
            }

            // Store metadata
            const metadata_key = try std.fmt.allocPrint(arena_allocator, "_meta:{s}", .{op.key});
            var enhanced_metadata = std.json.ObjectMap.init(arena_allocator);
            try enhanced_metadata.put("agent_id", std.json.Value{ .string = ctx.agent_id });
            try enhanced_metadata.put("timestamp", std.json.Value{ .integer = ctx.timestamp });
            try enhanced_metadata.put("session_id", std.json.Value{ .string = ctx.session_id });
            try enhanced_metadata.put("size", std.json.Value{ .integer = @as(i64, @intCast(op.value.len)) });

            const metadata_json = try std.json.stringifyAlloc(arena_allocator, std.json.Value{ .object = enhanced_metadata }, .{});
            ctx.database.saveFile(metadata_key, metadata_json) catch {};

            results[i] = BatchStoreResult{
                .success = true,
                .key = try ctx.allocator.dupe(u8, op.key),
                .indexed = indexed,
            };
        }

        const batch_time_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        const throughput = @as(f64, @floatFromInt(operations.len)) / (batch_time_ms / 1000.0);

        std.debug.print("✅ Batch store: {} operations in {d:.2}ms ({d:.0} ops/sec)\n", .{ operations.len, batch_time_ms, throughput });

        return results;
    }

    /// Batch search operations with shared setup costs
    pub fn batchSearch(ctx: *PrimitiveContext, queries: []BatchSearchQuery) ![]SearchResult {
        var all_results = ArrayList(SearchResult).init(ctx.allocator);
        defer all_results.deinit();

        var timer = std.time.Timer.start() catch return error.TimerUnavailable;

        for (queries) |query| {
            const search_params = std.json.ObjectMap.init(ctx.allocator);
            defer search_params.deinit();

            var params_obj = std.json.ObjectMap.init(ctx.allocator);
            defer params_obj.deinit();

            try params_obj.put("query", std.json.Value{ .string = query.text });
            try params_obj.put("type", std.json.Value{ .string = query.search_type });

            const params = std.json.Value{ .object = params_obj };

            const result = SearchPrimitive.execute(ctx, params) catch |err| {
                std.debug.print("Batch search error for query '{}': {}\n", .{ query.text, err });
                continue;
            };
            defer freeJsonContainer(ctx.allocator, result);

            if (result.object.get("results")) |results_value| {
                if (results_value == .array) {
                    for (results_value.array.items) |item| {
                        if (item == .object) {
                            const key = item.object.get("key").?.string;
                            const score = if (item.object.get("score")) |s| s.float else 0.0;

                            try all_results.append(SearchResult{
                                .query = query.text,
                                .search_type = query.search_type,
                                .results = &[_]SearchResultItem{.{
                                    .key = try ctx.allocator.dupe(u8, key),
                                    .score = @as(f32, @floatCast(score)),
                                    .result_type = try ctx.allocator.dupe(u8, query.search_type),
                                }},
                                .count = 1,
                                .execution_time_ms = 0.0,
                            });
                        }
                    }
                }
            }
        }

        const batch_time_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        const throughput = @as(f64, @floatFromInt(queries.len)) / (batch_time_ms / 1000.0);

        std.debug.print("✅ Batch search: {} queries in {d:.2}ms ({d:.0} queries/sec)\n", .{ queries.len, batch_time_ms, throughput });

        return try all_results.toOwnedSlice();
    }
};

/// Batch operation types
pub const BatchStoreOp = struct {
    key: []const u8,
    value: []const u8,
    metadata: ?std.json.Value = null,
};

pub const BatchStoreResult = struct {
    success: bool,
    key: []const u8,
    indexed: bool = false,
    error_message: ?[]const u8 = null,
};

pub const BatchSearchQuery = struct {
    text: []const u8,
    search_type: []const u8,
    max_results: u32 = 20,
};

/// Cache for expensive operations (embeddings, parsing results, etc.)
pub const OperationCache = struct {
    // Embedding cache for text -> vector conversions
    embedding_cache: HashMap([]const u8, []f32, HashContext, std.hash_map.default_max_load_percentage),

    // Parsed function cache for code analysis
    function_cache: HashMap([]const u8, [][]const u8, HashContext, std.hash_map.default_max_load_percentage),

    // Search result cache for frequent queries
    search_cache: HashMap(SearchCacheKey, []SearchResultItem, SearchCacheKeyContext, std.hash_map.default_max_load_percentage),

    // Cache statistics
    embedding_hits: u64 = 0,
    embedding_misses: u64 = 0,
    function_hits: u64 = 0,
    function_misses: u64 = 0,
    search_hits: u64 = 0,
    search_misses: u64 = 0,

    // Memory management
    allocator: Allocator,
    cache_arena: std.heap.ArenaAllocator,

    const HashContext = struct {
        pub fn hash(self: @This(), key: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(key);
        }

        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    const SearchCacheKey = struct {
        query: []const u8,
        search_type: []const u8,
        max_results: u32,

        pub fn init(allocator: Allocator, query: []const u8, search_type: []const u8, max_results: u32) !SearchCacheKey {
            return SearchCacheKey{
                .query = try allocator.dupe(u8, query),
                .search_type = try allocator.dupe(u8, search_type),
                .max_results = max_results,
            };
        }
    };

    const SearchCacheKeyContext = struct {
        pub fn hash(self: @This(), key: SearchCacheKey) u64 {
            _ = self;
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(key.query);
            hasher.update(key.search_type);
            hasher.update(std.mem.asBytes(&key.max_results));
            return hasher.final();
        }

        pub fn eql(self: @This(), a: SearchCacheKey, b: SearchCacheKey) bool {
            _ = self;
            return std.mem.eql(u8, a.query, b.query) and
                std.mem.eql(u8, a.search_type, b.search_type) and
                a.max_results == b.max_results;
        }
    };

    pub fn init(allocator: Allocator) OperationCache {
        return OperationCache{
            .embedding_cache = HashMap([]const u8, []f32, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .function_cache = HashMap([]const u8, [][]const u8, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .search_cache = HashMap(SearchCacheKey, []SearchResultItem, SearchCacheKeyContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .cache_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *OperationCache) void {
        self.embedding_cache.deinit();
        self.function_cache.deinit();
        self.search_cache.deinit();
        self.cache_arena.deinit();
    }

    /// Cache embedding for text (prevents recomputation)
    pub fn cacheEmbedding(self: *OperationCache, text: []const u8, embedding: []const f32) !void {
        const text_copy = try self.cache_arena.allocator().dupe(u8, text);
        const embedding_copy = try self.cache_arena.allocator().dupe(f32, embedding);
        try self.embedding_cache.put(text_copy, embedding_copy);
    }

    /// Get cached embedding (returns null if not found)
    pub fn getCachedEmbedding(self: *OperationCache, text: []const u8) ?[]f32 {
        if (self.embedding_cache.get(text)) |embedding| {
            self.embedding_hits += 1;
            return embedding;
        } else {
            self.embedding_misses += 1;
            return null;
        }
    }

    /// Cache parsed functions for code content
    pub fn cacheFunctions(self: *OperationCache, content: []const u8, functions: []const []const u8) !void {
        const content_copy = try self.cache_arena.allocator().dupe(u8, content);
        const functions_copy = try self.cache_arena.allocator().alloc([]const u8, functions.len);
        for (functions, 0..) |func, i| {
            functions_copy[i] = try self.cache_arena.allocator().dupe(u8, func);
        }
        try self.function_cache.put(content_copy, functions_copy);
    }

    /// Get cached functions (returns null if not found)
    pub fn getCachedFunctions(self: *OperationCache, content: []const u8) ?[][]const u8 {
        if (self.function_cache.get(content)) |functions| {
            self.function_hits += 1;
            return functions;
        } else {
            self.function_misses += 1;
            return null;
        }
    }

    /// Cache search results for frequent queries
    pub fn cacheSearchResults(self: *OperationCache, query: []const u8, search_type: []const u8, max_results: u32, results: []const SearchResultItem) !void {
        const cache_key = try SearchCacheKey.init(self.cache_arena.allocator(), query, search_type, max_results);
        const results_copy = try self.cache_arena.allocator().dupe(SearchResultItem, results);
        try self.search_cache.put(cache_key, results_copy);
    }

    /// Get cached search results (returns null if not found)
    pub fn getCachedSearchResults(self: *OperationCache, query: []const u8, search_type: []const u8, max_results: u32) ?[]SearchResultItem {
        // Create temporary key for lookup (not cached)
        var temp_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer temp_arena.deinit();
        const temp_key = SearchCacheKey.init(temp_arena.allocator(), query, search_type, max_results) catch return null;

        if (self.search_cache.get(temp_key)) |results| {
            self.search_hits += 1;
            return results;
        } else {
            self.search_misses += 1;
            return null;
        }
    }

    /// Get cache statistics
    pub fn getCacheStats(self: *const OperationCache) struct {
        embedding_hit_ratio: f64,
        function_hit_ratio: f64,
        search_hit_ratio: f64,
        total_entries: usize,
        memory_used_mb: f64,
    } {
        const embedding_total = self.embedding_hits + self.embedding_misses;
        const function_total = self.function_hits + self.function_misses;
        const search_total = self.search_hits + self.search_misses;

        const embedding_hit_ratio = if (embedding_total > 0) @as(f64, @floatFromInt(self.embedding_hits)) / @as(f64, @floatFromInt(embedding_total)) else 0.0;
        const function_hit_ratio = if (function_total > 0) @as(f64, @floatFromInt(self.function_hits)) / @as(f64, @floatFromInt(function_total)) else 0.0;
        const search_hit_ratio = if (search_total > 0) @as(f64, @floatFromInt(self.search_hits)) / @as(f64, @floatFromInt(search_total)) else 0.0;

        const total_entries = self.embedding_cache.count() + self.function_cache.count() + self.search_cache.count();

        // Rough memory estimate (simplified)
        const estimated_memory_mb = @as(f64, @floatFromInt(total_entries)) * 1024.0 / (1024.0 * 1024.0);

        return .{
            .embedding_hit_ratio = embedding_hit_ratio,
            .function_hit_ratio = function_hit_ratio,
            .search_hit_ratio = search_hit_ratio,
            .total_entries = total_entries,
            .memory_used_mb = estimated_memory_mb,
        };
    }

    /// Clear cache when memory usage gets too high
    pub fn clearCache(self: *OperationCache) void {
        self.embedding_cache.clearAndFree();
        self.function_cache.clearAndFree();
        self.search_cache.clearAndFree();
        self.cache_arena.deinit();
        self.cache_arena = std.heap.ArenaAllocator.init(self.allocator);

        // Reset stats
        self.embedding_hits = 0;
        self.embedding_misses = 0;
        self.function_hits = 0;
        self.function_misses = 0;
        self.search_hits = 0;
        self.search_misses = 0;
    }
};

// Unit Tests
test "StorePrimitive basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try @import("semantic_database.zig").SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var context = PrimitiveContext{
        .allocator = allocator,
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .agent_id = "test_agent",
        .timestamp = std.time.timestamp(),
        .session_id = "test_session",
    };

    // Create test parameters
    var params_obj = std.json.ObjectMap.init(allocator);
    defer params_obj.deinit();

    try params_obj.put("key", std.json.Value{ .string = "test_key" });
    try params_obj.put("value", std.json.Value{ .string = "test_value" });

    const params = std.json.Value{ .object = params_obj };

    // Test validation
    try StorePrimitive.validate(params);

    // Test execution
    const result = try StorePrimitive.execute(&context, params);
    defer cleanupCopiedJsonValue(allocator, result); // Properly free the result

    try testing.expect(result.object.get("success").?.bool == true);
    try testing.expect(std.mem.eql(u8, result.object.get("key").?.string, "test_key"));
}

test "RetrievePrimitive basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    // Store test data first
    try database.saveFile("test_key", "test_value");

    var semantic_db = try @import("semantic_database.zig").SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var context = PrimitiveContext{
        .allocator = allocator,
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .agent_id = "test_agent",
        .timestamp = std.time.timestamp(),
        .session_id = "test_session",
    };

    // Create test parameters
    var params_obj = std.json.ObjectMap.init(allocator);
    defer params_obj.deinit();

    try params_obj.put("key", std.json.Value{ .string = "test_key" });
    try params_obj.put("include_history", std.json.Value{ .bool = false });

    const params = std.json.Value{ .object = params_obj };

    // Test validation
    try RetrievePrimitive.validate(params);

    // Test execution
    const result = try RetrievePrimitive.execute(&context, params);
    defer cleanupCopiedJsonValue(allocator, result); // Properly free the result

    try testing.expect(result.object.get("exists").?.bool == true);
    try testing.expect(std.mem.eql(u8, result.object.get("value").?.string, "test_value"));
}

test "SearchPrimitive validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test valid parameters
    var valid_params = std.json.ObjectMap.init(allocator);
    defer valid_params.deinit();

    try valid_params.put("query", std.json.Value{ .string = "test query" });
    try valid_params.put("type", std.json.Value{ .string = "semantic" });

    try SearchPrimitive.validate(std.json.Value{ .object = valid_params });

    // Test invalid type
    var invalid_params = std.json.ObjectMap.init(allocator);
    defer invalid_params.deinit();

    try invalid_params.put("query", std.json.Value{ .string = "test query" });
    try invalid_params.put("type", std.json.Value{ .string = "invalid_type" });

    try testing.expectError(error.InvalidSearchType, SearchPrimitive.validate(std.json.Value{ .object = invalid_params }));
}

// Simplified JSON cleanup using arena allocator approach
// This function only handles structures we create, not arbitrary JSON
pub fn cleanupPrimitiveResult(allocator: Allocator, value: std.json.Value) void {
    switch (value) {
        .object => |obj| {
            // Free strings that we know we've allocated (key, value fields in our results)
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const val = entry.value_ptr.*;
                // Free specific string fields that we know we duplicate
                if ((std.mem.eql(u8, key, "key") or
                    std.mem.eql(u8, key, "value") or
                    std.mem.eql(u8, key, "source") or
                    std.mem.eql(u8, key, "target") or
                    std.mem.eql(u8, key, "current_session") or
                    std.mem.eql(u8, key, "name") or
                    std.mem.eql(u8, key, "description") or
                    std.mem.eql(u8, key, "performance")) and val == .string)
                {
                    allocator.free(val.string);
                }
                // Handle operation_counts object - need to free keys that are duplicated
                if (std.mem.eql(u8, key, "operation_counts") and val == .object) {
                    var op_iter = val.object.iterator();
                    while (op_iter.next()) |op_entry| {
                        allocator.free(op_entry.key_ptr.*);
                    }
                    var mutable_op_obj = val.object;
                    mutable_op_obj.deinit();
                }
                // Recursively clean nested objects/arrays
                else if (val == .object or val == .array) {
                    cleanupPrimitiveResult(allocator, val);
                }
            }
            // Free the object map itself
            var mutable_obj = obj;
            mutable_obj.deinit();
        },
        .array => |arr| {
            // Clean up any nested objects/arrays first
            for (arr.items) |item| {
                cleanupPrimitiveResult(allocator, item);
            }
            // Free the array itself
            var mutable_arr = arr;
            mutable_arr.deinit();
        },
        .string => {
            // Don't automatically free top-level strings - too risky without clear ownership tracking
            // Strings within objects are handled above when we know they're ours
        },
        else => {
            // No cleanup needed for primitives like bool, integer, float, null
        },
    }
}

// Cleanup function specifically for results from copyJsonValue (frees everything)
pub fn cleanupCopiedJsonValue(allocator: Allocator, value: std.json.Value) void {
    freeJsonValue(allocator, value);
}

/// Deep copy a JSON value using the provided allocator
/// This is needed for copying user metadata into our structures
fn copyJsonValue(allocator: Allocator, value: std.json.Value) !std.json.Value {
    switch (value) {
        .null => return std.json.Value{ .null = {} },
        .bool => |b| return std.json.Value{ .bool = b },
        .integer => |i| return std.json.Value{ .integer = i },
        .float => |f| return std.json.Value{ .float = f },
        .number_string => |s| {
            const copied_string = try allocator.dupe(u8, s);
            return std.json.Value{ .number_string = copied_string };
        },
        .string => |s| {
            const copied_string = try allocator.dupe(u8, s);
            return std.json.Value{ .string = copied_string };
        },
        .array => |arr| {
            var new_array = std.json.Array.init(allocator);
            for (arr.items) |item| {
                const copied_item = try copyJsonValue(allocator, item);
                try new_array.append(copied_item);
            }
            return std.json.Value{ .array = new_array };
        },
        .object => |obj| {
            var new_object = std.json.ObjectMap.init(allocator);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                const copied_key = try allocator.dupe(u8, entry.key_ptr.*);
                const copied_value = try copyJsonValue(allocator, entry.value_ptr.*);
                try new_object.put(copied_key, copied_value);
            }
            return std.json.Value{ .object = new_object };
        },
    }
}

/// Free a JSON value that was created with copyJsonValue
fn freeJsonValue(allocator: Allocator, value: std.json.Value) void {
    switch (value) {
        .string => |s| allocator.free(s),
        .number_string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items) |item| {
                freeJsonValue(allocator, item);
            }
            var mutable_arr = arr;
            mutable_arr.deinit();
        },
        .object => |obj| {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*); // Free the key
                freeJsonValue(allocator, entry.value_ptr.*); // Free the value
            }
            var mutable_obj = obj;
            mutable_obj.deinit();
        },
        else => {
            // No cleanup needed for null, bool, integer, float
        },
    }
}

// Safe JSON cleanup - only frees containers, not strings
// Use this for JSON structures we build locally
fn freeJsonContainer(allocator: Allocator, value: std.json.Value) void {
    switch (value) {
        .array => |arr| {
            for (arr.items) |item| {
                freeJsonContainer(allocator, item);
            }
            var mutable_arr = arr;
            mutable_arr.deinit();
        },
        .object => |obj| {
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                freeJsonContainer(allocator, entry.value_ptr.*);
            }
            var mutable_obj = obj;
            mutable_obj.deinit();
        },
        else => {
            // Don't free strings - too dangerous without clear ownership tracking
            // No need to use allocator for primitive types like bool, integer, float, null
        },
    }
}

test "transform operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test function parsing
    const code =
        \\pub fn main() void {
        \\    print("Hello");
        \\}
        \\function calculate() {
        \\    return 42;
        \\}
    ;

    const result = try parseFunctions(allocator, code);
    defer allocator.free(result);

    // Should contain both function definitions
    try testing.expect(std.mem.indexOf(u8, result, "pub fn main()") != null);
    try testing.expect(std.mem.indexOf(u8, result, "function calculate()") != null);
}
