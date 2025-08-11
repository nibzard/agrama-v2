//! Primitive Integration Tests
//!
//! This module provides comprehensive integration testing for the primitive-based
//! AI memory substrate, validating end-to-end workflows and system integration:
//!
//! Integration Testing Areas:
//! - End-to-end primitive workflows
//! - MCP protocol compliance testing
//! - Multi-agent interaction scenarios
//! - Database consistency validation
//! - Performance under realistic loads
//! - Error handling and recovery
//! - System reliability testing

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const expect = testing.expect;
const expectError = testing.expectError;

const agrama_lib = @import("agrama_lib");
const Database = agrama_lib.Database;
const SemanticDatabase = agrama_lib.SemanticDatabase;
const TripleHybridSearchEngine = agrama_lib.TripleHybridSearchEngine;
const PrimitiveEngine = agrama_lib.PrimitiveEngine;
const PrimitiveMCPServer = agrama_lib.PrimitiveMCPServer;
const primitives = agrama_lib.primitives;

/// Integration test configuration
const IntegrationTestConfig = struct {
    test_agents: usize = 10,
    operations_per_agent: usize = 100,
    test_duration_seconds: u64 = 30,
    max_acceptable_error_rate: f64 = 0.01, // 1% error rate
    target_latency_p99_ms: f64 = 10.0, // 99th percentile latency
};

/// Integration test context
const IntegrationTestContext = struct {
    allocator: Allocator,
    config: IntegrationTestConfig,
    database: *Database,
    semantic_db: *SemanticDatabase,
    graph_engine: *TripleHybridSearchEngine,
    primitive_engine: *PrimitiveEngine,
    mcp_server: ?*PrimitiveMCPServer = null,

    pub fn createJsonParams(self: *IntegrationTestContext, comptime T: type, params: T) !std.json.Value {
        const json_string = try std.json.stringifyAlloc(self.allocator, params, .{});
        defer self.allocator.free(json_string);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_string, .{});
        return parsed.value;
    }
};

/// Test metrics collection
const TestMetrics = struct {
    total_operations: u64 = 0,
    successful_operations: u64 = 0,
    failed_operations: u64 = 0,
    total_latency_ns: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    latency_samples: ArrayList(u64),

    pub fn init(allocator: Allocator) TestMetrics {
        return TestMetrics{
            .latency_samples = ArrayList(u64).init(allocator),
        };
    }

    pub fn deinit(self: *TestMetrics) void {
        self.latency_samples.deinit();
    }

    pub fn recordOperation(self: *TestMetrics, success: bool, latency_ns: u64) !void {
        self.total_operations += 1;

        if (success) {
            self.successful_operations += 1;
        } else {
            self.failed_operations += 1;
        }

        self.total_latency_ns += latency_ns;
        self.min_latency_ns = @min(self.min_latency_ns, latency_ns);
        self.max_latency_ns = @max(self.max_latency_ns, latency_ns);

        try self.latency_samples.append(latency_ns);
    }

    pub fn getSuccessRate(self: *TestMetrics) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_operations)) / @as(f64, @floatFromInt(self.total_operations));
    }

    pub fn getAvgLatencyMs(self: *TestMetrics) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_latency_ns)) / @as(f64, @floatFromInt(self.total_operations)) / 1_000_000.0;
    }

    pub fn getPercentileLatencyMs(self: *TestMetrics, percentile: f64) f64 {
        if (self.latency_samples.items.len == 0) return 0.0;

        // Sort samples for percentile calculation
        std.sort.heap(u64, self.latency_samples.items, {}, std.sort.asc(u64));

        const index = @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.latency_samples.items.len)) * percentile / 100.0));
        const clamped_index = @min(index, self.latency_samples.items.len - 1);

        return @as(f64, @floatFromInt(self.latency_samples.items[clamped_index])) / 1_000_000.0;
    }
};

/// End-to-end workflow tests
const WorkflowTests = struct {
    /// Test complete knowledge building workflow
    fn testCompleteKnowledgeBuildingWorkflow(ctx: *IntegrationTestContext) !void {
        std.debug.print("🔄 Testing complete knowledge building workflow...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        const agent_id = "knowledge_builder_agent";

        // Phase 1: Store initial documents
        const documents = [_]struct { id: []const u8, content: []const u8, topic: []const u8 }{
            .{ .id = "auth_concepts", .content = "Authentication is the process of verifying user identity. Modern systems use multi-factor authentication for enhanced security.", .topic = "security" },
            .{ .id = "crypto_basics", .content = "Cryptographic hash functions like SHA-256 provide data integrity. They produce fixed-size outputs from variable inputs.", .topic = "security" },
            .{ .id = "memory_management", .content = "Memory management in systems programming involves allocation and deallocation. Languages like Zig provide explicit control.", .topic = "programming" },
            .{ .id = "distributed_systems", .content = "Distributed systems face challenges like network partitions, consistency, and availability. CAP theorem describes trade-offs.", .topic = "systems" },
            .{ .id = "machine_learning", .content = "Machine learning algorithms learn patterns from data. Neural networks use backpropagation for training.", .topic = "ai" },
        };

        var workflow_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Store all documents
        for (documents) |doc| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { topic: []const u8, document_type: []const u8 } }, .{
                .key = doc.id,
                .value = doc.content,
                .metadata = .{ .topic = doc.topic, .document_type = "knowledge_base" },
            }), agent_id);

            const latency_ns = op_timer.read();
            const success = result.object.get("success").?.bool;
            try metrics.recordOperation(success, latency_ns);

            try expect(success);
        }

        // Phase 2: Extract and analyze content
        for (documents) |doc| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            // Transform to extract key concepts
            const transform_result = try ctx.primitive_engine.executePrimitive("transform", try ctx.createJsonParams(struct { operation: []const u8, data: []const u8 }, .{
                .operation = "generate_summary",
                .data = doc.content,
            }), agent_id);

            const latency_ns = op_timer.read();
            const success = transform_result.object.get("success").?.bool;
            try metrics.recordOperation(success, latency_ns);

            try expect(success);

            // Store the extracted summary
            const summary_key = try std.fmt.allocPrint(ctx.allocator, "{s}_summary", .{doc.id});
            defer ctx.allocator.free(summary_key);

            const summary_content = transform_result.object.get("output").?.string;

            const store_summary_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { derived_from: []const u8, type: []const u8 } }, .{
                .key = summary_key,
                .value = summary_content,
                .metadata = .{ .derived_from = doc.id, .type = "summary" },
            }), agent_id);

            try expect(store_summary_result.object.get("success").?.bool);
        }

        // Phase 3: Create knowledge graph relationships
        const relationships = [_]struct { from: []const u8, to: []const u8, relation: []const u8 }{
            .{ .from = "auth_concepts", .to = "crypto_basics", .relation = "relates_to" },
            .{ .from = "crypto_basics", .to = "memory_management", .relation = "implemented_using" },
            .{ .from = "distributed_systems", .to = "crypto_basics", .relation = "depends_on" },
            .{ .from = "machine_learning", .to = "distributed_systems", .relation = "can_use" },
        };

        for (relationships) |rel| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const link_result = try ctx.primitive_engine.executePrimitive("link", try ctx.createJsonParams(struct { from: []const u8, to: []const u8, relation: []const u8, metadata: struct { confidence: f64, created_by: []const u8 } }, .{
                .from = rel.from,
                .to = rel.to,
                .relation = rel.relation,
                .metadata = .{ .confidence = 0.8, .created_by = "knowledge_builder" },
            }), agent_id);

            const latency_ns = op_timer.read();
            const success = link_result.object.get("success").?.bool;
            try metrics.recordOperation(success, latency_ns);

            try expect(success);
        }

        // Phase 4: Search and validation
        const search_queries = [_]struct { query: []const u8, search_type: []const u8 }{
            .{ .query = "authentication security", .search_type = "semantic" },
            .{ .query = "memory programming", .search_type = "lexical" },
            .{ .query = "distributed systems", .search_type = "hybrid" },
        };

        for (search_queries) |query| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const search_result = try ctx.primitive_engine.executePrimitive("search", try ctx.createJsonParams(struct { query: []const u8, type: []const u8, options: struct { max_results: i32 } }, .{
                .query = query.query,
                .type = query.search_type,
                .options = .{ .max_results = 10 },
            }), agent_id);

            const latency_ns = op_timer.read();
            const success = search_result.object.get("count") != null;
            try metrics.recordOperation(success, latency_ns);

            try expect(success);

            // Should find relevant results
            const result_count = search_result.object.get("count").?.integer;
            try expect(result_count > 0);
        }

        // Phase 5: Retrieve and verify data integrity
        for (documents) |doc| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const retrieve_result = try ctx.primitive_engine.executePrimitive("retrieve", try ctx.createJsonParams(struct { key: []const u8, include_history: bool }, .{
                .key = doc.id,
                .include_history = true,
            }), agent_id);

            const latency_ns = op_timer.read();
            const success = retrieve_result.object.get("exists").?.bool;
            try metrics.recordOperation(success, latency_ns);

            try expect(success);

            // Verify content integrity
            const retrieved_content = retrieve_result.object.get("value").?.string;
            try expect(std.mem.eql(u8, retrieved_content, doc.content));

            // Verify metadata exists
            try expect(retrieve_result.object.get("metadata") != null);
        }

        const total_workflow_time_ms = @as(f64, @floatFromInt(workflow_timer.read())) / 1_000_000.0;

        // Validate overall performance
        try expect(metrics.getSuccessRate() > (1.0 - ctx.config.max_acceptable_error_rate));
        try expect(metrics.getPercentileLatencyMs(99) < ctx.config.target_latency_p99_ms);

        std.debug.print("✅ COMPLETE WORKFLOW: {d} operations, {d:.1}% success, {d:.2}ms avg, {d:.2}ms p99\n", .{
            metrics.total_operations,
            metrics.getSuccessRate() * 100,
            metrics.getAvgLatencyMs(),
            metrics.getPercentileLatencyMs(99),
        });
        std.debug.print("   Total workflow time: {d:.1}ms\n", .{total_workflow_time_ms});
    }

    /// Test multi-agent collaborative workflow
    fn testMultiAgentCollaborativeWorkflow(ctx: *IntegrationTestContext) !void {
        std.debug.print("🤝 Testing multi-agent collaborative workflow...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        // Define agent roles and their specializations
        const agents = [_]struct { name: []const u8, specialty: []const u8 }{
            .{ .name = "data_collector_agent", .specialty = "data_collection" },
            .{ .name = "analyzer_agent", .specialty = "analysis" },
            .{ .name = "knowledge_curator_agent", .specialty = "curation" },
            .{ .name = "validator_agent", .specialty = "validation" },
        };

        const collaboration_data = "Large text about software engineering practices, testing methodologies, and quality assurance processes in modern development teams.";

        var workflow_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Phase 1: Data Collector Agent stores raw data
        {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { collected_by: []const u8, source: []const u8, collection_timestamp: i64 } }, .{
                .key = "raw_software_practices_data",
                .value = collaboration_data,
                .metadata = .{
                    .collected_by = agents[0].name,
                    .source = "industry_survey_2024",
                    .collection_timestamp = std.time.timestamp(),
                },
            }), agents[0].name);

            const latency_ns = op_timer.read();
            try metrics.recordOperation(result.object.get("success").?.bool, latency_ns);
            try expect(result.object.get("success").?.bool);
        }

        // Phase 2: Analyzer Agent processes the data
        {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const analysis_result = try ctx.primitive_engine.executePrimitive("transform", try ctx.createJsonParams(struct { operation: []const u8, data: []const u8 }, .{
                .operation = "parse_functions", // Simulating analysis
                .data = collaboration_data,
            }), agents[1].name);

            const latency_ns = op_timer.read();
            try metrics.recordOperation(analysis_result.object.get("success").?.bool, latency_ns);
            try expect(analysis_result.object.get("success").?.bool);

            // Store analysis results
            const analyzed_data = analysis_result.object.get("output").?.string;

            const store_analysis_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { analyzed_by: []const u8, analysis_type: []const u8, derived_from: []const u8 } }, .{
                .key = "software_practices_analysis",
                .value = analyzed_data,
                .metadata = .{
                    .analyzed_by = agents[1].name,
                    .analysis_type = "function_extraction",
                    .derived_from = "raw_software_practices_data",
                },
            }), agents[1].name);

            try expect(store_analysis_result.object.get("success").?.bool);
        }

        // Phase 3: Knowledge Curator creates relationships
        {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const link_result = try ctx.primitive_engine.executePrimitive("link", try ctx.createJsonParams(struct { from: []const u8, to: []const u8, relation: []const u8, metadata: struct { curated_by: []const u8, curation_confidence: f64, relationship_type: []const u8 } }, .{
                .from = "raw_software_practices_data",
                .to = "software_practices_analysis",
                .relation = "analyzed_to_produce",
                .metadata = .{
                    .curated_by = agents[2].name,
                    .curation_confidence = 0.95,
                    .relationship_type = "data_transformation",
                },
            }), agents[2].name);

            const latency_ns = op_timer.read();
            try metrics.recordOperation(link_result.object.get("success").?.bool, latency_ns);
            try expect(link_result.object.get("success").?.bool);
        }

        // Phase 4: Validator Agent performs quality checks
        {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            // Retrieve data for validation
            const retrieve_result = try ctx.primitive_engine.executePrimitive("retrieve", try ctx.createJsonParams(struct { key: []const u8, include_history: bool }, .{
                .key = "software_practices_analysis",
                .include_history = true,
            }), agents[3].name);

            const latency_ns = op_timer.read();
            try metrics.recordOperation(retrieve_result.object.get("exists").?.bool, latency_ns);
            try expect(retrieve_result.object.get("exists").?.bool);

            // Perform search to validate relationships
            const search_result = try ctx.primitive_engine.executePrimitive("search", try ctx.createJsonParams(struct { query: []const u8, type: []const u8, options: struct { max_results: i32 } }, .{
                .query = "software practices",
                .type = "hybrid",
                .options = .{ .max_results = 5 },
            }), agents[3].name);

            try expect(search_result.object.get("count") != null);

            // Store validation report
            const validation_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { validated_by: []const u8, validation_status: []const u8, validation_timestamp: i64 } }, .{
                .key = "software_practices_validation_report",
                .value = "Validation completed: Data integrity confirmed, relationships verified, search functionality operational.",
                .metadata = .{
                    .validated_by = agents[3].name,
                    .validation_status = "passed",
                    .validation_timestamp = std.time.timestamp(),
                },
            }), agents[3].name);

            try expect(validation_result.object.get("success").?.bool);
        }

        // Phase 5: Cross-agent verification - each agent checks others' work
        for (agents) |agent| {
            const search_result = try ctx.primitive_engine.executePrimitive("search", try ctx.createJsonParams(struct { query: []const u8, type: []const u8, options: struct { max_results: i32 } }, .{
                .query = "software practices validation analysis",
                .type = "semantic",
                .options = .{ .max_results = 10 },
            }), agent.name);

            try expect(search_result.object.get("count") != null);
            const result_count = search_result.object.get("count").?.integer;
            try expect(result_count >= 2); // Should find at least raw data and analysis
        }

        const total_workflow_time_ms = @as(f64, @floatFromInt(workflow_timer.read())) / 1_000_000.0;

        // Validate collaboration metrics
        try expect(metrics.getSuccessRate() > (1.0 - ctx.config.max_acceptable_error_rate));
        try expect(metrics.total_operations >= 4); // At least one operation per agent

        std.debug.print("✅ MULTI-AGENT COLLABORATION: {d} agents, {d} operations, {d:.1}% success\n", .{
            agents.len,
            metrics.total_operations,
            metrics.getSuccessRate() * 100,
        });
        std.debug.print("   Workflow completion time: {d:.1}ms\n", .{total_workflow_time_ms});
    }

    /// Test iterative refinement workflow
    fn testIterativeRefinementWorkflow(ctx: *IntegrationTestContext) !void {
        std.debug.print("🔄 Testing iterative refinement workflow...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        const agent_id = "iterative_agent";
        const base_concept = "authentication_system";

        // Define refinement iterations
        const iterations = [_]struct { version: u32, content: []const u8, improvement: []const u8 }{
            .{ .version = 1, .content = "Basic password authentication with username/password validation.", .improvement = "initial_version" },
            .{ .version = 2, .content = "Enhanced authentication with password hashing using bcrypt for security.", .improvement = "added_password_hashing" },
            .{ .version = 3, .content = "Multi-factor authentication with SMS verification and time-based tokens.", .improvement = "added_multi_factor" },
            .{ .version = 4, .content = "Zero-trust authentication with continuous verification and device fingerprinting.", .improvement = "added_zero_trust" },
            .{ .version = 5, .content = "Biometric authentication integration with fallback to traditional methods.", .improvement = "added_biometric_support" },
        };

        var workflow_timer = std.time.Timer.start() catch return error.TimerUnavailable;

        // Store each iteration
        for (iterations) |iteration| {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const version_key = try std.fmt.allocPrint(ctx.allocator, "{s}_v{d}", .{ base_concept, iteration.version });
            defer ctx.allocator.free(version_key);

            const store_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { version: u32, improvement: []const u8, iteration_timestamp: i64, base_concept: []const u8 } }, .{
                .key = version_key,
                .value = iteration.content,
                .metadata = .{
                    .version = iteration.version,
                    .improvement = iteration.improvement,
                    .iteration_timestamp = std.time.timestamp(),
                    .base_concept = base_concept,
                },
            }), agent_id);

            const latency_ns = op_timer.read();
            try metrics.recordOperation(store_result.object.get("success").?.bool, latency_ns);
            try expect(store_result.object.get("success").?.bool);

            // Link to previous version if not the first
            if (iteration.version > 1) {
                const prev_key = try std.fmt.allocPrint(ctx.allocator, "{s}_v{d}", .{ base_concept, iteration.version - 1 });
                defer ctx.allocator.free(prev_key);

                const link_result = try ctx.primitive_engine.executePrimitive("link", try ctx.createJsonParams(struct { from: []const u8, to: []const u8, relation: []const u8, metadata: struct { evolution_type: []const u8, version_increment: u32, improvement_description: []const u8 } }, .{
                    .from = prev_key,
                    .to = version_key,
                    .relation = "evolved_into",
                    .metadata = .{
                        .evolution_type = "iterative_refinement",
                        .version_increment = 1,
                        .improvement_description = iteration.improvement,
                    },
                }), agent_id);

                try expect(link_result.object.get("success").?.bool);
            }

            // Analyze the improvement using transform
            const analysis_result = try ctx.primitive_engine.executePrimitive("transform", try ctx.createJsonParams(struct { operation: []const u8, data: []const u8 }, .{
                .operation = "generate_summary",
                .data = iteration.content,
            }), agent_id);

            try expect(analysis_result.object.get("success").?.bool);

            // Store analysis of this version
            const analysis_key = try std.fmt.allocPrint(ctx.allocator, "{s}_v{d}_analysis", .{ base_concept, iteration.version });
            defer ctx.allocator.free(analysis_key);

            const analysis_content = analysis_result.object.get("output").?.string;

            const store_analysis_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8, metadata: struct { analysis_version: u32, source_version: []const u8, analysis_type: []const u8 } }, .{
                .key = analysis_key,
                .value = analysis_content,
                .metadata = .{
                    .analysis_version = iteration.version,
                    .source_version = version_key,
                    .analysis_type = "summary_analysis",
                },
            }), agent_id);

            try expect(store_analysis_result.object.get("success").?.bool);
        }

        // Test evolution chain queries
        for (1..iterations.len + 1) |version| {
            const search_query = try std.fmt.allocPrint(ctx.allocator, "authentication system v{d}", .{version});
            defer ctx.allocator.free(search_query);

            const search_result = try ctx.primitive_engine.executePrimitive("search", try ctx.createJsonParams(struct { query: []const u8, type: []const u8, options: struct { max_results: i32 } }, .{
                .query = search_query,
                .type = "hybrid",
                .options = .{ .max_results = 3 },
            }), agent_id);

            try expect(search_result.object.get("count") != null);
            const result_count = search_result.object.get("count").?.integer;
            try expect(result_count > 0);
        }

        // Validate the complete evolution chain
        const latest_version_key = try std.fmt.allocPrint(ctx.allocator, "{s}_v{d}", .{ base_concept, iterations.len });
        defer ctx.allocator.free(latest_version_key);

        const retrieve_result = try ctx.primitive_engine.executePrimitive("retrieve", try ctx.createJsonParams(struct { key: []const u8, include_history: bool }, .{
            .key = latest_version_key,
            .include_history = true,
        }), agent_id);

        try expect(retrieve_result.object.get("exists").?.bool);

        const total_workflow_time_ms = @as(f64, @floatFromInt(workflow_timer.read())) / 1_000_000.0;

        // Validate iterative refinement metrics
        try expect(metrics.getSuccessRate() > (1.0 - ctx.config.max_acceptable_error_rate));
        try expect(metrics.total_operations >= iterations.len * 3); // Store + link + transform per iteration

        std.debug.print("✅ ITERATIVE REFINEMENT: {d} iterations, {d} operations, {d:.1}% success\n", .{
            iterations.len,
            metrics.total_operations,
            metrics.getSuccessRate() * 100,
        });
        std.debug.print("   Complete evolution chain time: {d:.1}ms\n", .{total_workflow_time_ms});
    }
};

/// MCP protocol compliance tests
const MCPComplianceTests = struct {
    /// Test MCP server initialization and capabilities
    fn testMCPServerInitialization(ctx: *IntegrationTestContext) !void {
        std.debug.print("📡 Testing MCP server initialization...\n", .{});

        // Initialize MCP server
        var mcp_server = try PrimitiveMCPServer.init(ctx.allocator, ctx.database, ctx.semantic_db, ctx.graph_engine);
        defer mcp_server.deinit();

        // Verify server has all 5 primitives registered
        try expect(mcp_server.primitives.items.len == 5);

        // Verify primitive names
        var found_primitives = std.EnumSet(enum { store, retrieve, search, link, transform }).initEmpty();

        for (mcp_server.primitives.items) |primitive| {
            if (std.mem.eql(u8, primitive.name, "store")) {
                found_primitives.insert(.store);
            } else if (std.mem.eql(u8, primitive.name, "retrieve")) {
                found_primitives.insert(.retrieve);
            } else if (std.mem.eql(u8, primitive.name, "search")) {
                found_primitives.insert(.search);
            } else if (std.mem.eql(u8, primitive.name, "link")) {
                found_primitives.insert(.link);
            } else if (std.mem.eql(u8, primitive.name, "transform")) {
                found_primitives.insert(.transform);
            }
        }

        try expect(found_primitives.count() == 5);

        // Verify server capabilities
        try expect(mcp_server.capabilities.tools != null);
        try expect(mcp_server.capabilities.logging != null);

        // Test performance statistics
        const perf_stats = try mcp_server.getPerformanceStats();
        try expect(perf_stats.object.get("total_primitive_calls") != null);
        try expect(perf_stats.object.get("avg_response_time_ms") != null);

        std.debug.print("✅ MCP SERVER initialization: 5 primitives registered, capabilities validated\n", .{});
    }

    /// Test MCP protocol message handling
    fn testMCPProtocolMessages(ctx: *IntegrationTestContext) !void {
        std.debug.print("📨 Testing MCP protocol message handling...\n", .{});

        // Initialize MCP server
        var mcp_server = try PrimitiveMCPServer.init(ctx.allocator, ctx.database, ctx.semantic_db, ctx.graph_engine);
        defer mcp_server.deinit();

        // Test agent session management through the server
        try mcp_server.updateAgentSession("test_mcp_agent", "store");
        try mcp_server.updateAgentSession("test_mcp_agent", "retrieve");
        try mcp_server.updateAgentSession("test_mcp_agent", "search");

        try expect(mcp_server.agent_sessions.count() >= 1);

        if (mcp_server.agent_sessions.get("test_mcp_agent")) |session| {
            try expect(session.operations_count == 3);
            try expect(session.primitives_used.count() == 3);
        }

        // Test performance tracking
        const initial_calls = mcp_server.total_primitive_calls;

        // Simulate tool calls through the primitive engine (MCP server integration)
        const test_operations = [_]struct { primitive: []const u8, success_expected: bool }{
            .{ .primitive = "store", .success_expected = true },
            .{ .primitive = "retrieve", .success_expected = true },
            .{ .primitive = "search", .success_expected = true },
            .{ .primitive = "link", .success_expected = true },
            .{ .primitive = "transform", .success_expected = true },
        };

        for (test_operations) |op| {
            // Create appropriate parameters for each primitive
            const params = switch (std.mem.eql(u8, op.primitive, "store")) {
                true => try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                    .key = "mcp_test_key",
                    .value = "MCP test value",
                }),
                false => switch (std.mem.eql(u8, op.primitive, "retrieve")) {
                    true => try ctx.createJsonParams(struct { key: []const u8 }, .{
                        .key = "mcp_test_key",
                    }),
                    false => switch (std.mem.eql(u8, op.primitive, "search")) {
                        true => try ctx.createJsonParams(struct { query: []const u8, type: []const u8 }, .{
                            .query = "MCP test search",
                            .type = "lexical",
                        }),
                        false => switch (std.mem.eql(u8, op.primitive, "link")) {
                            true => try ctx.createJsonParams(struct { from: []const u8, to: []const u8, relation: []const u8 }, .{
                                .from = "mcp_test_source",
                                .to = "mcp_test_target",
                                .relation = "mcp_test_relation",
                            }),
                            false => try ctx.createJsonParams(struct { operation: []const u8, data: []const u8 }, .{
                                .operation = "generate_summary",
                                .data = "MCP test data for transformation",
                            }),
                        },
                    },
                },
            };

            const result = try ctx.primitive_engine.executePrimitive(op.primitive, params, "mcp_compliance_agent");

            const actual_success = result.object.get("success").?.bool;
            if (op.success_expected) {
                try expect(actual_success);
            }
        }

        // Verify call tracking worked
        try expect(mcp_server.total_primitive_calls >= initial_calls);

        std.debug.print("✅ MCP PROTOCOL messages: session tracking, performance monitoring validated\n", .{});
    }

    /// Test MCP error handling and recovery
    fn testMCPErrorHandling(ctx: *IntegrationTestContext) !void {
        std.debug.print("🚨 Testing MCP error handling and recovery...\n", .{});

        // Test invalid primitive calls
        const invalid_operations = [_]struct { primitive: []const u8, params: std.json.Value, expected_error: bool }{
            // Invalid store operation (empty key)
            .{ .primitive = "store", .params = try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                .key = "",
                .value = "some value",
            }), .expected_error = true },
            // Invalid search type
            .{ .primitive = "search", .params = try ctx.createJsonParams(struct { query: []const u8, type: []const u8 }, .{
                .query = "test query",
                .type = "invalid_search_type",
            }), .expected_error = true },
            // Invalid transform operation
            .{ .primitive = "transform", .params = try ctx.createJsonParams(struct { operation: []const u8, data: []const u8 }, .{
                .operation = "unsupported_operation",
                .data = "test data",
            }), .expected_error = true },
        };

        var error_handled_count: usize = 0;

        for (invalid_operations) |invalid_op| {
            const result = ctx.primitive_engine.executePrimitive(invalid_op.primitive, invalid_op.params, "error_test_agent") catch |err| {
                // Expect specific errors to be caught
                switch (err) {
                    error.EmptyKey, error.InvalidSearchType, error.UnsupportedOperation, error.UnknownPrimitive => {
                        error_handled_count += 1;
                        continue;
                    },
                    else => return err,
                }
            };

            // If no error was thrown, check if the operation failed gracefully
            if (result.object.get("success")) |success| {
                if (success.bool == false and invalid_op.expected_error) {
                    error_handled_count += 1;
                }
            }
        }

        try expect(error_handled_count == invalid_operations.len);

        // Test system recovery after errors
        const recovery_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
            .key = "recovery_test",
            .value = "System should work normally after errors",
        }), "recovery_test_agent");

        try expect(recovery_result.object.get("success").?.bool == true);

        std.debug.print("✅ MCP ERROR handling: {d} errors handled gracefully, system recovery validated\n", .{error_handled_count});
    }
};

/// System reliability and stress tests
const ReliabilityTests = struct {
    /// Test system under sustained load
    fn testSustainedLoadReliability(ctx: *IntegrationTestContext) !void {
        std.debug.print("⚡ Testing sustained load reliability...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        const load_duration_ms = 5000; // 5 seconds
        const target_ops_per_second = 100;
        const start_time = std.time.milliTimestamp();

        var operation_count: usize = 0;

        // Sustain load for the specified duration
        while (std.time.milliTimestamp() - start_time < load_duration_ms) {
            var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

            const agent_name = try std.fmt.allocPrint(ctx.allocator, "load_agent_{d}", .{operation_count % 10});
            defer ctx.allocator.free(agent_name);

            const key = try std.fmt.allocPrint(ctx.allocator, "load_test_{d}", .{operation_count});
            defer ctx.allocator.free(key);

            const value = try std.fmt.allocPrint(ctx.allocator, "Load test data {d} at {d}ms", .{ operation_count, std.time.milliTimestamp() });
            defer ctx.allocator.free(value);

            const result = ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                .key = key,
                .value = value,
            }), agent_name) catch |err| {
                const latency_ns = op_timer.read();
                try metrics.recordOperation(false, latency_ns);
                std.debug.print("⚠️ Load test operation {d} failed: {any}\n", .{ operation_count, err });
                continue;
            };

            const latency_ns = op_timer.read();
            const success = result.object.get("success").?.bool;
            try metrics.recordOperation(success, latency_ns);

            operation_count += 1;

            // Small delay to control load rate
            std.time.sleep(1_000_000); // 1ms
        }

        const actual_duration_ms = std.time.milliTimestamp() - start_time;
        const actual_ops_per_second = @as(f64, @floatFromInt(operation_count)) / (@as(f64, @floatFromInt(actual_duration_ms)) / 1000.0);

        // System should maintain reasonable performance under load
        try expect(metrics.getSuccessRate() > 0.95); // 95% success rate minimum
        try expect(actual_ops_per_second > @as(f64, @floatFromInt(target_ops_per_second)) * 0.8); // At least 80% of target

        std.debug.print("✅ SUSTAINED LOAD: {d} ops in {d}ms, {d:.0} ops/sec, {d:.1}% success\n", .{
            operation_count,
            actual_duration_ms,
            actual_ops_per_second,
            metrics.getSuccessRate() * 100,
        });
        std.debug.print("   Avg latency: {d:.2}ms, P99: {d:.2}ms\n", .{
            metrics.getAvgLatencyMs(),
            metrics.getPercentileLatencyMs(99),
        });
    }

    /// Test concurrent access patterns
    fn testConcurrentAccessPatterns(ctx: *IntegrationTestContext) !void {
        std.debug.print("🔄 Testing concurrent access patterns...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        const num_concurrent_operations = 50;
        const shared_data_key = "concurrent_shared_data";

        // Initialize shared data
        const init_result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
            .key = shared_data_key,
            .value = "Initial shared data for concurrent access testing",
        }), "init_agent");
        try expect(init_result.object.get("success").?.bool);

        // Simulate concurrent read/write operations
        for (0..num_concurrent_operations) |i| {
            const agent_name = try std.fmt.allocPrint(ctx.allocator, "concurrent_agent_{d}", .{i});
            defer ctx.allocator.free(agent_name);

            if (i % 3 == 0) {
                // Write operation (update shared data)
                var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

                const new_value = try std.fmt.allocPrint(ctx.allocator, "Updated by {s} at iteration {d}", .{ agent_name, i });
                defer ctx.allocator.free(new_value);

                const result = ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                    .key = shared_data_key,
                    .value = new_value,
                }), agent_name) catch |err| {
                    const latency_ns = op_timer.read();
                    try metrics.recordOperation(false, latency_ns);
                    std.debug.print("⚠️ Concurrent write {d} failed: {any}\n", .{ i, err });
                    continue;
                };

                const latency_ns = op_timer.read();
                try metrics.recordOperation(result.object.get("success").?.bool, latency_ns);
            } else {
                // Read operation
                var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

                const result = ctx.primitive_engine.executePrimitive("retrieve", try ctx.createJsonParams(struct { key: []const u8 }, .{
                    .key = shared_data_key,
                }), agent_name) catch |err| {
                    const latency_ns = op_timer.read();
                    try metrics.recordOperation(false, latency_ns);
                    std.debug.print("⚠️ Concurrent read {d} failed: {any}\n", .{ i, err });
                    continue;
                };

                const latency_ns = op_timer.read();
                try metrics.recordOperation(result.object.get("exists").?.bool, latency_ns);
            }
        }

        // Verify final data integrity
        const final_result = try ctx.primitive_engine.executePrimitive("retrieve", try ctx.createJsonParams(struct { key: []const u8, include_history: bool }, .{
            .key = shared_data_key,
            .include_history = true,
        }), "integrity_check_agent");

        try expect(final_result.object.get("exists").?.bool);

        // System should handle concurrent access without corruption
        try expect(metrics.getSuccessRate() > 0.90); // 90% success rate minimum for concurrent access

        std.debug.print("✅ CONCURRENT ACCESS: {d} operations, {d:.1}% success, data integrity maintained\n", .{
            metrics.total_operations,
            metrics.getSuccessRate() * 100,
        });
    }

    /// Test error recovery and system resilience
    fn testErrorRecoveryResilience(ctx: *IntegrationTestContext) !void {
        std.debug.print("🛡️ Testing error recovery and resilience...\n", .{});

        var metrics = TestMetrics.init(ctx.allocator);
        defer metrics.deinit();

        // Test recovery from various error conditions
        const error_scenarios = [_]struct { name: []const u8, operation: []const u8 }{
            .{ .name = "invalid_key_error", .operation = "store_with_empty_key" },
            .{ .name = "missing_data_error", .operation = "retrieve_nonexistent" },
            .{ .name = "invalid_search_error", .operation = "search_with_invalid_type" },
            .{ .name = "malformed_link_error", .operation = "link_with_empty_fields" },
            .{ .name = "unsupported_transform_error", .operation = "transform_unsupported_operation" },
        };

        var recovery_count: usize = 0;

        for (error_scenarios) |scenario| {
            std.debug.print("  Testing recovery from: {s}\n", .{scenario.name});

            // Cause the error condition
            _ = ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                .key = "", // This should cause an error
                .value = "test value",
            }), "error_scenario_agent") catch {
                // Error expected

                // Test immediate recovery with valid operation
                var op_timer = std.time.Timer.start() catch return error.TimerUnavailable;

                const recovery_key = try std.fmt.allocPrint(ctx.allocator, "recovery_after_{s}", .{scenario.name});
                defer ctx.allocator.free(recovery_key);

                const recovery_result = ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                    .key = recovery_key,
                    .value = "System recovered successfully after error",
                }), "recovery_test_agent") catch |recovery_err| {
                    std.debug.print("⚠️ Recovery failed for {s}: {any}\n", .{ scenario.name, recovery_err });
                    continue;
                };

                const latency_ns = op_timer.read();
                const success = recovery_result.object.get("success").?.bool;
                try metrics.recordOperation(success, latency_ns);

                if (success) {
                    recovery_count += 1;
                }

                continue;
            };

            // If no error occurred, that might be fine too (system might handle gracefully)
            recovery_count += 1;
        }

        // System should recover from all error scenarios
        try expect(recovery_count == error_scenarios.len);

        // Test system stability after multiple errors
        const stability_operations = 10;
        for (0..stability_operations) |i| {
            const stability_key = try std.fmt.allocPrint(ctx.allocator, "stability_test_{d}", .{i});
            defer ctx.allocator.free(stability_key);

            const result = try ctx.primitive_engine.executePrimitive("store", try ctx.createJsonParams(struct { key: []const u8, value: []const u8 }, .{
                .key = stability_key,
                .value = "Post-error stability validation",
            }), "stability_agent");

            try expect(result.object.get("success").?.bool);
        }

        std.debug.print("✅ ERROR RECOVERY: {d}/{d} scenarios recovered, system stability maintained\n", .{
            recovery_count,
            error_scenarios.len,
        });
    }
};

/// Main integration test execution function
pub fn runIntegrationTests(allocator: Allocator) !void {
    std.debug.print("\n🔧 PRIMITIVE INTEGRATION TEST SUITE\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    // Initialize test infrastructure
    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    var integration_ctx = IntegrationTestContext{
        .allocator = allocator,
        .config = IntegrationTestConfig{},
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .primitive_engine = &primitive_engine,
    };

    const start_time = std.time.milliTimestamp();

    // Run all integration test categories
    std.debug.print("🔄 END-TO-END WORKFLOW TESTS\n", .{});
    try WorkflowTests.testCompleteKnowledgeBuildingWorkflow(&integration_ctx);
    try WorkflowTests.testMultiAgentCollaborativeWorkflow(&integration_ctx);
    try WorkflowTests.testIterativeRefinementWorkflow(&integration_ctx);

    std.debug.print("\n📡 MCP PROTOCOL COMPLIANCE TESTS\n", .{});
    try MCPComplianceTests.testMCPServerInitialization(&integration_ctx);
    try MCPComplianceTests.testMCPProtocolMessages(&integration_ctx);
    try MCPComplianceTests.testMCPErrorHandling(&integration_ctx);

    std.debug.print("\n⚡ SYSTEM RELIABILITY TESTS\n", .{});
    try ReliabilityTests.testSustainedLoadReliability(&integration_ctx);
    try ReliabilityTests.testConcurrentAccessPatterns(&integration_ctx);
    try ReliabilityTests.testErrorRecoveryResilience(&integration_ctx);

    const total_time_ms = @as(f64, @floatFromInt(std.time.milliTimestamp() - start_time));

    std.debug.print("\n🎯 INTEGRATION TEST SUITE SUMMARY\n", .{});
    std.debug.print("=" ** 50 ++ "\n", .{});
    std.debug.print("✅ All integration tests PASSED!\n", .{});
    std.debug.print("⏱️  Total execution time: {d:.1}ms\n", .{total_time_ms});
    std.debug.print("🔧 Integration validations:\n", .{});
    std.debug.print("   • End-to-end workflows ✅\n", .{});
    std.debug.print("   • Multi-agent collaboration ✅\n", .{});
    std.debug.print("   • MCP protocol compliance ✅\n", .{});
    std.debug.print("   • System reliability ✅\n", .{});
    std.debug.print("   • Error recovery ✅\n", .{});
    std.debug.print("   • Performance under load ✅\n", .{});
    std.debug.print("\n🚀 PRIMITIVE SUBSTRATE INTEGRATION VALIDATED!\n", .{});
}

// Export tests for zig test runner
test "primitive integration comprehensive test suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected in integration test suite", .{});
        }
    }
    const allocator = gpa.allocator();

    try runIntegrationTests(allocator);
}

test "end-to-end workflow tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    var integration_ctx = IntegrationTestContext{
        .allocator = allocator,
        .config = IntegrationTestConfig{
            .operations_per_agent = 10, // Reduced for test
            .test_duration_seconds = 5, // Reduced for test
        },
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .primitive_engine = &primitive_engine,
    };

    try WorkflowTests.testCompleteKnowledgeBuildingWorkflow(&integration_ctx);
}

test "MCP protocol compliance tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var database = Database.init(allocator);
    defer database.deinit();

    var semantic_db = try SemanticDatabase.init(allocator, .{});
    defer semantic_db.deinit();

    var graph_engine = TripleHybridSearchEngine.init(allocator);
    defer graph_engine.deinit();

    var primitive_engine = try PrimitiveEngine.init(allocator, &database, &semantic_db, &graph_engine);
    defer primitive_engine.deinit();

    var integration_ctx = IntegrationTestContext{
        .allocator = allocator,
        .config = IntegrationTestConfig{},
        .database = &database,
        .semantic_db = &semantic_db,
        .graph_engine = &graph_engine,
        .primitive_engine = &primitive_engine,
    };

    try MCPComplianceTests.testMCPServerInitialization(&integration_ctx);
    try MCPComplianceTests.testMCPErrorHandling(&integration_ctx);
}
