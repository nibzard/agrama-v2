//! Enhanced Database Integration for Agrama MCP Server
//! Combines all advanced database capabilities for comprehensive AI agent support

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

const Database = @import("database.zig").Database;
const SemanticDatabase = @import("semantic_database.zig").SemanticDatabase;
const FrontierReductionEngine = @import("fre.zig").FrontierReductionEngine;
const crdt_manager_mod = @import("crdt_manager.zig");
const CRDTManager = crdt_manager_mod.CRDTManager;
const CRDTStats = crdt_manager_mod.CRDTStats;
const Agent = crdt_manager_mod.AgentCRDTSession;
const QueuedOperation = crdt_manager_mod.QueuedOperation;
const ConflictEvent = @import("crdt.zig").ConflictEvent;
const TripleHybridSearchEngine = @import("triple_hybrid_search.zig").TripleHybridSearchEngine;

const hnsw = @import("hnsw.zig");
const bm25 = @import("bm25.zig");

/// Configuration for enhanced database initialization
pub const EnhancedDatabaseConfig = struct {
    // HNSW Configuration
    hnsw_vector_dimensions: u32 = 768,
    hnsw_max_connections: u32 = 16,
    hnsw_ef_construction: usize = 200,
    matryoshka_dims: []const u32 = &[_]u32{ 64, 256, 768 },

    // FRE Configuration
    fre_default_recursion_levels: u32 = 3,
    fre_max_frontier_size: usize = 1000,
    fre_pivot_threshold: f32 = 0.1,

    // CRDT Configuration
    crdt_enable_real_time_sync: bool = true,
    crdt_conflict_resolution: CRDTConflictStrategy = .last_writer_wins,
    crdt_broadcast_events: bool = true,

    // Triple Hybrid Search Configuration
    hybrid_bm25_weight: f32 = 0.4,
    hybrid_hnsw_weight: f32 = 0.4,
    hybrid_fre_weight: f32 = 0.2,

    pub const CRDTConflictStrategy = enum {
        last_writer_wins,
        semantic_merge,
        agent_priority,
        human_intervention,
    };
};

/// Enhanced database integrating all Agrama capabilities
pub const EnhancedDatabase = struct {
    allocator: Allocator,

    // Core database components
    temporal_db: Database,
    semantic_db: SemanticDatabase,
    fre: FrontierReductionEngine,
    crdt_manager: ?CRDTManager, // Optional for now
    hybrid_search: TripleHybridSearchEngine,

    // Configuration
    config: EnhancedDatabaseConfig,

    // Embedding generation (placeholder for ML integration)
    embedding_cache: HashMap([]const u8, hnsw.MatryoshkaEmbedding, HashContext, std.hash_map.default_max_load_percentage),

    // Performance metrics
    metrics: DatabaseMetrics,

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

    pub fn init(allocator: Allocator, config: EnhancedDatabaseConfig) !EnhancedDatabase {
        // Initialize core temporal database
        const temporal_db = Database.init(allocator);

        // Initialize semantic database with HNSW
        const hnsw_config = SemanticDatabase.HNSWConfig{
            .vector_dimensions = config.hnsw_vector_dimensions,
            .max_connections = config.hnsw_max_connections,
            .ef_construction = config.hnsw_ef_construction,
            .matryoshka_dims = config.matryoshka_dims,
        };
        const semantic_db = try SemanticDatabase.init(allocator, hnsw_config);

        // Initialize FRE for graph operations
        var fre = FrontierReductionEngine.init(allocator);
        fre.default_recursion_levels = config.fre_default_recursion_levels;
        fre.max_frontier_size = config.fre_max_frontier_size;
        fre.pivot_threshold = config.fre_pivot_threshold;

        // For now, skip CRDT manager initialization to avoid complex dependencies
        // TODO: Properly integrate CRDT manager when websocket server is available

        // Initialize triple hybrid search engine
        const hybrid_search = TripleHybridSearchEngine.init(allocator);

        return EnhancedDatabase{
            .allocator = allocator,
            .temporal_db = temporal_db,
            .semantic_db = semantic_db,
            .fre = fre,
            .crdt_manager = null, // Will be initialized later when needed
            .hybrid_search = hybrid_search,
            .config = config,
            .embedding_cache = HashMap([]const u8, hnsw.MatryoshkaEmbedding, HashContext, std.hash_map.default_max_load_percentage).init(allocator),
            .metrics = DatabaseMetrics{},
        };
    }

    pub fn deinit(self: *EnhancedDatabase) void {
        self.temporal_db.deinit();
        self.semantic_db.deinit();
        self.fre.deinit();
        if (self.crdt_manager) |*manager| {
            manager.deinit();
        }
        self.hybrid_search.deinit();

        // Clean up embedding cache
        var cache_iterator = self.embedding_cache.iterator();
        while (cache_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mut_embedding = entry.value_ptr.*;
            mut_embedding.deinit(self.allocator);
        }
        self.embedding_cache.deinit();
    }

    /// Save file with full database integration
    pub fn saveFileEnhanced(self: *EnhancedDatabase, path: []const u8, content: []const u8, agent_id: []const u8) !void {
        const start_time = std.time.milliTimestamp();

        // 1. Save to temporal database
        try self.temporal_db.saveFile(path, content);

        // 2. Generate embedding for semantic indexing
        if (self.shouldGenerateEmbedding(content)) {
            const embedding = try self.generateEmbedding(content);
            try self.semantic_db.saveFileWithEmbedding(path, content, embedding);
        } else {
            try self.semantic_db.saveFile(path, content);
        }

        // 3. Update graph relationships via FRE
        try self.updateGraphRelationships(path, content, agent_id);

        // 4. Handle CRDT collaboration if enabled
        if (self.config.crdt_enable_real_time_sync) {
            try self.updateCRDTDocument(path, content, agent_id);
        }

        // 5. Update hybrid search indices
        try self.updateHybridSearchIndices(path, content);

        // Update metrics
        const end_time = std.time.milliTimestamp();
        self.metrics.total_saves += 1;
        self.metrics.average_save_time_ms = updateAverageTime(self.metrics.average_save_time_ms, @as(f64, @floatFromInt(end_time - start_time)), self.metrics.total_saves);
    }

    /// Get file with comprehensive context
    pub fn getFileEnhanced(self: *EnhancedDatabase, path: []const u8) !EnhancedFileResult {
        const start_time = std.time.milliTimestamp();

        // Get basic file content
        const content = try self.temporal_db.getFile(path);

        var result = EnhancedFileResult{
            .path = try self.allocator.dupe(u8, path),
            .content = try self.allocator.dupe(u8, content),
            .exists = true,
        };

        // Add semantic context if available
        if (self.embedding_cache.get(path)) |_| {
            result.embedding_available = true;
            result.semantic_similarity_threshold = 0.8;
        }

        // Add graph context
        result.graph_context = try self.getGraphContext(path);

        // Add collaborative context if enabled
        if (self.config.crdt_enable_real_time_sync) {
            result.collaborative_context = try self.getCRDTContext(path);
        }

        // Update metrics
        const end_time = std.time.milliTimestamp();
        self.metrics.total_reads += 1;
        self.metrics.average_read_time_ms = updateAverageTime(self.metrics.average_read_time_ms, @as(f64, @floatFromInt(end_time - start_time)), self.metrics.total_reads);

        return result;
    }

    /// Perform enhanced hybrid search
    pub fn searchEnhanced(self: *EnhancedDatabase, query: EnhancedSearchQuery) ![]EnhancedSearchResult {
        const start_time = std.time.milliTimestamp();

        // Create hybrid query from enhanced query
        var hybrid_query = @import("triple_hybrid_search.zig").HybridQuery{
            .text_query = query.text_query,
            .max_results = query.max_results,
            .max_graph_hops = query.max_graph_hops,
            .alpha = self.config.hybrid_bm25_weight,
            .beta = self.config.hybrid_hnsw_weight,
            .gamma = self.config.hybrid_fre_weight,
        };

        // Generate embedding if needed
        if (query.include_semantic_search and hybrid_query.embedding_query == null) {
            const embedding = try self.generateEmbedding(query.text_query);
            hybrid_query.embedding_query = embedding.fine().data;
        }

        // Set starting nodes for graph traversal
        if (query.context_files.len > 0) {
            var node_ids = try self.allocator.alloc(u32, query.context_files.len);
            defer self.allocator.free(node_ids);

            for (query.context_files, 0..) |file_path, i| {
                const full_node_id = self.getNodeIdForFile(file_path);
                node_ids[i] = @as(u32, @truncate(full_node_id)); // Truncate 128-bit to 32-bit for compatibility
            }
            hybrid_query.starting_nodes = node_ids;
        }

        // Perform hybrid search
        const hybrid_results = try self.hybrid_search.search(hybrid_query);
        defer {
            for (hybrid_results) |result| {
                result.deinit(self.allocator);
            }
            self.allocator.free(hybrid_results);
        }

        // Convert to enhanced results with additional context
        var enhanced_results = try self.allocator.alloc(EnhancedSearchResult, hybrid_results.len);
        for (hybrid_results, 0..) |hybrid_result, i| {
            enhanced_results[i] = EnhancedSearchResult{
                .file_path = try self.allocator.dupe(u8, hybrid_result.file_path),
                .combined_score = hybrid_result.combined_score,
                .bm25_score = hybrid_result.bm25_score,
                .semantic_score = hybrid_result.hnsw_score,
                .graph_score = hybrid_result.fre_score,
                .matching_terms = try self.allocator.dupe([]const u8, hybrid_result.matching_terms),
                .semantic_similarity = hybrid_result.semantic_similarity,
                .graph_distance = hybrid_result.graph_distance,
            };
        }

        // Update metrics
        const end_time = std.time.milliTimestamp();
        self.metrics.total_searches += 1;
        self.metrics.average_search_time_ms = updateAverageTime(self.metrics.average_search_time_ms, @as(f64, @floatFromInt(end_time - start_time)), self.metrics.total_searches);

        return enhanced_results;
    }

    /// Analyze dependencies using FRE
    pub fn analyzeDependencies(self: *EnhancedDatabase, file_path: []const u8, max_depth: u32) !DependencyAnalysisResult {
        const node_id = self.getNodeIdForFile(file_path);
        const dependency_graph = try self.fre.analyzeDependencies(node_id, .forward, max_depth);

        // Convert FRE result to MCP-friendly format
        var dependencies = try self.allocator.alloc([]const u8, dependency_graph.nodes.len);
        for (dependency_graph.nodes, 0..) |node_id_dep, i| {
            dependencies[i] = try self.allocator.dupe(u8, self.getFilePathForNodeId(node_id_dep));
        }

        return DependencyAnalysisResult{
            .root_file = try self.allocator.dupe(u8, file_path),
            .dependencies = dependencies,
            .max_depth_analyzed = max_depth,
            .total_dependencies_found = @as(u32, @intCast(dependencies.len)),
        };
    }

    /// Get comprehensive database statistics
    pub fn getStats(self: *EnhancedDatabase) DatabaseStats {
        const temporal_stats = self.temporal_db.current_files.count();
        const semantic_stats = self.semantic_db.getStats();
        const fre_stats = self.fre.getGraphStats();
        const crdt_stats = if (self.crdt_manager) |*manager| manager.getStats() else CRDTStats{ .active_agents = 0, .active_documents = 0, .total_operations = 0, .total_conflicts = 0, .global_conflicts = 0 };
        const hybrid_stats = self.hybrid_search.getStats();

        return DatabaseStats{
            .temporal_files = @as(u32, @intCast(temporal_stats)),
            .semantic_indexed_files = semantic_stats.indexed_files,
            .graph_nodes = fre_stats.nodes,
            .graph_edges = fre_stats.edges,
            .active_crdt_documents = crdt_stats.active_documents,
            .hybrid_search_avg_time_ms = hybrid_stats.total_time_ms,
            .cache_hit_rate = self.calculateCacheHitRate(),
            .metrics = self.metrics,
        };
    }

    // Private helper methods

    fn shouldGenerateEmbedding(self: *EnhancedDatabase, content: []const u8) bool {
        _ = self;
        // Generate embeddings for code files and substantial text content
        return content.len > 50 and (std.mem.indexOf(u8, content, "function") != null or
            std.mem.indexOf(u8, content, "class") != null or
            std.mem.indexOf(u8, content, "import") != null or
            std.mem.indexOf(u8, content, "const") != null);
    }

    fn generateEmbedding(self: *EnhancedDatabase, content: []const u8) !hnsw.MatryoshkaEmbedding {
        // Placeholder for ML-based embedding generation
        // In production, this would call an embedding model
        var embedding = try hnsw.MatryoshkaEmbedding.init(self.allocator, self.config.hnsw_vector_dimensions, self.config.matryoshka_dims);

        // Simple hash-based embedding for testing
        const hash = std.hash_map.hashString(content);
        for (0..self.config.hnsw_vector_dimensions) |i| {
            const value = (@as(f32, @floatFromInt((hash >> @as(u6, @intCast(i % 64))) & 0xFF)) - 127.5) / 127.5;
            embedding.full_vector.data[i] = value;
        }

        return embedding;
    }

    fn updateGraphRelationships(self: *EnhancedDatabase, path: []const u8, content: []const u8, agent_id: []const u8) !void {
        // Extract dependencies and create graph nodes/edges
        const node_id = self.getNodeIdForFile(path);

        // Create file node if it doesn't exist
        var file_node = @import("fre.zig").TemporalNode.init(self.allocator, node_id, .file, agent_id);
        try file_node.setProperty(self.allocator, "path", path);
        try file_node.setProperty(self.allocator, "size", try std.fmt.allocPrint(self.allocator, "{d}", .{content.len}));

        try self.fre.addNode(file_node);

        // Extract and create dependency edges (simplified)
        const dependencies = try self.extractDependencies(content);
        for (dependencies) |dep| {
            const dep_node_id = self.getNodeIdForFile(dep);
            const edge = @import("fre.zig").TemporalEdge.init(node_id, dep_node_id, .depends_on, 1.0, agent_id);
            try self.fre.addEdge(edge);
        }
    }

    fn updateCRDTDocument(self: *EnhancedDatabase, path: []const u8, content: []const u8, agent_id: []const u8) !void {
        // Create or update CRDT document for real-time collaboration
        if (self.crdt_manager) |*manager| {
            // Implement CRDT document update when properly integrated
            _ = manager;
            _ = path;
            _ = content;
            _ = agent_id;
        }
    }

    fn updateHybridSearchIndices(self: *EnhancedDatabase, path: []const u8, content: []const u8) !void {
        // Add document to hybrid search engine
        const doc_id = @as(bm25.DocumentID, @intCast(std.hash_map.hashString(path)));

        // Generate embedding if not cached
        if (!self.embedding_cache.contains(path)) {
            const embedding = try self.generateEmbedding(content);
            try self.embedding_cache.put(try self.allocator.dupe(u8, path), embedding);
        }

        const embedding = self.embedding_cache.get(path);
        const embedding_slice = if (embedding) |emb| emb.fine().data else null;

        try self.hybrid_search.addDocument(doc_id, path, content, embedding_slice);
    }

    pub fn getNodeIdForFile(self: *EnhancedDatabase, path: []const u8) u128 {
        _ = self;
        // Simple hash-based node ID generation
        return @as(u128, @intCast(std.hash_map.hashString(path)));
    }

    fn getFilePathForNodeId(self: *EnhancedDatabase, node_id: u128) []const u8 {
        _ = self;
        _ = node_id;
        // Placeholder - would maintain reverse lookup in production
        return "unknown";
    }

    fn extractDependencies(self: *EnhancedDatabase, content: []const u8) ![][]const u8 {
        _ = content;
        // Placeholder - would use AST parsing in production
        return try self.allocator.alloc([]const u8, 0);
    }

    fn getGraphContext(self: *EnhancedDatabase, path: []const u8) !GraphContextResult {
        const node_id = self.getNodeIdForFile(path);

        // Get immediate neighbors
        const paths = try self.fre.computeTemporalPaths(&[_]u128{node_id}, .bidirectional, 1, @import("fre.zig").TimeRange.current());
        defer paths.deinit(self.allocator);

        return GraphContextResult{
            .immediate_dependencies = @as(u32, @intCast(paths.reachable_nodes.len)),
            .graph_centrality = self.calculateCentrality(node_id),
        };
    }

    fn getCRDTContext(self: *EnhancedDatabase, path: []const u8) !CRDTContextResult {
        if (self.crdt_manager) |*manager| {
            _ = manager;
            _ = path;
            // TODO: Implement when CRDT manager is properly integrated
            return CRDTContextResult{};
        } else {
            return CRDTContextResult{};
        }
    }

    fn calculateCentrality(self: *EnhancedDatabase, node_id: u128) f32 {
        _ = self;
        _ = node_id;
        // Placeholder for graph centrality calculation
        return 0.5;
    }

    fn calculateCacheHitRate(self: *EnhancedDatabase) f32 {
        if (self.metrics.total_reads == 0) return 0.0;
        return @as(f32, @floatFromInt(self.metrics.cache_hits)) / @as(f32, @floatFromInt(self.metrics.total_reads));
    }

    fn updateAverageTime(current_avg: f64, new_time: f64, count: u64) f64 {
        if (count == 1) return new_time;
        const weight = 1.0 / @as(f64, @floatFromInt(count));
        return (1.0 - weight) * current_avg + weight * new_time;
    }
};

/// Enhanced file result with comprehensive context
pub const EnhancedFileResult = struct {
    path: []const u8,
    content: []const u8,
    exists: bool,

    // Semantic context
    embedding_available: bool = false,
    semantic_similarity_threshold: f32 = 0.0,

    // Graph context
    graph_context: GraphContextResult = .{},

    // Collaborative context
    collaborative_context: ?CRDTContextResult = null,

    pub fn deinit(self: EnhancedFileResult, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.content);
    }
};

/// Enhanced search query with comprehensive options
pub const EnhancedSearchQuery = struct {
    text_query: []const u8,
    context_files: []const []const u8 = &[_][]const u8{},
    max_results: u32 = 20,
    max_graph_hops: u32 = 3,
    include_semantic_search: bool = true,
    include_dependency_analysis: bool = true,
    include_crdt_context: bool = false,
};

/// Enhanced search result with multi-modal scoring
pub const EnhancedSearchResult = struct {
    file_path: []const u8,
    combined_score: f32,

    // Component scores
    bm25_score: f32 = 0.0,
    semantic_score: f32 = 0.0,
    graph_score: f32 = 0.0,

    // Additional metadata
    matching_terms: [][]const u8 = &[_][]const u8{},
    semantic_similarity: f32 = 0.0,
    graph_distance: u32 = std.math.maxInt(u32),

    pub fn deinit(self: EnhancedSearchResult, allocator: Allocator) void {
        allocator.free(self.file_path);
        for (self.matching_terms) |term| {
            allocator.free(term);
        }
        if (self.matching_terms.len > 0) {
            allocator.free(self.matching_terms);
        }
    }
};

/// Dependency analysis result
pub const DependencyAnalysisResult = struct {
    root_file: []const u8,
    dependencies: [][]const u8,
    max_depth_analyzed: u32,
    total_dependencies_found: u32,

    pub fn deinit(self: DependencyAnalysisResult, allocator: Allocator) void {
        allocator.free(self.root_file);
        for (self.dependencies) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.dependencies);
    }
};

/// Graph context information
pub const GraphContextResult = struct {
    immediate_dependencies: u32 = 0,
    graph_centrality: f32 = 0.0,
};

/// CRDT collaborative context
pub const CRDTContextResult = struct {
    active_collaborators: u32 = 0,
    pending_operations: u32 = 0,
    last_sync_timestamp: i64 = 0,
};

/// Database performance metrics
pub const DatabaseMetrics = struct {
    total_reads: u64 = 0,
    total_writes: u64 = 0,
    total_saves: u64 = 0,
    total_searches: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
    average_read_time_ms: f64 = 0.0,
    average_write_time_ms: f64 = 0.0,
    average_save_time_ms: f64 = 0.0,
    average_search_time_ms: f64 = 0.0,
};

/// Comprehensive database statistics
pub const DatabaseStats = struct {
    // Component statistics
    temporal_files: u32,
    semantic_indexed_files: u32,
    graph_nodes: u32,
    graph_edges: u32,
    active_crdt_documents: u32,

    // Performance statistics
    hybrid_search_avg_time_ms: f64,
    cache_hit_rate: f32,

    // Detailed metrics
    metrics: DatabaseMetrics,
};
