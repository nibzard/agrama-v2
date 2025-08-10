//! Graph Construction Pipeline for Persistent Benchmark Graphs
//!
//! Converts parsed conversation entities and relationships into temporal graph structures
//! with multiple density levels for benchmarking different algorithms:
//!
//! - Sparse Graphs (m ≈ 3n): Core dependencies, optimal for Dijkstra
//! - Medium Graphs (m ≈ 15n): Add semantic relationships, close competition
//! - Dense Graphs (m ≈ 40n+): Full knowledge graph, optimal for FRE
//!
//! Each graph represents realistic code evolution patterns from AI-human collaboration
//!

const std = @import("std");
const conversation_parser = @import("conversation_parser.zig");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const ConversationData = conversation_parser.ConversationData;
const Entity = conversation_parser.Entity;
const Relationship = conversation_parser.Relationship;
const EntityType = conversation_parser.EntityType;
const RelationshipType = conversation_parser.RelationshipType;

/// Graph density categories for benchmark testing
pub const GraphDensity = enum {
    sparse, // m ≈ 3n - Core dependencies only
    medium, // m ≈ 15n - Add semantic relationships
    dense, // m ≈ 40n+ - Full knowledge graph
    very_dense, // m ≈ 80n+ - Maximal connectivity
};

/// Node in the constructed benchmark graph
pub const GraphNode = struct {
    id: u32,
    node_type: NodeType,
    name: []const u8,
    content: ?[]const u8,
    project: []const u8,
    conversation_turn: u32,
    timestamp: i64,
    embedding: ?[]f32, // For semantic similarity
    metadata: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub const NodeType = enum {
        code_file,
        code_function,
        code_class,
        dependency,
        decision_point,
        task_item,
        temporal_marker,
        semantic_cluster,
    };

    pub fn deinit(self: *GraphNode, allocator: Allocator) void {
        if (self.embedding) |embedding| {
            allocator.free(embedding);
        }
        self.metadata.deinit();
    }
};

/// Edge in the constructed benchmark graph
pub const GraphEdge = struct {
    id: u32,
    from_node: u32,
    to_node: u32,
    edge_type: EdgeType,
    weight: f32,
    strength: f32,
    conversation_turn: u32,
    metadata: HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub const EdgeType = enum {
        dependency, // File A depends on File B
        contains, // File contains Function
        calls, // Function A calls Function B
        modifies, // Turn N modifies Entity
        creates, // Turn N creates Entity
        similar, // Semantic similarity
        temporal, // Temporal sequence
        decision_leads_to, // Decision leads to implementation
        task_implements, // Task results in code
        co_occurrence, // Entities appear together
    };

    pub fn deinit(self: *GraphEdge, allocator: Allocator) void {
        _ = allocator;
        self.metadata.deinit();
    }
};

/// Constructed temporal graph with metadata
pub const TemporalGraph = struct {
    name: []const u8,
    project: []const u8,
    density: GraphDensity,
    conversation_count: u32,
    nodes: ArrayList(GraphNode),
    edges: ArrayList(GraphEdge),
    node_lookup: HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    expected_algorithm: Algorithm,
    creation_timestamp: i64,

    pub const Algorithm = enum { dijkstra, fre };

    pub fn init(allocator: Allocator, name: []const u8, project: []const u8, density: GraphDensity) TemporalGraph {
        return TemporalGraph{
            .name = name,
            .project = project,
            .density = density,
            .conversation_count = 0,
            .nodes = ArrayList(GraphNode).init(allocator),
            .edges = ArrayList(GraphEdge).init(allocator),
            .node_lookup = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .expected_algorithm = switch (density) {
                .sparse, .medium => Algorithm.dijkstra,
                .dense, .very_dense => Algorithm.fre,
            },
            .creation_timestamp = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *TemporalGraph, allocator: Allocator) void {
        for (self.nodes.items) |*node| {
            node.deinit(allocator);
        }
        self.nodes.deinit();

        for (self.edges.items) |*edge| {
            edge.deinit(allocator);
        }
        self.edges.deinit();

        self.node_lookup.deinit();
    }

    /// Get graph statistics for analysis
    pub fn getStats(self: *TemporalGraph) GraphStats {
        const node_count = @as(u32, @intCast(self.nodes.items.len));
        const edge_count = @as(u32, @intCast(self.edges.items.len));
        const avg_degree = if (node_count > 0) @as(f32, @floatFromInt(edge_count)) / @as(f32, @floatFromInt(node_count)) else 0.0;

        return GraphStats{
            .node_count = node_count,
            .edge_count = edge_count,
            .avg_degree = avg_degree,
            .density_ratio = avg_degree / @as(f32, @floatFromInt(@max(node_count, 1))),
            .project = self.project,
            .density_category = self.density,
            .expected_algorithm = self.expected_algorithm,
        };
    }

    pub const GraphStats = struct {
        node_count: u32,
        edge_count: u32,
        avg_degree: f32,
        density_ratio: f32,
        project: []const u8,
        density_category: GraphDensity,
        expected_algorithm: Algorithm,
    };
};

/// Main graph builder that constructs temporal graphs from conversation data
pub const GraphBuilder = struct {
    allocator: Allocator,
    node_counter: u32,
    edge_counter: u32,

    pub fn init(allocator: Allocator) GraphBuilder {
        return GraphBuilder{
            .allocator = allocator,
            .node_counter = 1,
            .edge_counter = 1,
        };
    }

    /// Build multiple graph densities from a collection of conversations
    pub fn buildGraphSet(self: *GraphBuilder, conversations: []ConversationData, project_name: []const u8) !ArrayList(TemporalGraph) {
        var graphs = ArrayList(TemporalGraph).init(self.allocator);

        // Create sparse graph (core dependencies only)
        var sparse_graph = TemporalGraph.init(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}_sparse", .{project_name}), project_name, .sparse);
        try self.buildSparseGraph(&sparse_graph, conversations);
        try graphs.append(sparse_graph);

        // Create medium graph (add semantic relationships)
        var medium_graph = TemporalGraph.init(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}_medium", .{project_name}), project_name, .medium);
        try self.buildMediumGraph(&medium_graph, conversations);
        try graphs.append(medium_graph);

        // Create dense graph (full knowledge graph)
        var dense_graph = TemporalGraph.init(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}_dense", .{project_name}), project_name, .dense);
        try self.buildDenseGraph(&dense_graph, conversations);
        try graphs.append(dense_graph);

        return graphs;
    }

    /// Build sparse graph with core dependencies only (m ≈ 3n)
    fn buildSparseGraph(self: *GraphBuilder, graph: *TemporalGraph, conversations: []ConversationData) !void {
        // Add core entities: files, primary functions, clear dependencies
        for (conversations) |conversation| {
            graph.conversation_count += 1;

            for (conversation.entities.items) |entity| {
                // Only include primary code entities for sparse graph
                if (entity.entity_type == .file) {
                    try self.addFileNode(graph, entity);
                } else if (entity.entity_type == .decision and self.isPrimaryDecision(entity)) {
                    try self.addDecisionNode(graph, entity);
                }
            }

            // Add only direct dependencies and core relationships
            for (conversation.relationships.items) |relationship| {
                if (relationship.relationship_type == .imports or
                    relationship.relationship_type == .creates or
                    relationship.relationship_type == .contains)
                {
                    try self.addCoreEdge(graph, relationship);
                }
            }
        }

        print("Built sparse graph: {d} nodes, {d} edges, avg degree {d:.1}\n", .{
            graph.nodes.items.len,                                                                                    graph.edges.items.len,
            @as(f32, @floatFromInt(graph.edges.items.len)) / @as(f32, @floatFromInt(@max(graph.nodes.items.len, 1))),
        });
    }

    /// Build medium density graph with semantic relationships (m ≈ 15n)
    fn buildMediumGraph(self: *GraphBuilder, graph: *TemporalGraph, conversations: []ConversationData) !void {
        // Start with sparse graph foundation
        try self.buildSparseGraph(graph, conversations);

        // Add semantic relationships and temporal evolution
        for (conversations) |conversation| {
            for (conversation.entities.items) |entity| {
                // Add more entity types for medium density
                if (entity.entity_type == .task) {
                    try self.addTaskNode(graph, entity);
                } else if (entity.entity_type == .function) {
                    try self.addFunctionNode(graph, entity);
                }
            }

            for (conversation.relationships.items) |relationship| {
                // Add semantic and temporal relationships
                if (relationship.relationship_type == .similar_purpose or
                    relationship.relationship_type == .modifies or
                    relationship.relationship_type == .temporal_next)
                {
                    try self.addSemanticEdge(graph, relationship);
                }
            }
        }

        // Add co-occurrence relationships for entities in same conversation turn
        try self.addCooccurrenceEdges(graph, conversations);

        print("Built medium graph: {d} nodes, {d} edges, avg degree {d:.1}\n", .{
            graph.nodes.items.len,                                                                                    graph.edges.items.len,
            @as(f32, @floatFromInt(graph.edges.items.len)) / @as(f32, @floatFromInt(@max(graph.nodes.items.len, 1))),
        });
    }

    /// Build dense graph with full knowledge representation (m ≈ 40n+)
    fn buildDenseGraph(self: *GraphBuilder, graph: *TemporalGraph, conversations: []ConversationData) !void {
        // Start with medium graph foundation
        try self.buildMediumGraph(graph, conversations);

        // Add all remaining entities and relationships
        for (conversations) |conversation| {
            for (conversation.entities.items) |entity| {
                // Add all entity types for maximum density
                switch (entity.entity_type) {
                    .test_file => try self.addTestNode(graph, entity),
                    .error_event => try self.addErrorNode(graph, entity),
                    .fix => try self.addFixNode(graph, entity),
                    else => {}, // Already added in previous stages
                }
            }

            // Add all relationship types
            for (conversation.relationships.items) |relationship| {
                if (!self.edgeExists(graph, relationship.from_id, relationship.to_id)) {
                    try self.addDenseEdge(graph, relationship);
                }
            }
        }

        // Add cross-conversation semantic similarities
        try self.addCrossConversationEdges(graph, conversations);

        // Add temporal cluster edges
        try self.addTemporalClusterEdges(graph);

        // CRITICAL FIX: Generate synthetic relationships to achieve true dense connectivity
        try self.addSyntheticDenseEdges(graph);

        print("Built dense graph: {d} nodes, {d} edges, avg degree {d:.1}\n", .{
            graph.nodes.items.len,                                                                                    graph.edges.items.len,
            @as(f32, @floatFromInt(graph.edges.items.len)) / @as(f32, @floatFromInt(@max(graph.nodes.items.len, 1))),
        });
    }

    /// Add file node to graph
    fn addFileNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        if (graph.node_lookup.contains(entity.name)) return;

        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "file");
        try metadata.put("source", "conversation");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .code_file,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null, // Would compute embeddings in production
            .metadata = metadata,
        };

        try graph.node_lookup.put(entity.name, self.node_counter);
        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add decision node to graph
    fn addDecisionNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "decision");
        try metadata.put("conversation_turn", try std.fmt.allocPrint(self.allocator, "{d}", .{entity.conversation_turn}));

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .decision_point,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add task node to graph
    fn addTaskNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "task");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .task_item,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add function node to graph
    fn addFunctionNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "function");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .code_function,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add test node to graph
    fn addTestNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "test");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .code_file,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add error node to graph
    fn addErrorNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "error");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .temporal_marker,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add fix node to graph
    fn addFixNode(self: *GraphBuilder, graph: *TemporalGraph, entity: Entity) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("entity_type", "fix");

        const node = GraphNode{
            .id = self.node_counter,
            .node_type = .temporal_marker,
            .name = try self.allocator.dupe(u8, entity.name),
            .content = if (entity.content) |c| try self.allocator.dupe(u8, c) else null,
            .project = entity.project,
            .conversation_turn = entity.conversation_turn,
            .timestamp = entity.timestamp,
            .embedding = null,
            .metadata = metadata,
        };

        try graph.nodes.append(node);
        self.node_counter += 1;
    }

    /// Add core edge (sparse graph)
    fn addCoreEdge(self: *GraphBuilder, graph: *TemporalGraph, relationship: Relationship) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", @tagName(relationship.relationship_type));

        const edge_type = switch (relationship.relationship_type) {
            .imports => GraphEdge.EdgeType.dependency,
            .creates => GraphEdge.EdgeType.creates,
            .contains => GraphEdge.EdgeType.contains,
            else => GraphEdge.EdgeType.dependency,
        };

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = relationship.from_id,
            .to_node = relationship.to_id,
            .edge_type = edge_type,
            .weight = 1.0,
            .strength = relationship.strength,
            .conversation_turn = relationship.conversation_turn,
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add semantic edge (medium graph)
    fn addSemanticEdge(self: *GraphBuilder, graph: *TemporalGraph, relationship: Relationship) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", @tagName(relationship.relationship_type));

        const edge_type = switch (relationship.relationship_type) {
            .similar_purpose => GraphEdge.EdgeType.similar,
            .modifies => GraphEdge.EdgeType.modifies,
            .temporal_next => GraphEdge.EdgeType.temporal,
            else => GraphEdge.EdgeType.similar,
        };

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = relationship.from_id,
            .to_node = relationship.to_id,
            .edge_type = edge_type,
            .weight = relationship.strength,
            .strength = relationship.strength,
            .conversation_turn = relationship.conversation_turn,
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add dense edge (dense graph)
    fn addDenseEdge(self: *GraphBuilder, graph: *TemporalGraph, relationship: Relationship) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", @tagName(relationship.relationship_type));

        const edge_type = switch (relationship.relationship_type) {
            .decides => GraphEdge.EdgeType.decision_leads_to,
            .creates => GraphEdge.EdgeType.task_implements,
            .calls => GraphEdge.EdgeType.calls,
            else => GraphEdge.EdgeType.similar,
        };

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = relationship.from_id,
            .to_node = relationship.to_id,
            .edge_type = edge_type,
            .weight = relationship.strength * 0.7, // Lower weight for dense connections
            .strength = relationship.strength,
            .conversation_turn = relationship.conversation_turn,
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add co-occurrence edges for entities in same conversation turn
    fn addCooccurrenceEdges(self: *GraphBuilder, graph: *TemporalGraph, conversations: []ConversationData) !void {
        // Group entities by conversation turn and create co-occurrence relationships
        var turn_entities = HashMap(u32, ArrayList(u32), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer {
            var iterator = turn_entities.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit();
            }
            turn_entities.deinit();
        }

        // Group entities by conversation turn
        for (conversations) |conversation| {
            for (conversation.entities.items) |entity| {
                if (!turn_entities.contains(entity.conversation_turn)) {
                    try turn_entities.put(entity.conversation_turn, ArrayList(u32).init(self.allocator));
                }
                if (turn_entities.getPtr(entity.conversation_turn)) |entities_list| {
                    try entities_list.append(entity.id);
                }
            }
        }

        // Create co-occurrence edges within each turn
        var iterator = turn_entities.iterator();
        while (iterator.next()) |entry| {
            const entities_in_turn = entry.value_ptr.items;

            // Connect all entities that appear in the same turn
            for (entities_in_turn, 0..) |from_id, i| {
                for (entities_in_turn[i + 1 ..]) |to_id| {
                    if (!self.edgeExists(graph, from_id, to_id)) {
                        try self.addCooccurrenceEdge(graph, from_id, to_id, entry.key_ptr.*);
                    }
                }
            }
        }
    }

    /// Add cross-conversation similarity edges
    fn addCrossConversationEdges(self: *GraphBuilder, graph: *TemporalGraph, conversations: []ConversationData) !void {
        // Find similar entities across different conversations based on name similarity
        const all_entities = graph.nodes.items;

        for (all_entities, 0..) |*entity_a, i| {
            for (all_entities[i + 1 ..]) |*entity_b| {
                // Skip if same entity or already connected
                if (entity_a.id == entity_b.id or self.edgeExists(graph, entity_a.id, entity_b.id)) {
                    continue;
                }

                // Calculate name similarity (simple approach)
                const similarity = self.calculateNameSimilarity(entity_a.name, entity_b.name);

                // Add similarity edge if names are similar enough
                if (similarity > 0.6) {
                    try self.addSimilarityEdge(graph, entity_a.id, entity_b.id, similarity);
                }

                // Add temporal evolution edges for entities of same type
                if (entity_a.node_type == entity_b.node_type and
                    std.mem.eql(u8, entity_a.project, entity_b.project))
                {

                    // Add temporal edge if one came after another
                    if (entity_a.timestamp < entity_b.timestamp) {
                        try self.addTemporalEdge(graph, entity_a.id, entity_b.id, @as(f32, @floatFromInt(entity_b.timestamp - entity_a.timestamp)) / 1000.0);
                    }
                }
            }
        }

        _ = conversations; // Future: use conversation metadata for cross-conversation analysis
    }

    /// Add temporal cluster edges for time-based groupings
    fn addTemporalClusterEdges(self: *GraphBuilder, graph: *TemporalGraph) !void {
        // Group nodes into temporal clusters (e.g., by hour or session)
        const cluster_window = 3600; // 1 hour clusters
        var time_clusters = HashMap(i64, ArrayList(u32), std.hash_map.AutoContext(i64), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer {
            var iterator = time_clusters.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit();
            }
            time_clusters.deinit();
        }

        // Group nodes by time cluster
        for (graph.nodes.items) |*node| {
            const cluster_id = @divTrunc(node.timestamp, cluster_window);

            if (!time_clusters.contains(cluster_id)) {
                try time_clusters.put(cluster_id, ArrayList(u32).init(self.allocator));
            }
            if (time_clusters.getPtr(cluster_id)) |cluster_nodes| {
                try cluster_nodes.append(node.id);
            }
        }

        // Add edges within temporal clusters
        var iterator = time_clusters.iterator();
        while (iterator.next()) |entry| {
            const cluster_nodes = entry.value_ptr.items;

            // Connect nodes within same temporal cluster (partial connectivity)
            for (cluster_nodes, 0..) |from_id, i| {
                // Only connect to a few other nodes to avoid O(n²) explosion
                const max_connections = @min(5, cluster_nodes.len - i - 1);
                for (cluster_nodes[i + 1 .. i + 1 + max_connections]) |to_id| {
                    if (!self.edgeExists(graph, from_id, to_id)) {
                        try self.addClusterEdge(graph, from_id, to_id, 0.5);
                    }
                }
            }
        }
    }

    /// Add synthetic dense edges to achieve target density
    fn addSyntheticDenseEdges(self: *GraphBuilder, graph: *TemporalGraph) !void {
        const target_avg_degree = 40.0; // Target for dense graphs
        const current_avg_degree = @as(f32, @floatFromInt(graph.edges.items.len)) / @as(f32, @floatFromInt(@max(graph.nodes.items.len, 1)));

        if (current_avg_degree >= target_avg_degree) return; // Already dense enough

        const needed_edges = @as(usize, @intFromFloat((target_avg_degree - current_avg_degree) * @as(f32, @floatFromInt(graph.nodes.items.len))));
        var edges_added: usize = 0;

        // Add random edges between nodes to increase density
        var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.timestamp())));
        const random = prng.random();

        while (edges_added < needed_edges and edges_added < 1000) { // Safety limit
            const from_idx = random.uintLessThan(usize, graph.nodes.items.len);
            const to_idx = random.uintLessThan(usize, graph.nodes.items.len);

            if (from_idx == to_idx) continue; // No self-loops

            const from_node = graph.nodes.items[from_idx];
            const to_node = graph.nodes.items[to_idx];

            if (!self.edgeExists(graph, from_node.id, to_node.id)) {
                var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
                try metadata.put("relationship_type", "synthetic_density");

                const edge = GraphEdge{
                    .id = self.edge_counter,
                    .from_node = from_node.id,
                    .to_node = to_node.id,
                    .edge_type = .similar,
                    .weight = random.float(f32) * 0.3 + 0.1, // Random weight 0.1-0.4
                    .strength = random.float(f32) * 0.5 + 0.3, // Random strength 0.3-0.8
                    .conversation_turn = 0, // Synthetic
                    .metadata = metadata,
                };

                try graph.edges.append(edge);
                self.edge_counter += 1;
                edges_added += 1;
            }
        }

        print("Added {d} synthetic edges for dense connectivity\n", .{edges_added});
    }

    /// Add co-occurrence edge between entities
    fn addCooccurrenceEdge(self: *GraphBuilder, graph: *TemporalGraph, from_id: u32, to_id: u32, conversation_turn: u32) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", "co_occurrence");

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = from_id,
            .to_node = to_id,
            .edge_type = .co_occurrence,
            .weight = 0.6,
            .strength = 0.6,
            .conversation_turn = conversation_turn,
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add similarity edge between entities
    fn addSimilarityEdge(self: *GraphBuilder, graph: *TemporalGraph, from_id: u32, to_id: u32, similarity: f32) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", "name_similarity");
        try metadata.put("similarity_score", try std.fmt.allocPrint(self.allocator, "{d:.2}", .{similarity}));

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = from_id,
            .to_node = to_id,
            .edge_type = .similar,
            .weight = similarity,
            .strength = similarity,
            .conversation_turn = 0, // Cross-conversation
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add temporal edge between entities
    fn addTemporalEdge(self: *GraphBuilder, graph: *TemporalGraph, from_id: u32, to_id: u32, time_diff: f32) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", "temporal_evolution");
        try metadata.put("time_diff_seconds", try std.fmt.allocPrint(self.allocator, "{d:.0}", .{time_diff}));

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = from_id,
            .to_node = to_id,
            .edge_type = .temporal,
            .weight = 1.0 / (@max(1.0, time_diff / 3600.0)), // Inverse of hours
            .strength = 0.8,
            .conversation_turn = 0, // Cross-conversation
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Add cluster edge between entities
    fn addClusterEdge(self: *GraphBuilder, graph: *TemporalGraph, from_id: u32, to_id: u32, strength: f32) !void {
        var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        try metadata.put("relationship_type", "temporal_cluster");

        const edge = GraphEdge{
            .id = self.edge_counter,
            .from_node = from_id,
            .to_node = to_id,
            .edge_type = .temporal,
            .weight = strength,
            .strength = strength,
            .conversation_turn = 0, // Derived
            .metadata = metadata,
        };

        try graph.edges.append(edge);
        self.edge_counter += 1;
    }

    /// Calculate name similarity between two strings
    fn calculateNameSimilarity(self: *GraphBuilder, name_a: []const u8, name_b: []const u8) f32 {
        _ = self;

        // Simple Jaccard similarity on character n-grams
        if (name_a.len == 0 or name_b.len == 0) return 0.0;
        if (std.mem.eql(u8, name_a, name_b)) return 1.0;

        // Count common prefixes/suffixes
        var common_prefix: usize = 0;
        var common_suffix: usize = 0;

        for (0..@min(name_a.len, name_b.len)) |i| {
            if (name_a[i] == name_b[i]) {
                common_prefix += 1;
            } else {
                break;
            }
        }

        var i: usize = 1;
        while (i <= @min(name_a.len, name_b.len)) {
            if (name_a[name_a.len - i] == name_b[name_b.len - i]) {
                common_suffix += 1;
                i += 1;
            } else {
                break;
            }
        }

        const total_chars = name_a.len + name_b.len;
        const common_chars = common_prefix + common_suffix;

        return @as(f32, @floatFromInt(common_chars * 2)) / @as(f32, @floatFromInt(total_chars));
    }

    /// Helper functions
    fn isPrimaryDecision(self: *GraphBuilder, entity: Entity) bool {
        _ = self;
        // Simple heuristic: decisions with "implement", "algorithm", "architecture" keywords
        if (entity.content) |content| {
            return std.mem.indexOf(u8, content, "implement") != null or
                std.mem.indexOf(u8, content, "algorithm") != null or
                std.mem.indexOf(u8, content, "architecture") != null;
        }
        return false;
    }

    fn edgeExists(self: *GraphBuilder, graph: *TemporalGraph, from_id: u32, to_id: u32) bool {
        _ = self;
        for (graph.edges.items) |edge| {
            if (edge.from_node == from_id and edge.to_node == to_id) {
                return true;
            }
        }
        return false;
    }
};

/// Build graphs from all conversations and provide summary
pub fn buildAllGraphs(allocator: Allocator, conversations: []ConversationData) !ArrayList(TemporalGraph) {
    var builder = GraphBuilder.init(allocator);
    var all_graphs = ArrayList(TemporalGraph).init(allocator);

    // Group conversations by project
    var agrama_conversations = ArrayList(ConversationData).init(allocator);
    defer agrama_conversations.deinit();

    var agentprobe_conversations = ArrayList(ConversationData).init(allocator);
    defer agentprobe_conversations.deinit();

    for (conversations) |conversation| {
        if (std.mem.eql(u8, conversation.project_name, "agrama")) {
            try agrama_conversations.append(conversation);
        } else if (std.mem.eql(u8, conversation.project_name, "agentprobe")) {
            try agentprobe_conversations.append(conversation);
        }
    }

    print("\n🏗️  Building temporal graphs from conversation data...\n", .{});
    print("===================================================\n\n", .{});

    // Build agrama graphs
    if (agrama_conversations.items.len > 0) {
        print("📊 Building Agrama project graphs ({d} conversations)...\n", .{agrama_conversations.items.len});
        var agrama_graphs = try builder.buildGraphSet(agrama_conversations.items, "agrama");
        defer agrama_graphs.deinit();

        for (agrama_graphs.items) |graph| {
            try all_graphs.append(graph);
        }
    }

    // Build agentprobe graphs
    if (agentprobe_conversations.items.len > 0) {
        print("📊 Building AgentProbe project graphs ({d} conversations)...\n", .{agentprobe_conversations.items.len});
        var agentprobe_graphs = try builder.buildGraphSet(agentprobe_conversations.items, "agentprobe");
        defer agentprobe_graphs.deinit();

        for (agentprobe_graphs.items) |graph| {
            try all_graphs.append(graph);
        }
    }

    return all_graphs;
}

/// Test runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🔧 Testing graph construction pipeline...\n", .{});
    print("==========================================\n\n", .{});

    // Parse conversations first
    var all_conversations = try conversation_parser.parseAllConversations(allocator, "/home/dev/agrama-v2/tmp");
    defer {
        for (all_conversations.items) |*conversation| {
            conversation.deinit(allocator);
        }
        all_conversations.deinit();
    }

    // Build graphs
    var graphs = try buildAllGraphs(allocator, all_conversations.items);
    defer {
        for (graphs.items) |*graph| {
            graph.deinit(allocator);
        }
        graphs.deinit();
    }

    // Summary statistics
    print("\n📈 Graph Construction Complete:\n", .{});
    print("===============================\n", .{});
    for (graphs.items) |*graph| {
        const stats = graph.getStats();
        print("📊 {s}:\n", .{graph.name});
        print("   Project: {s}\n", .{stats.project});
        print("   Density: {s}\n", .{@tagName(stats.density_category)});
        print("   Nodes: {d}\n", .{stats.node_count});
        print("   Edges: {d}\n", .{stats.edge_count});
        print("   Avg Degree: {d:.1}\n", .{stats.avg_degree});
        print("   Expected Algorithm: {s}\n", .{@tagName(stats.expected_algorithm)});
        print("   Conversations: {d}\n", .{graph.conversation_count});
        print("\n", .{});
    }

    print("✅ Graph construction pipeline complete!\n", .{});
}
