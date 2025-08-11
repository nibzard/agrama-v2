//! Enhanced MCP Tools with Full Database Integration
//! Provides comprehensive MCP tools that expose all Agrama database capabilities

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const EnhancedDatabase = @import("enhanced_database.zig").EnhancedDatabase;
const EnhancedSearchQuery = @import("enhanced_database.zig").EnhancedSearchQuery;

/// Enhanced MCP tool definitions with comprehensive database access
pub const EnhancedMCPTools = struct {
    /// Enhanced read_code tool with semantic context and dependency analysis
    pub const ReadCodeEnhanced = struct {
        pub const name = "read_code_enhanced";
        pub const description = "Read code files with comprehensive context including semantic similarity, dependencies, and collaborative information";

        pub const InputSchema = struct {
            path: []const u8,
            include_history: ?bool = false,
            history_limit: ?u32 = 5,
            include_semantic_context: ?bool = true,
            include_dependencies: ?bool = true,
            include_collaborative_context: ?bool = false,
            dependency_depth: ?u32 = 2,
            semantic_similarity_threshold: ?f32 = 0.7,
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            _ = agent_id; // Will be used for access control in future

            // Get enhanced file result with all context
            const file_result = enhanced_db.getFileEnhanced(params.path) catch |err| switch (err) {
                error.FileNotFound => {
                    var result = std.json.ObjectMap.init(enhanced_db.allocator);
                    try result.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, params.path) });
                    try result.put("exists", std.json.Value{ .bool = false });
                    try result.put("error", std.json.Value{ .string = "File not found" });
                    return std.json.Value{ .object = result };
                },
                else => return err,
            };
            defer file_result.deinit(enhanced_db.allocator);

            var result = std.json.ObjectMap.init(enhanced_db.allocator);

            // Basic file information
            try result.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, file_result.path) });
            try result.put("content", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, file_result.content) });
            try result.put("exists", std.json.Value{ .bool = file_result.exists });

            // History if requested
            if (params.include_history orelse false) {
                const history = enhanced_db.temporal_db.getHistory(params.path, params.history_limit orelse 5) catch &[_]@import("database.zig").Change{};
                defer if (history.len > 0) enhanced_db.allocator.free(history);

                var history_array = std.json.Array.init(enhanced_db.allocator);
                for (history) |change| {
                    var change_obj = std.json.ObjectMap.init(enhanced_db.allocator);
                    try change_obj.put("timestamp", std.json.Value{ .integer = change.timestamp });
                    try change_obj.put("content", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, change.content) });
                    try history_array.append(std.json.Value{ .object = change_obj });
                }
                try result.put("history", std.json.Value{ .array = history_array });
            }

            // Semantic context if requested
            if (params.include_semantic_context orelse true) {
                var semantic_context = std.json.ObjectMap.init(enhanced_db.allocator);
                try semantic_context.put("embedding_available", std.json.Value{ .bool = file_result.embedding_available });
                try semantic_context.put("similarity_threshold", std.json.Value{ .float = file_result.semantic_similarity_threshold });

                // Find semantically similar files
                if (file_result.embedding_available) {
                    const search_query = EnhancedSearchQuery{
                        .text_query = file_result.content[0..@min(200, file_result.content.len)], // First 200 chars
                        .max_results = 5,
                        .include_semantic_search = true,
                        .include_dependency_analysis = false,
                    };

                    const similar_files = enhanced_db.searchEnhanced(search_query) catch &[_]@import("enhanced_database.zig").EnhancedSearchResult{};
                    defer {
                        for (similar_files) |similar_file| {
                            similar_file.deinit(enhanced_db.allocator);
                        }
                        if (similar_files.len > 0) enhanced_db.allocator.free(similar_files);
                    }

                    var similar_array = std.json.Array.init(enhanced_db.allocator);
                    for (similar_files) |similar| {
                        if (similar.semantic_score >= (params.semantic_similarity_threshold orelse 0.7)) {
                            var similar_obj = std.json.ObjectMap.init(enhanced_db.allocator);
                            try similar_obj.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, similar.file_path) });
                            try similar_obj.put("similarity", std.json.Value{ .float = similar.semantic_score });
                            try similar_array.append(std.json.Value{ .object = similar_obj });
                        }
                    }
                    try semantic_context.put("similar_files", std.json.Value{ .array = similar_array });
                }

                try result.put("semantic_context", std.json.Value{ .object = semantic_context });
            }

            // Dependency analysis if requested
            if (params.include_dependencies orelse true) {
                const dependency_result = enhanced_db.analyzeDependencies(params.path, params.dependency_depth orelse 2) catch {
                    var empty_deps = std.json.ObjectMap.init(enhanced_db.allocator);
                    try empty_deps.put("dependencies", std.json.Value{ .array = std.json.Array.init(enhanced_db.allocator) });
                    try empty_deps.put("error", std.json.Value{ .string = "Dependency analysis failed" });
                    return std.json.Value{ .object = empty_deps };
                };
                defer dependency_result.deinit(enhanced_db.allocator);

                var dependency_context = std.json.ObjectMap.init(enhanced_db.allocator);
                try dependency_context.put("total_dependencies", std.json.Value{ .integer = @as(i64, @intCast(dependency_result.total_dependencies_found)) });
                try dependency_context.put("max_depth_analyzed", std.json.Value{ .integer = @as(i64, @intCast(dependency_result.max_depth_analyzed)) });

                var deps_array = std.json.Array.init(enhanced_db.allocator);
                for (dependency_result.dependencies) |dep| {
                    try deps_array.append(std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, dep) });
                }
                try dependency_context.put("dependencies", std.json.Value{ .array = deps_array });

                // Add graph context
                try dependency_context.put("graph_centrality", std.json.Value{ .float = file_result.graph_context.graph_centrality });
                try dependency_context.put("immediate_dependencies", std.json.Value{ .integer = @as(i64, @intCast(file_result.graph_context.immediate_dependencies)) });

                try result.put("dependency_context", std.json.Value{ .object = dependency_context });
            }

            // Collaborative context if requested
            if (params.include_collaborative_context orelse false) {
                if (file_result.collaborative_context) |crdt_context| {
                    var collab_context = std.json.ObjectMap.init(enhanced_db.allocator);
                    try collab_context.put("active_collaborators", std.json.Value{ .integer = @as(i64, @intCast(crdt_context.active_collaborators)) });
                    try collab_context.put("pending_operations", std.json.Value{ .integer = @as(i64, @intCast(crdt_context.pending_operations)) });
                    try collab_context.put("last_sync", std.json.Value{ .integer = crdt_context.last_sync_timestamp });
                    try result.put("collaborative_context", std.json.Value{ .object = collab_context });
                }
            }

            return std.json.Value{ .object = result };
        }
    };

    /// Enhanced write_code tool with CRDT collaboration and semantic indexing
    pub const WriteCodeEnhanced = struct {
        pub const name = "write_code_enhanced";
        pub const description = "Write code files with automatic semantic indexing, dependency tracking, and collaborative conflict resolution";

        pub const InputSchema = struct {
            path: []const u8,
            content: []const u8,
            enable_crdt_sync: ?bool = true,
            enable_semantic_indexing: ?bool = true,
            enable_dependency_tracking: ?bool = true,
            conflict_resolution_strategy: ?[]const u8 = "last_writer_wins",
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            // Save file with enhanced capabilities
            enhanced_db.saveFileEnhanced(params.path, params.content, agent_id) catch |err| {
                var error_result = std.json.ObjectMap.init(enhanced_db.allocator);
                try error_result.put("success", std.json.Value{ .bool = false });
                try error_result.put("error", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, @errorName(err)) });
                return std.json.Value{ .object = error_result };
            };

            var result = std.json.ObjectMap.init(enhanced_db.allocator);
            try result.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, params.path) });
            try result.put("success", std.json.Value{ .bool = true });
            try result.put("timestamp", std.json.Value{ .integer = std.time.timestamp() });
            try result.put("agent_id", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, agent_id) });

            // Add indexing status
            var indexing_status = std.json.ObjectMap.init(enhanced_db.allocator);
            try indexing_status.put("semantic_indexed", std.json.Value{ .bool = params.enable_semantic_indexing orelse true });
            try indexing_status.put("dependencies_tracked", std.json.Value{ .bool = params.enable_dependency_tracking orelse true });
            try indexing_status.put("crdt_enabled", std.json.Value{ .bool = params.enable_crdt_sync orelse true });
            try result.put("indexing_status", std.json.Value{ .object = indexing_status });

            return std.json.Value{ .object = result };
        }
    };

    /// Enhanced semantic search tool
    pub const SemanticSearchTool = struct {
        pub const name = "semantic_search";
        pub const description = "Perform semantic search across codebase using hybrid BM25 + HNSW + FRE approach";

        pub const InputSchema = struct {
            query: []const u8,
            context_files: ?[][]const u8 = null,
            max_results: ?u32 = 20,
            include_semantic: ?bool = true,
            include_lexical: ?bool = true,
            include_graph: ?bool = true,
            semantic_weight: ?f32 = 0.4,
            lexical_weight: ?f32 = 0.4,
            graph_weight: ?f32 = 0.2,
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            _ = agent_id;

            const search_query = EnhancedSearchQuery{
                .text_query = params.query,
                .context_files = params.context_files orelse &[_][]const u8{},
                .max_results = params.max_results orelse 20,
                .include_semantic_search = params.include_semantic orelse true,
                .include_dependency_analysis = params.include_graph orelse true,
            };

            const search_results = enhanced_db.searchEnhanced(search_query) catch |err| {
                var error_result = std.json.ObjectMap.init(enhanced_db.allocator);
                try error_result.put("success", std.json.Value{ .bool = false });
                try error_result.put("error", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, @errorName(err)) });
                return std.json.Value{ .object = error_result };
            };
            defer {
                for (search_results) |search_result| {
                    search_result.deinit(enhanced_db.allocator);
                }
                enhanced_db.allocator.free(search_results);
            }

            var result = std.json.ObjectMap.init(enhanced_db.allocator);
            try result.put("query", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, params.query) });
            try result.put("total_results", std.json.Value{ .integer = @as(i64, @intCast(search_results.len)) });

            var results_array = std.json.Array.init(enhanced_db.allocator);
            for (search_results) |search_result| {
                var result_obj = std.json.ObjectMap.init(enhanced_db.allocator);
                try result_obj.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, search_result.file_path) });
                try result_obj.put("combined_score", std.json.Value{ .float = search_result.combined_score });
                try result_obj.put("bm25_score", std.json.Value{ .float = search_result.bm25_score });
                try result_obj.put("semantic_score", std.json.Value{ .float = search_result.semantic_score });
                try result_obj.put("graph_score", std.json.Value{ .float = search_result.graph_score });
                try result_obj.put("semantic_similarity", std.json.Value{ .float = search_result.semantic_similarity });

                if (search_result.graph_distance != std.math.maxInt(u32)) {
                    try result_obj.put("graph_distance", std.json.Value{ .integer = @as(i64, @intCast(search_result.graph_distance)) });
                }

                // Add matching terms
                if (search_result.matching_terms.len > 0) {
                    var terms_array = std.json.Array.init(enhanced_db.allocator);
                    for (search_result.matching_terms) |term| {
                        try terms_array.append(std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, term) });
                    }
                    try result_obj.put("matching_terms", std.json.Value{ .array = terms_array });
                }

                try results_array.append(std.json.Value{ .object = result_obj });
            }
            try result.put("results", std.json.Value{ .array = results_array });

            return std.json.Value{ .object = result };
        }
    };

    /// Dependency analysis tool
    pub const AnalyzeDependenciesTool = struct {
        pub const name = "analyze_dependencies";
        pub const description = "Analyze code dependencies using Frontier Reduction Engine for impact assessment";

        pub const InputSchema = struct {
            file_path: []const u8,
            max_depth: ?u32 = 3,
            direction: ?[]const u8 = "bidirectional", // forward, reverse, bidirectional
            include_impact_analysis: ?bool = true,
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            _ = agent_id;

            const dependency_result = enhanced_db.analyzeDependencies(params.file_path, params.max_depth orelse 3) catch |err| {
                var error_result = std.json.ObjectMap.init(enhanced_db.allocator);
                try error_result.put("success", std.json.Value{ .bool = false });
                try error_result.put("error", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, @errorName(err)) });
                return std.json.Value{ .object = error_result };
            };
            defer dependency_result.deinit(enhanced_db.allocator);

            var result = std.json.ObjectMap.init(enhanced_db.allocator);
            try result.put("root_file", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, dependency_result.root_file) });
            try result.put("total_dependencies", std.json.Value{ .integer = @as(i64, @intCast(dependency_result.total_dependencies_found)) });
            try result.put("max_depth_analyzed", std.json.Value{ .integer = @as(i64, @intCast(dependency_result.max_depth_analyzed)) });

            var deps_array = std.json.Array.init(enhanced_db.allocator);
            for (dependency_result.dependencies) |dep| {
                try deps_array.append(std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, dep) });
            }
            try result.put("dependencies", std.json.Value{ .array = deps_array });

            // Impact analysis if requested
            if (params.include_impact_analysis orelse true) {
                const node_id = enhanced_db.getNodeIdForFile(params.file_path);
                const impact = enhanced_db.fre.computeImpactRadius(&[_]u128{node_id}, params.max_depth orelse 3) catch {
                    var empty_impact = std.json.ObjectMap.init(enhanced_db.allocator);
                    try empty_impact.put("error", std.json.Value{ .string = "Impact analysis failed" });
                    try result.put("impact_analysis", std.json.Value{ .object = empty_impact });
                    return std.json.Value{ .object = result };
                };
                defer impact.deinit(enhanced_db.allocator);

                var impact_obj = std.json.ObjectMap.init(enhanced_db.allocator);
                try impact_obj.put("affected_entities", std.json.Value{ .integer = @as(i64, @intCast(impact.affected_entities.len)) });
                try impact_obj.put("estimated_complexity", std.json.Value{ .float = impact.estimated_complexity });
                try impact_obj.put("critical_paths", std.json.Value{ .integer = @as(i64, @intCast(impact.critical_paths.len)) });

                try result.put("impact_analysis", std.json.Value{ .object = impact_obj });
            }

            return std.json.Value{ .object = result };
        }
    };

    /// Database status and statistics tool
    pub const DatabaseStatsTool = struct {
        pub const name = "get_database_stats";
        pub const description = "Get comprehensive database statistics including performance metrics and component status";

        pub const InputSchema = struct {
            include_performance_metrics: ?bool = true,
            include_component_details: ?bool = true,
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            _ = agent_id;

            const stats = enhanced_db.getStats();

            var result = std.json.ObjectMap.init(enhanced_db.allocator);

            // Component statistics
            if (params.include_component_details orelse true) {
                var components = std.json.ObjectMap.init(enhanced_db.allocator);
                try components.put("temporal_files", std.json.Value{ .integer = @as(i64, @intCast(stats.temporal_files)) });
                try components.put("semantic_indexed_files", std.json.Value{ .integer = @as(i64, @intCast(stats.semantic_indexed_files)) });
                try components.put("graph_nodes", std.json.Value{ .integer = @as(i64, @intCast(stats.graph_nodes)) });
                try components.put("graph_edges", std.json.Value{ .integer = @as(i64, @intCast(stats.graph_edges)) });
                try components.put("active_crdt_documents", std.json.Value{ .integer = @as(i64, @intCast(stats.active_crdt_documents)) });
                try result.put("components", std.json.Value{ .object = components });
            }

            // Performance metrics
            if (params.include_performance_metrics orelse true) {
                var performance = std.json.ObjectMap.init(enhanced_db.allocator);
                try performance.put("cache_hit_rate", std.json.Value{ .float = stats.cache_hit_rate });
                try performance.put("hybrid_search_avg_time_ms", std.json.Value{ .float = stats.hybrid_search_avg_time_ms });
                try performance.put("total_operations", std.json.Value{ .integer = @as(i64, @intCast(stats.metrics.total_reads + stats.metrics.total_writes + stats.metrics.total_searches)) });
                try performance.put("avg_read_time_ms", std.json.Value{ .float = stats.metrics.average_read_time_ms });
                try performance.put("avg_write_time_ms", std.json.Value{ .float = stats.metrics.average_write_time_ms });
                try performance.put("avg_search_time_ms", std.json.Value{ .float = stats.metrics.average_search_time_ms });
                try result.put("performance", std.json.Value{ .object = performance });
            }

            return std.json.Value{ .object = result };
        }
    };

    /// Code Analysis tool for AST parsing and static analysis
    pub const CodeAnalysis = struct {
        pub const name = "code_analysis";
        pub const description = "Analyze code structure, extract functions, variables, dependencies, and provide static analysis insights";

        pub const InputSchema = struct {
            path: []const u8,
            analysis_type: ?[]const u8 = "comprehensive", // "functions", "variables", "dependencies", "structure", "comprehensive"
            include_metrics: ?bool = true,
            include_dependencies: ?bool = true,
            include_ast_structure: ?bool = false,
            language_hint: ?[]const u8 = null, // "javascript", "typescript", "python", "zig", etc.
        };

        pub fn execute(enhanced_db: *EnhancedDatabase, params: InputSchema, agent_id: []const u8) !std.json.Value {
            _ = agent_id;

            // Get file content first
            const file_result = enhanced_db.getFileEnhanced(params.path) catch |err| switch (err) {
                error.FileNotFound => {
                    var error_result = std.json.ObjectMap.init(enhanced_db.allocator);
                    try error_result.put("success", std.json.Value{ .bool = false });
                    try error_result.put("error", std.json.Value{ .string = "File not found" });
                    try error_result.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, params.path) });
                    return std.json.Value{ .object = error_result };
                },
                else => return err,
            };
            defer file_result.deinit(enhanced_db.allocator);

            var result = std.json.ObjectMap.init(enhanced_db.allocator);
            try result.put("path", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, params.path) });
            try result.put("success", std.json.Value{ .bool = true });

            // Detect language if not provided
            const language = params.language_hint orelse detectLanguage(params.path);
            try result.put("detected_language", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, language) });

            // Perform code analysis
            const analysis = analyzeCode(enhanced_db.allocator, file_result.content, language) catch |err| {
                var error_result = std.json.ObjectMap.init(enhanced_db.allocator);
                try error_result.put("success", std.json.Value{ .bool = false });
                try error_result.put("error", std.json.Value{ .string = try enhanced_db.allocator.dupe(u8, @errorName(err)) });
                return std.json.Value{ .object = error_result };
            };
            defer analysis.deinit(enhanced_db.allocator);

            // Add analysis results
            try result.put("functions", std.json.Value{ .array = analysis.functions });
            try result.put("variables", std.json.Value{ .array = analysis.variables });
            
            if (params.include_metrics orelse true) {
                var metrics = std.json.ObjectMap.init(enhanced_db.allocator);
                try metrics.put("lines_of_code", std.json.Value{ .integer = @as(i64, @intCast(analysis.metrics.lines_of_code)) });
                try metrics.put("function_count", std.json.Value{ .integer = @as(i64, @intCast(analysis.metrics.function_count)) });
                try metrics.put("variable_count", std.json.Value{ .integer = @as(i64, @intCast(analysis.metrics.variable_count)) });
                try metrics.put("complexity_score", std.json.Value{ .float = analysis.metrics.complexity_score });
                try result.put("metrics", std.json.Value{ .object = metrics });
            }

            if (params.include_dependencies orelse true) {
                try result.put("imports", std.json.Value{ .array = analysis.imports });
                try result.put("dependencies", std.json.Value{ .array = analysis.dependencies });
            }

            return std.json.Value{ .object = result };
        }
    };
};

// Helper functions for code analysis
const CodeAnalysisResult = struct {
    functions: std.json.Array,
    variables: std.json.Array,
    imports: std.json.Array,
    dependencies: std.json.Array,
    metrics: struct {
        lines_of_code: u32,
        function_count: u32,
        variable_count: u32,
        complexity_score: f32,
    },

    pub fn deinit(self: *const CodeAnalysisResult, allocator: Allocator) void {
        _ = allocator; // Not used but required for consistency
        self.functions.deinit();
        self.variables.deinit();
        self.imports.deinit();
        self.dependencies.deinit();
    }
};

fn detectLanguage(file_path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, file_path, ".js")) return "javascript";
    if (std.mem.endsWith(u8, file_path, ".ts")) return "typescript";
    if (std.mem.endsWith(u8, file_path, ".tsx")) return "typescript";
    if (std.mem.endsWith(u8, file_path, ".jsx")) return "javascript";
    if (std.mem.endsWith(u8, file_path, ".py")) return "python";
    if (std.mem.endsWith(u8, file_path, ".zig")) return "zig";
    if (std.mem.endsWith(u8, file_path, ".c")) return "c";
    if (std.mem.endsWith(u8, file_path, ".cpp")) return "cpp";
    if (std.mem.endsWith(u8, file_path, ".rs")) return "rust";
    if (std.mem.endsWith(u8, file_path, ".go")) return "go";
    if (std.mem.endsWith(u8, file_path, ".java")) return "java";
    return "unknown";
}

fn analyzeCode(allocator: Allocator, content: []const u8, language: []const u8) !CodeAnalysisResult {
    var functions = std.json.Array.init(allocator);
    var variables = std.json.Array.init(allocator);
    var imports = std.json.Array.init(allocator);
    const dependencies = std.json.Array.init(allocator);

    // Basic analysis - line-by-line parsing
    var lines_of_code: u32 = 0;
    var function_count: u32 = 0;
    var variable_count: u32 = 0;
    var complexity_score: f32 = 1.0;

    var line_iterator = std.mem.split(u8, content, "\n");
    while (line_iterator.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t\r");
        if (trimmed_line.len == 0 or trimmed_line[0] == '#' or 
            std.mem.startsWith(u8, trimmed_line, "//")) {
            continue; // Skip empty lines and comments
        }
        lines_of_code += 1;

        // Language-specific analysis
        if (std.mem.eql(u8, language, "javascript") or std.mem.eql(u8, language, "typescript")) {
            try analyzeJavaScript(allocator, trimmed_line, &functions, &variables, &imports, &function_count, &variable_count, &complexity_score);
        } else if (std.mem.eql(u8, language, "python")) {
            try analyzePython(allocator, trimmed_line, &functions, &variables, &imports, &function_count, &variable_count, &complexity_score);
        } else if (std.mem.eql(u8, language, "zig")) {
            try analyzeZig(allocator, trimmed_line, &functions, &variables, &imports, &function_count, &variable_count, &complexity_score);
        } else {
            // Generic analysis
            try analyzeGeneric(allocator, trimmed_line, &functions, &variables, &function_count, &variable_count, &complexity_score);
        }
    }

    return CodeAnalysisResult{
        .functions = functions,
        .variables = variables,
        .imports = imports,
        .dependencies = dependencies,
        .metrics = .{
            .lines_of_code = lines_of_code,
            .function_count = function_count,
            .variable_count = variable_count,
            .complexity_score = complexity_score,
        },
    };
}

fn analyzeJavaScript(allocator: Allocator, line: []const u8, functions: *std.json.Array, variables: *std.json.Array, imports: *std.json.Array, function_count: *u32, variable_count: *u32, complexity_score: *f32) !void {
    // Function detection
    if (std.mem.indexOf(u8, line, "function ") != null or 
        std.mem.indexOf(u8, line, "const ") != null and std.mem.indexOf(u8, line, " => ") != null or
        std.mem.indexOf(u8, line, "async function") != null) {
        function_count.* += 1;
        
        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("type", std.json.Value{ .string = "function" });
        try func_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = func_obj });
        
        complexity_score.* += 0.5;
    }

    // Variable detection
    if (std.mem.startsWith(u8, line, "var ") or 
        std.mem.startsWith(u8, line, "let ") or 
        std.mem.startsWith(u8, line, "const ")) {
        variable_count.* += 1;
        
        var var_obj = std.json.ObjectMap.init(allocator);
        try var_obj.put("type", std.json.Value{ .string = "variable" });
        try var_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try variables.append(std.json.Value{ .object = var_obj });
    }

    // Import detection
    if (std.mem.startsWith(u8, line, "import ") or 
        std.mem.startsWith(u8, line, "require(") or
        std.mem.startsWith(u8, line, "const ") and std.mem.indexOf(u8, line, "require(") != null) {
        var import_obj = std.json.ObjectMap.init(allocator);
        try import_obj.put("type", std.json.Value{ .string = "import" });
        try import_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try imports.append(std.json.Value{ .object = import_obj });
    }

    // Complexity indicators
    if (std.mem.indexOf(u8, line, "if ") != null or 
        std.mem.indexOf(u8, line, "for ") != null or 
        std.mem.indexOf(u8, line, "while ") != null or
        std.mem.indexOf(u8, line, "switch ") != null) {
        complexity_score.* += 0.3;
    }
}

fn analyzePython(allocator: Allocator, line: []const u8, functions: *std.json.Array, variables: *std.json.Array, imports: *std.json.Array, function_count: *u32, variable_count: *u32, complexity_score: *f32) !void {
    // Function detection
    if (std.mem.startsWith(u8, line, "def ") or std.mem.startsWith(u8, line, "async def ")) {
        function_count.* += 1;
        
        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("type", std.json.Value{ .string = "function" });
        try func_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = func_obj });
        
        complexity_score.* += 0.5;
    }

    // Class detection
    if (std.mem.startsWith(u8, line, "class ")) {
        function_count.* += 1;
        
        var class_obj = std.json.ObjectMap.init(allocator);
        try class_obj.put("type", std.json.Value{ .string = "class" });
        try class_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = class_obj });
        
        complexity_score.* += 0.7;
    }

    // Import detection
    if (std.mem.startsWith(u8, line, "import ") or 
        std.mem.startsWith(u8, line, "from ") and std.mem.indexOf(u8, line, " import ") != null) {
        var import_obj = std.json.ObjectMap.init(allocator);
        try import_obj.put("type", std.json.Value{ .string = "import" });
        try import_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try imports.append(std.json.Value{ .object = import_obj });
    }

    // Variable detection (simple heuristic)
    if (std.mem.indexOf(u8, line, " = ") != null and !std.mem.startsWith(u8, line, "if ") and !std.mem.startsWith(u8, line, "for ")) {
        variable_count.* += 1;
        
        var var_obj = std.json.ObjectMap.init(allocator);
        try var_obj.put("type", std.json.Value{ .string = "assignment" });
        try var_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try variables.append(std.json.Value{ .object = var_obj });
    }

    // Complexity indicators
    if (std.mem.startsWith(u8, line, "if ") or 
        std.mem.startsWith(u8, line, "for ") or 
        std.mem.startsWith(u8, line, "while ") or
        std.mem.startsWith(u8, line, "try:") or
        std.mem.startsWith(u8, line, "except")) {
        complexity_score.* += 0.3;
    }
}

fn analyzeZig(allocator: Allocator, line: []const u8, functions: *std.json.Array, variables: *std.json.Array, imports: *std.json.Array, function_count: *u32, variable_count: *u32, complexity_score: *f32) !void {
    // Function detection
    if (std.mem.indexOf(u8, line, "pub fn ") != null or 
        std.mem.indexOf(u8, line, "fn ") != null) {
        function_count.* += 1;
        
        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("type", std.json.Value{ .string = "function" });
        try func_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = func_obj });
        
        complexity_score.* += 0.5;
    }

    // Struct/enum detection
    if (std.mem.indexOf(u8, line, "pub const ") != null and std.mem.indexOf(u8, line, "struct") != null or
        std.mem.indexOf(u8, line, "pub const ") != null and std.mem.indexOf(u8, line, "enum") != null) {
        function_count.* += 1;
        
        var type_obj = std.json.ObjectMap.init(allocator);
        try type_obj.put("type", std.json.Value{ .string = "type_definition" });
        try type_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = type_obj });
        
        complexity_score.* += 0.4;
    }

    // Import detection
    if (std.mem.startsWith(u8, line, "const ") and std.mem.indexOf(u8, line, "@import(") != null) {
        var import_obj = std.json.ObjectMap.init(allocator);
        try import_obj.put("type", std.json.Value{ .string = "import" });
        try import_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try imports.append(std.json.Value{ .object = import_obj });
    }

    // Variable detection
    if ((std.mem.startsWith(u8, line, "var ") or 
         std.mem.startsWith(u8, line, "const ")) and 
         std.mem.indexOf(u8, line, "@import") == null) {
        variable_count.* += 1;
        
        var var_obj = std.json.ObjectMap.init(allocator);
        try var_obj.put("type", std.json.Value{ .string = "variable" });
        try var_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try variables.append(std.json.Value{ .object = var_obj });
    }

    // Complexity indicators
    if (std.mem.indexOf(u8, line, "if ") != null or 
        std.mem.indexOf(u8, line, "for ") != null or 
        std.mem.indexOf(u8, line, "while ") != null or
        std.mem.indexOf(u8, line, "switch ") != null) {
        complexity_score.* += 0.3;
    }
}

fn analyzeGeneric(allocator: Allocator, line: []const u8, functions: *std.json.Array, variables: *std.json.Array, function_count: *u32, variable_count: *u32, complexity_score: *f32) !void {
    // Generic function pattern detection
    if (std.mem.indexOf(u8, line, "(") != null and std.mem.indexOf(u8, line, ")") != null and
        (std.mem.indexOf(u8, line, "{") != null or std.mem.endsWith(u8, std.mem.trim(u8, line, " "), ":"))) {
        function_count.* += 1;
        
        var func_obj = std.json.ObjectMap.init(allocator);
        try func_obj.put("type", std.json.Value{ .string = "potential_function" });
        try func_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try functions.append(std.json.Value{ .object = func_obj });
        
        complexity_score.* += 0.3;
    }

    // Generic assignment detection
    if (std.mem.indexOf(u8, line, "=") != null) {
        variable_count.* += 1;
        
        var var_obj = std.json.ObjectMap.init(allocator);
        try var_obj.put("type", std.json.Value{ .string = "potential_assignment" });
        try var_obj.put("line", std.json.Value{ .string = try allocator.dupe(u8, line) });
        try variables.append(std.json.Value{ .object = var_obj });
    }
}
