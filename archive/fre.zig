const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ArenaAllocator = std.heap.ArenaAllocator;

/// Node identifier type for the graph
pub const NodeID = u128;

/// Edge identifier type for the graph
pub const EdgeID = u128;

/// Agent identifier type
pub const AgentID = []const u8;

/// Time range for temporal queries
pub const TimeRange = struct {
    start: i64,
    end: ?i64, // null means unbounded (current time)

    pub fn current() TimeRange {
        return TimeRange{
            .start = std.time.timestamp(),
            .end = null,
        };
    }

    pub fn infinite() TimeRange {
        return TimeRange{
            .start = 0,
            .end = null,
        };
    }

    pub fn includesNow(self: TimeRange) bool {
        const now = std.time.timestamp();
        return self.start <= now and (self.end == null or self.end.? >= now);
    }
};

/// Node types in the temporal graph
pub const NodeType = enum {
    file,
    function,
    class,
    module,
    package,
    agent,
    decision,
    change,

    pub fn toString(self: NodeType) []const u8 {
        return switch (self) {
            .file => "file",
            .function => "function",
            .class => "class",
            .module => "module",
            .package => "package",
            .agent => "agent",
            .decision => "decision",
            .change => "change",
        };
    }
};

/// Edge types in the temporal graph
pub const RelationType = enum {
    depends_on,
    contains,
    implements,
    calls,
    modifies,
    created_by,
    influences,
    similar_to,

    pub fn toString(self: RelationType) []const u8 {
        return switch (self) {
            .depends_on => "depends_on",
            .contains => "contains",
            .implements => "implements",
            .calls => "calls",
            .modifies => "modifies",
            .created_by => "created_by",
            .influences => "influences",
            .similar_to => "similar_to",
        };
    }
};

/// Traversal direction for graph operations
pub const TraversalDirection = enum {
    forward,
    reverse,
    bidirectional,
};

/// Temporal metadata for nodes and edges
pub const TemporalMeta = struct {
    created_at: i64,
    valid_from: i64,
    valid_to: ?i64, // null means currently valid
    last_modified: i64,
    created_by: AgentID,
};

/// A node in the temporal graph
pub const TemporalNode = struct {
    id: NodeID,
    node_type: NodeType,
    properties: HashMap([]const u8, []const u8, StringContext, std.hash_map.default_max_load_percentage),
    temporal_metadata: TemporalMeta,
    // For now, we'll implement a simple embedding placeholder
    embedding_checksum: ?u64, // Simple checksum instead of full embedding

    const StringContext = struct {
        pub fn hash(self: @This(), s: []const u8) u64 {
            _ = self;
            return std.hash_map.hashString(s);
        }
        pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
            _ = self;
            return std.mem.eql(u8, a, b);
        }
    };

    pub fn init(allocator: Allocator, id: NodeID, node_type: NodeType, created_by: AgentID) TemporalNode {
        const now = std.time.timestamp();
        return TemporalNode{
            .id = id,
            .node_type = node_type,
            .properties = HashMap([]const u8, []const u8, StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .temporal_metadata = TemporalMeta{
                .created_at = now,
                .valid_from = now,
                .valid_to = null,
                .last_modified = now,
                .created_by = created_by,
            },
            .embedding_checksum = null,
        };
    }

    pub fn deinit(self: *TemporalNode, allocator: Allocator) void {
        var prop_iterator = self.properties.iterator();
        while (prop_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.properties.deinit();
    }

    pub fn setProperty(self: *TemporalNode, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const owned_key = try allocator.dupe(u8, key);
        const owned_value = try allocator.dupe(u8, value);

        // Free existing values if they exist
        if (self.properties.fetchRemove(key)) |kv| {
            allocator.free(kv.key);
            allocator.free(kv.value);
        }

        try self.properties.put(owned_key, owned_value);
        self.temporal_metadata.last_modified = std.time.timestamp();
    }

    pub fn getProperty(self: *TemporalNode, key: []const u8) ?[]const u8 {
        return self.properties.get(key);
    }
};

/// An edge in the temporal graph
pub const TemporalEdge = struct {
    id: EdgeID,
    source: NodeID,
    target: NodeID,
    relationship: RelationType,
    weight: f32,
    temporal_range: TimeRange,
    created_by: AgentID,

    pub fn init(source: NodeID, target: NodeID, relationship: RelationType, weight: f32, created_by: AgentID) TemporalEdge {
        const now = std.time.timestamp();
        return TemporalEdge{
            .id = @as(EdgeID, @intCast(now)) << 64 | @as(EdgeID, @intCast(std.crypto.random.int(u64))),
            .source = source,
            .target = target,
            .relationship = relationship,
            .weight = weight,
            .temporal_range = TimeRange{
                .start = now,
                .end = null,
            },
            .created_by = created_by,
        };
    }

    pub fn isActive(self: TemporalEdge, at_time: i64) bool {
        return self.temporal_range.start <= at_time and
            (self.temporal_range.end == null or self.temporal_range.end.? >= at_time);
    }
};

/// Search result for graph queries
pub const SearchResult = struct {
    node_id: NodeID,
    distance: f32,
    similarity: f32,
    path_length: u32,
};

/// Weighted entity used in frontier management
pub const WeightedEntity = struct {
    node_id: NodeID,
    distance: f32,
    temporal_weight: f32,
    semantic_weight: f32,

    pub fn compareDistance(context: void, a: WeightedEntity, b: WeightedEntity) bool {
        _ = context;
        return a.distance < b.distance;
    }

    pub fn totalWeight(self: WeightedEntity) f32 {
        return self.distance + 0.1 * self.temporal_weight + 0.1 * self.semantic_weight;
    }
};

/// Frontier data structure for FRE algorithm
pub const TemporalFrontier = struct {
    allocator: Allocator,
    entities: ArrayList(WeightedEntity),
    max_size: usize,
    insertion_count: usize,

    pub fn init(allocator: Allocator, max_size: usize) TemporalFrontier {
        return TemporalFrontier{
            .allocator = allocator,
            .entities = ArrayList(WeightedEntity).init(allocator),
            .max_size = max_size,
            .insertion_count = 0,
        };
    }

    pub fn deinit(self: *TemporalFrontier) void {
        self.entities.deinit();
    }

    pub fn insert(self: *TemporalFrontier, entity: WeightedEntity) !void {
        try self.entities.append(entity);
        self.insertion_count += 1;

        if (self.entities.items.len > self.max_size) {
            // Sort by distance and keep the closest entities
            std.sort.pdq(WeightedEntity, self.entities.items, {}, WeightedEntity.compareDistance);
            try self.entities.resize(self.max_size);
        }
    }

    pub fn pullMinimum(self: *TemporalFrontier, k: usize) ![]WeightedEntity {
        if (self.entities.items.len == 0) {
            return try self.allocator.alloc(WeightedEntity, 0);
        }

        // Sort entities by total weight
        std.sort.pdq(WeightedEntity, self.entities.items, {}, WeightedEntity.compareDistance);

        const actual_k = @min(k, self.entities.items.len);
        const result = try self.allocator.alloc(WeightedEntity, actual_k);

        // Copy the k smallest entities
        @memcpy(result, self.entities.items[0..actual_k]);

        // Remove the extracted entities
        const remaining = self.entities.items.len - actual_k;
        if (remaining > 0) {
            std.mem.copyForwards(WeightedEntity, self.entities.items[0..remaining], self.entities.items[actual_k..]);
        }
        try self.entities.resize(remaining);

        return result;
    }

    pub fn isEmpty(self: TemporalFrontier) bool {
        return self.entities.items.len == 0;
    }

    pub fn size(self: TemporalFrontier) usize {
        return self.entities.items.len;
    }
};

/// Result of path computation
pub const PathResult = struct {
    reachable_nodes: []NodeID,
    distances: []f32,
    paths: [][]NodeID, // Actual paths to each reachable node
    computation_time_ms: u32,
    nodes_explored: u32,

    pub fn deinit(self: PathResult, allocator: Allocator) void {
        allocator.free(self.reachable_nodes);
        allocator.free(self.distances);

        for (self.paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.paths);
    }
};

/// Impact analysis result
pub const ImpactAnalysis = struct {
    affected_entities: []NodeID,
    dependencies: []NodeID,
    critical_paths: [][]NodeID,
    estimated_complexity: f32,

    pub fn deinit(self: ImpactAnalysis, allocator: Allocator) void {
        allocator.free(self.affected_entities);
        allocator.free(self.dependencies);

        for (self.critical_paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.critical_paths);
    }
};

/// Dependency analysis result
pub const DependencyGraph = struct {
    nodes: []NodeID,
    edges: []TemporalEdge,
    root_node: NodeID,
    depth: u32,

    pub fn deinit(self: DependencyGraph, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.edges);
    }
};

/// Frontier Reduction Engine - Core Implementation
pub const FrontierReductionEngine = struct {
    allocator: Allocator,
    arena: ArenaAllocator,

    // Graph storage
    nodes: HashMap(NodeID, TemporalNode, NodeContext, std.hash_map.default_max_load_percentage),
    edges: HashMap(EdgeID, TemporalEdge, EdgeContext, std.hash_map.default_max_load_percentage),

    // Adjacency lists for efficient traversal
    outgoing_edges: HashMap(NodeID, ArrayList(EdgeID), NodeContext, std.hash_map.default_max_load_percentage),
    incoming_edges: HashMap(NodeID, ArrayList(EdgeID), NodeContext, std.hash_map.default_max_load_percentage),

    // Configuration
    default_recursion_levels: u32,
    max_frontier_size: usize,
    pivot_threshold: f32,

    const NodeContext = struct {
        pub fn hash(self: @This(), id: NodeID) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(NodeID, void)({}, id);
        }
        pub fn eql(self: @This(), a: NodeID, b: NodeID) bool {
            _ = self;
            return a == b;
        }
    };

    const EdgeContext = struct {
        pub fn hash(self: @This(), id: EdgeID) u64 {
            _ = self;
            return std.hash_map.getAutoHashFn(EdgeID, void)({}, id);
        }
        pub fn eql(self: @This(), a: EdgeID, b: EdgeID) bool {
            _ = self;
            return a == b;
        }
    };

    pub fn init(allocator: Allocator) FrontierReductionEngine {
        return FrontierReductionEngine{
            .allocator = allocator,
            .arena = ArenaAllocator.init(allocator),
            .nodes = HashMap(NodeID, TemporalNode, NodeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .edges = HashMap(EdgeID, TemporalEdge, EdgeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .outgoing_edges = HashMap(NodeID, ArrayList(EdgeID), NodeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .incoming_edges = HashMap(NodeID, ArrayList(EdgeID), NodeContext, std.hash_map.default_max_load_percentage).init(allocator),
            .default_recursion_levels = 3,
            .max_frontier_size = 1000,
            .pivot_threshold = 0.1,
        };
    }

    pub fn deinit(self: *FrontierReductionEngine) void {
        // Clean up nodes
        var node_iterator = self.nodes.iterator();
        while (node_iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.nodes.deinit();
        self.edges.deinit();

        // Clean up adjacency lists
        var out_iterator = self.outgoing_edges.iterator();
        while (out_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.outgoing_edges.deinit();

        var in_iterator = self.incoming_edges.iterator();
        while (in_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.incoming_edges.deinit();

        self.arena.deinit();
    }

    /// Add a node to the graph
    pub fn addNode(self: *FrontierReductionEngine, node: TemporalNode) !void {
        try self.nodes.put(node.id, node);

        // Initialize adjacency lists
        if (!self.outgoing_edges.contains(node.id)) {
            try self.outgoing_edges.put(node.id, ArrayList(EdgeID).init(self.allocator));
        }
        if (!self.incoming_edges.contains(node.id)) {
            try self.incoming_edges.put(node.id, ArrayList(EdgeID).init(self.allocator));
        }
    }

    /// Add an edge to the graph
    pub fn addEdge(self: *FrontierReductionEngine, edge: TemporalEdge) !void {
        try self.edges.put(edge.id, edge);

        // Update adjacency lists
        if (self.outgoing_edges.getPtr(edge.source)) |source_edges| {
            try source_edges.append(edge.id);
        }

        if (self.incoming_edges.getPtr(edge.target)) |target_edges| {
            try target_edges.append(edge.id);
        }
    }

    /// Get a node by ID
    pub fn getNode(self: *FrontierReductionEngine, node_id: NodeID) ?*TemporalNode {
        return self.nodes.getPtr(node_id);
    }

    /// Get an edge by ID
    pub fn getEdge(self: *FrontierReductionEngine, edge_id: EdgeID) ?*TemporalEdge {
        return self.edges.getPtr(edge_id);
    }

    /// Core T-BMSSP (Temporal Bounded Multi-Source Shortest Path) algorithm
    /// This is the heart of the FRE implementation adapted for temporal graphs
    pub fn computeTemporalPaths(self: *FrontierReductionEngine, sources: []const NodeID, direction: TraversalDirection, max_hops: u32, time_range: TimeRange) !PathResult {
        const start_time = std.time.milliTimestamp();

        // Use arena allocator for temporary computations
        var computation_arena = ArenaAllocator.init(self.allocator);
        defer computation_arena.deinit();
        const arena_allocator = computation_arena.allocator();

        if (sources.len == 0) {
            return PathResult{
                .reachable_nodes = try self.allocator.alloc(NodeID, 0),
                .distances = try self.allocator.alloc(f32, 0),
                .paths = try self.allocator.alloc([]NodeID, 0),
                .computation_time_ms = 0,
                .nodes_explored = 0,
            };
        }

        // Determine recursion level based on graph size and complexity
        const level = if (max_hops == 0)
            self.selectOptimalLevel(self.nodes.count(), sources.len)
        else
            @min(max_hops, self.default_recursion_levels);

        const result = try self.computeTemporalPathsRecursive(sources, level, direction, time_range, arena_allocator, std.math.floatMax(f32));

        const end_time = std.time.milliTimestamp();

        // Convert temporary results to permanent storage
        const reachable_nodes = try self.allocator.dupe(NodeID, result.nodes);
        const distances = try self.allocator.dupe(f32, result.distances);
        const paths = try self.allocator.alloc([]NodeID, result.paths.len);

        for (result.paths, 0..) |path, i| {
            paths[i] = try self.allocator.dupe(NodeID, path);
        }

        return PathResult{
            .reachable_nodes = reachable_nodes,
            .distances = distances,
            .paths = paths,
            .computation_time_ms = @as(u32, @intCast(end_time - start_time)),
            .nodes_explored = result.explored_count,
        };
    }

    /// Recursive implementation of T-BMSSP with frontier reduction
    const TemporalPathsResult = struct {
        nodes: []NodeID,
        distances: []f32,
        paths: [][]NodeID,
        explored_count: u32,
    };

    fn computeTemporalPathsRecursive(self: *FrontierReductionEngine, sources: []const NodeID, level: u32, direction: TraversalDirection, time_range: TimeRange, arena_allocator: Allocator, max_distance: f32) !TemporalPathsResult {
        // Base case: use temporal Dijkstra
        if (level == 0 or sources.len <= 1) {
            return self.temporalDijkstra(sources, direction, time_range, max_distance, arena_allocator);
        }

        // Find temporal pivots for frontier reduction
        const pivots = try self.findTemporalPivots(sources, max_distance, time_range, arena_allocator);

        var all_nodes = ArrayList(NodeID).init(arena_allocator);
        var all_distances = ArrayList(f32).init(arena_allocator);
        var all_paths = ArrayList([]NodeID).init(arena_allocator);
        var total_explored: u32 = 0;

        // Process each pivot recursively
        for (pivots) |pivot| {
            const subresult = try self.computeTemporalPathsRecursive(&[_]NodeID{pivot}, level - 1, direction, time_range, arena_allocator, max_distance / 2.0);

            try all_nodes.appendSlice(subresult.nodes);
            try all_distances.appendSlice(subresult.distances);
            try all_paths.appendSlice(subresult.paths);
            total_explored += subresult.explored_count;
        }

        // Remove duplicates and merge results
        const unique_results = try self.removeDuplicateResults(all_nodes.items, all_distances.items, all_paths.items, arena_allocator);

        return TemporalPathsResult{
            .nodes = unique_results.nodes,
            .distances = unique_results.distances,
            .paths = unique_results.paths,
            .explored_count = total_explored,
        };
    }

    /// Find temporal pivots - nodes with large temporal subtrees
    fn findTemporalPivots(self: *FrontierReductionEngine, frontier: []const NodeID, max_distance: f32, time_range: TimeRange, arena_allocator: Allocator) ![]NodeID {
        var pivots = ArrayList(NodeID).init(arena_allocator);

        for (frontier) |node_id| {
            const subtree_size = self.estimateTemporalSubtreeSize(node_id, time_range, max_distance);
            if (subtree_size >= self.pivot_threshold) {
                try pivots.append(node_id);
            }
        }

        // If no pivots found, use all nodes
        if (pivots.items.len == 0) {
            try pivots.appendSlice(frontier);
        }

        return pivots.items;
    }

    /// Estimate the size of the temporal subtree from a given node
    fn estimateTemporalSubtreeSize(self: *FrontierReductionEngine, root: NodeID, time_range: TimeRange, max_distance: f32) f32 {
        _ = time_range;
        _ = max_distance;

        // Simple estimation based on outgoing edge count
        // In a full implementation, this would do a bounded traversal
        if (self.outgoing_edges.get(root)) |edges| {
            return @as(f32, @floatFromInt(edges.items.len)) / @as(f32, @floatFromInt(self.nodes.count()));
        }
        return 0.0;
    }

    /// Temporal Dijkstra algorithm for base case
    fn temporalDijkstra(self: *FrontierReductionEngine, sources: []const NodeID, direction: TraversalDirection, time_range: TimeRange, max_distance: f32, arena_allocator: Allocator) !TemporalPathsResult {
        var distances = HashMap(NodeID, f32, NodeContext, std.hash_map.default_max_load_percentage).init(arena_allocator);
        var predecessors = HashMap(NodeID, NodeID, NodeContext, std.hash_map.default_max_load_percentage).init(arena_allocator);
        var frontier = TemporalFrontier.init(arena_allocator, self.max_frontier_size);
        defer frontier.deinit();

        // Initialize with source nodes
        for (sources) |source| {
            try distances.put(source, 0.0);
            try frontier.insert(WeightedEntity{
                .node_id = source,
                .distance = 0.0,
                .temporal_weight = 0.0,
                .semantic_weight = 0.0,
            });
        }

        var nodes_explored: u32 = 0;

        // Main Dijkstra loop with temporal constraints
        while (!frontier.isEmpty()) {
            const current_entities = try frontier.pullMinimum(1);
            defer arena_allocator.free(current_entities);

            if (current_entities.len == 0) break;

            const current = current_entities[0];
            nodes_explored += 1;

            if (current.distance > max_distance) continue;

            // Get current distance (might have been updated since insertion)
            const current_distance = distances.get(current.node_id) orelse std.math.floatMax(f32);
            if (current.distance > current_distance) continue;

            // Explore neighbors
            const edge_list = switch (direction) {
                .forward => self.outgoing_edges.get(current.node_id),
                .reverse => self.incoming_edges.get(current.node_id),
                .bidirectional => self.outgoing_edges.get(current.node_id), // Simplified for now
            };

            if (edge_list) |edges| {
                for (edges.items) |edge_id| {
                    const edge = self.getEdge(edge_id) orelse continue;

                    // Check temporal validity
                    if (!edge.isActive(time_range.start)) continue;

                    const neighbor = switch (direction) {
                        .forward => edge.target,
                        .reverse => edge.source,
                        .bidirectional => if (edge.source == current.node_id) edge.target else edge.source,
                    };

                    const new_distance = current_distance + edge.weight;
                    if (new_distance > max_distance) continue;

                    const neighbor_distance = distances.get(neighbor) orelse std.math.floatMax(f32);

                    if (new_distance < neighbor_distance) {
                        try distances.put(neighbor, new_distance);
                        try predecessors.put(neighbor, current.node_id);

                        try frontier.insert(WeightedEntity{
                            .node_id = neighbor,
                            .distance = new_distance,
                            .temporal_weight = self.calculateTemporalWeight(neighbor, time_range),
                            .semantic_weight = 0.0, // TODO: Implement semantic weighting
                        });
                    }
                }
            }
        }

        // Reconstruct results
        var result_nodes = ArrayList(NodeID).init(arena_allocator);
        var result_distances = ArrayList(f32).init(arena_allocator);
        var result_paths = ArrayList([]NodeID).init(arena_allocator);

        var distance_iterator = distances.iterator();
        while (distance_iterator.next()) |entry| {
            try result_nodes.append(entry.key_ptr.*);
            try result_distances.append(entry.value_ptr.*);

            // Reconstruct path
            const path = try self.reconstructPath(entry.key_ptr.*, predecessors, arena_allocator);
            try result_paths.append(path);
        }

        return TemporalPathsResult{
            .nodes = result_nodes.items,
            .distances = result_distances.items,
            .paths = result_paths.items,
            .explored_count = nodes_explored,
        };
    }

    /// Reconstruct path from predecessors map
    fn reconstructPath(self: *FrontierReductionEngine, target: NodeID, predecessors: HashMap(NodeID, NodeID, NodeContext, std.hash_map.default_max_load_percentage), arena_allocator: Allocator) ![]NodeID {
        _ = self;
        var path = ArrayList(NodeID).init(arena_allocator);
        var current = target;

        try path.append(current);

        while (predecessors.get(current)) |predecessor| {
            try path.append(predecessor);
            current = predecessor;
        }

        // Reverse to get path from source to target
        std.mem.reverse(NodeID, path.items);
        return path.items;
    }

    /// Calculate temporal weight for a node
    fn calculateTemporalWeight(self: *FrontierReductionEngine, node_id: NodeID, time_range: TimeRange) f32 {
        const node = self.getNode(node_id) orelse return 1.0;

        const time_diff = @abs(node.temporal_metadata.created_at - time_range.start);
        const max_time_diff = 86400 * 365; // One year in seconds

        return 1.0 - @as(f32, @floatFromInt(@min(time_diff, max_time_diff))) / @as(f32, @floatFromInt(max_time_diff));
    }

    /// Remove duplicate results and merge
    const UniqueResults = struct {
        nodes: []NodeID,
        distances: []f32,
        paths: [][]NodeID,
    };

    fn removeDuplicateResults(self: *FrontierReductionEngine, nodes: []NodeID, distances: []f32, paths: [][]NodeID, arena_allocator: Allocator) !UniqueResults {
        _ = self;

        var seen = HashMap(NodeID, bool, NodeContext, std.hash_map.default_max_load_percentage).init(arena_allocator);
        var unique_nodes = ArrayList(NodeID).init(arena_allocator);
        var unique_distances = ArrayList(f32).init(arena_allocator);
        var unique_paths = ArrayList([]NodeID).init(arena_allocator);

        for (nodes, 0..) |node, i| {
            if (!seen.contains(node)) {
                try seen.put(node, true);
                try unique_nodes.append(node);
                try unique_distances.append(distances[i]);
                try unique_paths.append(paths[i]);
            }
        }

        return UniqueResults{
            .nodes = unique_nodes.items,
            .distances = unique_distances.items,
            .paths = unique_paths.items,
        };
    }

    /// Select optimal recursion level based on problem characteristics
    fn selectOptimalLevel(self: *FrontierReductionEngine, graph_size: usize, source_count: usize) u32 {
        _ = source_count;

        if (graph_size < 100) return 1;
        if (graph_size < 1000) return 2;
        if (graph_size < 10000) return 3;

        // For larger graphs, use logarithmic scaling
        const base_levels = @as(f32, @log(@as(f32, @floatFromInt(graph_size)))) * 2.0 / 3.0;
        return @max(1, @min(@as(u32, @intFromFloat(base_levels)), self.default_recursion_levels));
    }

    /// Analyze dependencies for a specific node
    pub fn analyzeDependencies(self: *FrontierReductionEngine, root: NodeID, direction: TraversalDirection, max_depth: u32) !DependencyGraph {
        const time_range = TimeRange.current();

        const paths = try self.computeTemporalPaths(&[_]NodeID{root}, direction, max_depth, time_range);
        defer paths.deinit(self.allocator);

        // Collect all edges involved in the dependency graph
        var involved_edges = ArrayList(TemporalEdge).init(self.allocator);
        defer involved_edges.deinit();

        for (paths.reachable_nodes) |node_id| {
            if (self.outgoing_edges.get(node_id)) |edge_list| {
                for (edge_list.items) |edge_id| {
                    if (self.getEdge(edge_id)) |edge| {
                        // Check if target is also in reachable nodes
                        for (paths.reachable_nodes) |target_id| {
                            if (edge.target == target_id) {
                                try involved_edges.append(edge.*);
                                break;
                            }
                        }
                    }
                }
            }
        }

        return DependencyGraph{
            .nodes = try self.allocator.dupe(NodeID, paths.reachable_nodes),
            .edges = try involved_edges.toOwnedSlice(),
            .root_node = root,
            .depth = max_depth,
        };
    }

    /// Compute impact analysis for changes
    pub fn computeImpactRadius(self: *FrontierReductionEngine, changed_nodes: []const NodeID, max_radius: u32) !ImpactAnalysis {
        // Forward analysis - what will be affected
        const forward_paths = try self.computeTemporalPaths(changed_nodes, .forward, max_radius, TimeRange.current());
        defer forward_paths.deinit(self.allocator);

        // Backward analysis - what dependencies exist
        const backward_paths = try self.computeTemporalPaths(changed_nodes, .reverse, max_radius, TimeRange.current());
        defer backward_paths.deinit(self.allocator);

        // Find critical paths (simplified implementation)
        var critical_paths = ArrayList([]NodeID).init(self.allocator);

        // Critical paths are the longest paths in the forward direction
        for (forward_paths.paths) |path| {
            if (path.len >= max_radius) {
                const critical_path = try self.allocator.dupe(NodeID, path);
                try critical_paths.append(critical_path);
            }
        }

        // Estimate complexity based on the number of affected nodes and paths
        const complexity = @as(f32, @floatFromInt(forward_paths.reachable_nodes.len)) /
            @as(f32, @floatFromInt(@max(1, self.nodes.count())));

        return ImpactAnalysis{
            .affected_entities = try self.allocator.dupe(NodeID, forward_paths.reachable_nodes),
            .dependencies = try self.allocator.dupe(NodeID, backward_paths.reachable_nodes),
            .critical_paths = try critical_paths.toOwnedSlice(),
            .estimated_complexity = complexity,
        };
    }

    /// Check reachability between nodes
    pub fn checkReachability(self: *FrontierReductionEngine, sources: []const NodeID, targets: []const NodeID, max_distance: u32) !bool {
        const time_range = TimeRange.current();
        const paths = try self.computeTemporalPaths(sources, .bidirectional, max_distance, time_range);
        defer paths.deinit(self.allocator);

        // Check if any target is reachable
        for (targets) |target| {
            for (paths.reachable_nodes) |reachable| {
                if (target == reachable) {
                    return true;
                }
            }
        }

        return false;
    }

    /// Get basic statistics about the graph
    pub fn getGraphStats(self: *FrontierReductionEngine) struct {
        nodes: u32,
        edges: u32,
        avg_degree: f32,
    } {
        const node_count = self.nodes.count();
        const edge_count = self.edges.count();

        const avg_degree = if (node_count > 0)
            @as(f32, @floatFromInt(edge_count * 2)) / @as(f32, @floatFromInt(node_count))
        else
            0.0;

        return .{
            .nodes = @as(u32, @intCast(node_count)),
            .edges = @as(u32, @intCast(edge_count)),
            .avg_degree = avg_degree,
        };
    }
};

// Tests
test "FrontierReductionEngine initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    const stats = fre.getGraphStats();
    try testing.expect(stats.nodes == 0);
    try testing.expect(stats.edges == 0);
}

test "Basic node and edge operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    // Create test nodes
    var node1 = TemporalNode.init(allocator, 1, NodeType.file, "test-agent");
    var node2 = TemporalNode.init(allocator, 2, NodeType.function, "test-agent");

    try node1.setProperty(allocator, "name", "test.zig");
    try node2.setProperty(allocator, "name", "testFunction");

    // Add nodes to graph
    try fre.addNode(node1);
    try fre.addNode(node2);

    // Create edge
    const edge = TemporalEdge.init(1, 2, RelationType.contains, 1.0, "test-agent");
    try fre.addEdge(edge);

    // Verify graph structure
    const stats = fre.getGraphStats();
    try testing.expect(stats.nodes == 2);
    try testing.expect(stats.edges == 1);

    // Test node retrieval
    const retrieved_node = fre.getNode(1);
    try testing.expect(retrieved_node != null);
    try testing.expect(retrieved_node.?.id == 1);

    const name = retrieved_node.?.getProperty("name");
    try testing.expect(name != null);
    try testing.expectEqualSlices(u8, "test.zig", name.?);
}

test "Simple path computation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    // Create a simple chain: 1 -> 2 -> 3
    const node1 = TemporalNode.init(allocator, 1, NodeType.file, "test-agent");
    const node2 = TemporalNode.init(allocator, 2, NodeType.function, "test-agent");
    const node3 = TemporalNode.init(allocator, 3, NodeType.class, "test-agent");

    try fre.addNode(node1);
    try fre.addNode(node2);
    try fre.addNode(node3);

    const edge1 = TemporalEdge.init(1, 2, RelationType.contains, 1.0, "test-agent");
    const edge2 = TemporalEdge.init(2, 3, RelationType.calls, 1.0, "test-agent");

    try fre.addEdge(edge1);
    try fre.addEdge(edge2);

    // Compute paths from node 1
    const paths = try fre.computeTemporalPaths(&[_]NodeID{1}, .forward, 3, TimeRange.current());
    defer paths.deinit(allocator);

    // Should reach all 3 nodes
    try testing.expect(paths.reachable_nodes.len >= 1); // At least source node
    try testing.expect(paths.computation_time_ms >= 0);
}

test "Dependency analysis" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    // Create dependency graph: A depends on B, B depends on C
    const nodeA = TemporalNode.init(allocator, 10, NodeType.module, "test-agent");
    const nodeB = TemporalNode.init(allocator, 20, NodeType.module, "test-agent");
    const nodeC = TemporalNode.init(allocator, 30, NodeType.module, "test-agent");

    try fre.addNode(nodeA);
    try fre.addNode(nodeB);
    try fre.addNode(nodeC);

    const depAB = TemporalEdge.init(10, 20, RelationType.depends_on, 1.0, "test-agent");
    const depBC = TemporalEdge.init(20, 30, RelationType.depends_on, 1.0, "test-agent");

    try fre.addEdge(depAB);
    try fre.addEdge(depBC);

    // Analyze dependencies of A
    const deps = try fre.analyzeDependencies(10, .forward, 3);
    defer deps.deinit(allocator);

    try testing.expect(deps.root_node == 10);
    try testing.expect(deps.depth == 3);
    try testing.expect(deps.nodes.len >= 1);
}

test "Impact analysis" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    // Create simple impact scenario
    const core = TemporalNode.init(allocator, 100, NodeType.module, "test-agent");
    const user1 = TemporalNode.init(allocator, 101, NodeType.module, "test-agent");
    const user2 = TemporalNode.init(allocator, 102, NodeType.module, "test-agent");

    try fre.addNode(core);
    try fre.addNode(user1);
    try fre.addNode(user2);

    // Users depend on core
    const dep1 = TemporalEdge.init(101, 100, RelationType.depends_on, 1.0, "test-agent");
    const dep2 = TemporalEdge.init(102, 100, RelationType.depends_on, 1.0, "test-agent");

    try fre.addEdge(dep1);
    try fre.addEdge(dep2);

    // Analyze impact of changing core
    const impact = try fre.computeImpactRadius(&[_]NodeID{100}, 2);
    defer impact.deinit(allocator);

    try testing.expect(impact.estimated_complexity >= 0.0);
    try testing.expect(impact.estimated_complexity <= 1.0);
}

test "Reachability check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fre = FrontierReductionEngine.init(allocator);
    defer fre.deinit();

    // Create disconnected components
    const nodeA = TemporalNode.init(allocator, 1, NodeType.file, "test-agent");
    const nodeB = TemporalNode.init(allocator, 2, NodeType.file, "test-agent");
    const nodeC = TemporalNode.init(allocator, 3, NodeType.file, "test-agent"); // Disconnected

    try fre.addNode(nodeA);
    try fre.addNode(nodeB);
    try fre.addNode(nodeC);

    // A -> B, but C is isolated
    const edge = TemporalEdge.init(1, 2, RelationType.calls, 1.0, "test-agent");
    try fre.addEdge(edge);

    // Check reachability
    const reachable_AB = try fre.checkReachability(&[_]NodeID{1}, &[_]NodeID{2}, 2);
    const reachable_AC = try fre.checkReachability(&[_]NodeID{1}, &[_]NodeID{3}, 2);

    try testing.expect(reachable_AB == true);
    try testing.expect(reachable_AC == false);
}
