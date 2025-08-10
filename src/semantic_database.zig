const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const hnsw = @import("hnsw.zig");
const Database = @import("database.zig").Database;
const Change = @import("database.zig").Change;

/// Enhanced database with semantic search capabilities via HNSW indexing
/// Extends the basic temporal database with vector search for code semantics
pub const SemanticDatabase = struct {
    allocator: Allocator,

    // Core temporal database for file operations
    temporal_db: Database,

    // HNSW indices for different code granularities
    function_index: ?hnsw.HNSWIndex, // Function-level semantic index
    file_index: ?hnsw.HNSWIndex, // File-level semantic index

    // Mapping from file paths to embeddings
    file_embeddings: HashMap([]const u8, hnsw.MatryoshkaEmbedding, HashContext, std.hash_map.default_max_load_percentage),

    // Node ID to file path mapping for reverse lookup
    node_to_path: HashMap(hnsw.NodeID, []const u8, std.hash_map.AutoContext(hnsw.NodeID), std.hash_map.default_max_load_percentage),

    // Node ID generation
    next_node_id: hnsw.NodeID,

    // HNSW configuration
    hnsw_config: HNSWConfig,

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

    const HNSWConfig = struct {
        vector_dimensions: u32 = 768, // Standard embedding dimension
        max_connections: u32 = 16, // M parameter
        ef_construction: usize = 200, // Construction parameter
        seed: u64 = 12345, // Random seed
        matryoshka_dims: []const u32 = &[_]u32{ 64, 256, 768 }, // Available precision levels
    };

    /// Initialize semantic database with HNSW indices
    pub fn init(allocator: Allocator, config: HNSWConfig) !SemanticDatabase {
        const temporal_db = Database.init(allocator);

        // Initialize HNSW indices
        const function_index = try hnsw.HNSWIndex.init(allocator, config.vector_dimensions, config.max_connections, config.ef_construction, config.seed);

        const file_index = try hnsw.HNSWIndex.init(allocator, config.vector_dimensions, config.max_connections, config.ef_construction, config.seed + 1 // Different seed for file index
        );

        return SemanticDatabase{
            .allocator = allocator,
            .temporal_db = temporal_db,
            .function_index = function_index,
            .file_index = file_index,
            .file_embeddings = HashMap([]const u8, hnsw.MatryoshkaEmbedding, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .node_to_path = HashMap(hnsw.NodeID, []const u8, std.hash_map.AutoContext(hnsw.NodeID), std.hash_map.default_max_load_percentage).init(allocator),
            .next_node_id = 1,
            .hnsw_config = config,
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *SemanticDatabase) void {
        // Clean up temporal database
        self.temporal_db.deinit();

        // Clean up HNSW indices
        if (self.function_index) |*index| {
            index.deinit();
        }

        if (self.file_index) |*index| {
            index.deinit();
        }

        // Clean up embeddings
        var embedding_iterator = self.file_embeddings.iterator();
        while (embedding_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_embedding = entry.value_ptr.*;
            mut_embedding.deinit(self.allocator);
        }
        self.file_embeddings.deinit();

        // Clean up node to path mapping
        var node_iterator = self.node_to_path.iterator();
        while (node_iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.node_to_path.deinit();
    }

    /// Save file with optional semantic embedding for enhanced search
    pub fn saveFileWithEmbedding(self: *SemanticDatabase, path: []const u8, content: []const u8, embedding: ?hnsw.MatryoshkaEmbedding) !void {
        // Save to temporal database first
        try self.temporal_db.saveFile(path, content);

        // Add semantic indexing if embedding provided
        if (embedding) |emb| {
            const node_id = self.next_node_id;
            self.next_node_id += 1;

            // Index the file-level embedding
            if (self.file_index) |*index| {
                const file_vector = emb.fine(); // Use full precision for files
                try index.insert(node_id, file_vector);
            }

            // Store the embedding for later retrieval
            const owned_path = try self.allocator.dupe(u8, path);

            // Remove old embedding if exists
            if (self.file_embeddings.fetchRemove(path)) |kv| {
                self.allocator.free(kv.key);
                var mut_embedding = kv.value;
                mut_embedding.deinit(self.allocator);
            }

            // Create a deep copy of the embedding to own its memory
            const owned_embedding = try emb.clone(self.allocator);
            try self.file_embeddings.put(owned_path, owned_embedding);

            // Store the node ID to path mapping for reverse lookup
            const owned_path_copy = try self.allocator.dupe(u8, path);
            try self.node_to_path.put(node_id, owned_path_copy);
        }
    }

    /// Save file (delegates to temporal database)
    pub fn saveFile(self: *SemanticDatabase, path: []const u8, content: []const u8) !void {
        return self.temporal_db.saveFile(path, content);
    }

    /// Get file content (delegates to temporal database)
    pub fn getFile(self: *SemanticDatabase, path: []const u8) ![]const u8 {
        return self.temporal_db.getFile(path);
    }

    /// Get file history (delegates to temporal database)
    pub fn getHistory(self: *SemanticDatabase, path: []const u8, limit: usize) ![]Change {
        return self.temporal_db.getHistory(path, limit);
    }

    /// Semantic search for files similar to query embedding
    pub fn semanticSearch(self: *SemanticDatabase, query_embedding: hnsw.MatryoshkaEmbedding, params: hnsw.HNSWSearchParams) ![]SemanticSearchResult {
        if (self.file_index == null) {
            return &[_]SemanticSearchResult{};
        }

        // Perform progressive precision search using matryoshka embeddings
        const fine_vector = query_embedding.fine();

        // Use full precision for file-level search (matching what we used for indexing)
        const raw_results = try self.file_index.?.search(fine_vector, params);
        defer self.allocator.free(raw_results);

        // Refine with full precision if needed
        var refined_results = ArrayList(SemanticSearchResult).init(self.allocator);
        defer refined_results.deinit();

        for (raw_results) |result| {
            // Find the corresponding file path
            if (self.findPathForNodeId(result.node_id)) |file_path| {
                // Re-rank with full precision if available
                var final_similarity = result.similarity;

                if (self.file_embeddings.get(file_path)) |file_embedding| {
                    final_similarity = fine_vector.cosineSimilarity(&file_embedding.fine());
                }

                const semantic_result = SemanticSearchResult{
                    .file_path = file_path,
                    .node_id = result.node_id,
                    .similarity = final_similarity,
                    .distance = result.distance,
                };

                try refined_results.append(semantic_result);
            }
        }

        // Sort by refined similarity and return top k
        std.sort.pdq(SemanticSearchResult, refined_results.items, {}, compareSemanticResults);

        const final_count = @min(params.k, refined_results.items.len);
        const results = try self.allocator.alloc(SemanticSearchResult, final_count);

        for (0..final_count) |i| {
            results[i] = refined_results.items[i];
        }

        return results;
    }

    /// Hybrid search combining semantic similarity with graph relationships
    pub fn hybridSearch(self: *SemanticDatabase, query: HybridQuery) ![]SemanticSearchResult {
        // Step 1: Semantic pre-filtering with HNSW
        const semantic_candidates = try self.semanticSearch(query.embedding, query.search_params);
        defer self.allocator.free(semantic_candidates);

        // Step 2: Graph-based filtering (placeholder for FRE integration)
        // For now, just return semantic results with additional metadata
        var hybrid_results = ArrayList(SemanticSearchResult).init(self.allocator);
        defer hybrid_results.deinit();

        for (semantic_candidates) |candidate| {
            // Add graph context (would be enhanced with FRE)
            var enhanced_candidate = candidate;
            enhanced_candidate.graph_distance = self.calculateGraphDistance(candidate.file_path, query.context_files);

            // Filter by graph constraints
            if (enhanced_candidate.graph_distance <= query.max_graph_distance) {
                try hybrid_results.append(enhanced_candidate);
            }
        }

        const results = try self.allocator.alloc(SemanticSearchResult, hybrid_results.items.len);
        @memcpy(results, hybrid_results.items);

        return results;
    }

    /// Find file path for a given node ID (reverse lookup)
    fn findPathForNodeId(self: *SemanticDatabase, node_id: hnsw.NodeID) ?[]const u8 {
        return self.node_to_path.get(node_id);
    }

    /// Calculate graph distance between files (placeholder for FRE integration)
    fn calculateGraphDistance(self: *SemanticDatabase, file_path: []const u8, context_files: []const []const u8) u32 {
        _ = self;
        _ = file_path;
        _ = context_files;
        // Placeholder - would use FRE for actual graph traversal
        return 1;
    }

    /// Get statistics about the semantic database
    pub fn getStats(self: *const SemanticDatabase) SemanticDatabaseStats {
        const temporal_files = self.temporal_db.current_files.count();

        var function_stats = IndexStats{
            .node_count = 0,
            .layer_count = 0,
            .entry_point = null,
            .avg_connections = 0.0,
        };

        if (self.function_index) |*index| {
            const stats = index.getStats();
            function_stats.node_count = stats.node_count;
            function_stats.layer_count = stats.layer_count;
            function_stats.entry_point = stats.entry_point;
            function_stats.avg_connections = stats.avg_connections;
        }

        var file_stats = IndexStats{
            .node_count = 0,
            .layer_count = 0,
            .entry_point = null,
            .avg_connections = 0.0,
        };

        if (self.file_index) |*index| {
            const stats = index.getStats();
            file_stats.node_count = stats.node_count;
            file_stats.layer_count = stats.layer_count;
            file_stats.entry_point = stats.entry_point;
            file_stats.avg_connections = stats.avg_connections;
        }

        return SemanticDatabaseStats{
            .total_files = temporal_files,
            .indexed_files = self.file_embeddings.count(),
            .function_index_stats = function_stats,
            .file_index_stats = file_stats,
            .next_node_id = self.next_node_id,
        };
    }
};

/// Result from semantic search with file context
pub const SemanticSearchResult = struct {
    file_path: []const u8,
    node_id: hnsw.NodeID,
    similarity: f32,
    distance: f32,
    graph_distance: u32 = 0, // Distance in code dependency graph
};

/// Hybrid query combining semantic and graph constraints
pub const HybridQuery = struct {
    embedding: hnsw.MatryoshkaEmbedding,
    search_params: hnsw.HNSWSearchParams,
    context_files: []const []const u8 = &[_][]const u8{}, // Files to consider for graph context
    max_graph_distance: u32 = 3, // Maximum hops in dependency graph
};

/// Index statistics type for consistency
pub const IndexStats = struct {
    node_count: usize,
    layer_count: usize,
    entry_point: ?hnsw.NodeID,
    avg_connections: f32,
};

/// Statistics for semantic database
pub const SemanticDatabaseStats = struct {
    total_files: u32,
    indexed_files: u32,
    function_index_stats: IndexStats,
    file_index_stats: IndexStats,
    next_node_id: hnsw.NodeID,
};

/// Comparison function for semantic search results
fn compareSemanticResults(context: void, a: SemanticSearchResult, b: SemanticSearchResult) bool {
    _ = context;
    return a.similarity > b.similarity;
}

// Unit Tests
test "SemanticDatabase initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 128,
        .max_connections = 8,
        .ef_construction = 100,
    };

    var semantic_db = try SemanticDatabase.init(allocator, config);
    defer semantic_db.deinit();

    const stats = semantic_db.getStats();
    try testing.expect(stats.total_files == 0);
    try testing.expect(stats.indexed_files == 0);
    try testing.expect(stats.next_node_id == 1);
}

test "SemanticDatabase file operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 128,
        .max_connections = 8,
        .ef_construction = 100,
    };

    var semantic_db = try SemanticDatabase.init(allocator, config);
    defer semantic_db.deinit();

    // Test basic file operations
    const test_path = "src/file.py";
    const test_content = "def hello_world():\n    print('Hello, World!')";

    try semantic_db.saveFile(test_path, test_content);

    const retrieved = try semantic_db.getFile(test_path);
    try testing.expectEqualSlices(u8, test_content, retrieved);

    const stats = semantic_db.getStats();
    try testing.expect(stats.total_files == 1);
}

test "SemanticDatabase embedding integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 64,
        .max_connections = 8,
        .ef_construction = 50,
        .matryoshka_dims = &[_]u32{ 32, 64 },
    };

    var semantic_db = try SemanticDatabase.init(allocator, config);
    defer semantic_db.deinit();

    // Create test embedding
    var embedding = try hnsw.MatryoshkaEmbedding.init(allocator, 64, config.matryoshka_dims);
    defer embedding.deinit(allocator);

    // Fill with test data
    for (0..64) |i| {
        embedding.full_vector.data[i] = @as(f32, @floatFromInt(i)) * 0.1;
    }

    // Save file with embedding
    const test_path = "src/embedded_file.py";
    const test_content = "def calculate(x):\n    return x * 2";

    try semantic_db.saveFileWithEmbedding(test_path, test_content, embedding);

    const stats = semantic_db.getStats();
    try testing.expect(stats.indexed_files == 1);
    try testing.expect(stats.file_index_stats.node_count == 1);
}

test "SemanticDatabase semantic search" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SemanticDatabase.HNSWConfig{
        .vector_dimensions = 32,
        .max_connections = 4,
        .ef_construction = 20,
        .matryoshka_dims = &[_]u32{ 16, 32 },
    };

    var semantic_db = try SemanticDatabase.init(allocator, config);
    defer semantic_db.deinit();

    // Add multiple files with embeddings
    const files = [_]struct { path: []const u8, content: []const u8, embedding_offset: f32 }{
        .{ .path = "math_utils.py", .content = "def add(a, b): return a + b", .embedding_offset = 1.0 },
        .{ .path = "string_utils.py", .content = "def upper(s): return s.upper()", .embedding_offset = 2.0 },
        .{ .path = "math_advanced.py", .content = "def multiply(a, b): return a * b", .embedding_offset = 1.1 },
    };

    for (files) |file| {
        var embedding = try hnsw.MatryoshkaEmbedding.init(allocator, 32, config.matryoshka_dims);
        defer embedding.deinit(allocator);

        // Create distinct embeddings
        for (0..32) |i| {
            embedding.full_vector.data[i] = file.embedding_offset + @as(f32, @floatFromInt(i)) * 0.01;
        }

        try semantic_db.saveFileWithEmbedding(file.path, file.content, embedding);
    }

    // Create query embedding similar to math files
    var query_embedding = try hnsw.MatryoshkaEmbedding.init(allocator, 32, config.matryoshka_dims);
    defer query_embedding.deinit(allocator);

    for (0..32) |i| {
        query_embedding.full_vector.data[i] = 1.05 + @as(f32, @floatFromInt(i)) * 0.01;
    }

    // Perform semantic search
    const search_params = hnsw.HNSWSearchParams{
        .k = 2,
        .ef = 10,
        .precision_target = 0.8,
    };

    const results = try semantic_db.semanticSearch(query_embedding, search_params);
    defer allocator.free(results);

    // Should find at least one result
    try testing.expect(results.len > 0);

    // Results should have reasonable similarity scores
    for (results) |result| {
        try testing.expect(result.similarity >= 0.0);
        try testing.expect(result.similarity <= 1.0);
    }
}
