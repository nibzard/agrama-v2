const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Random = std.Random;

/// Node ID type for HNSW index - consistent with temporal graph
pub const NodeID = u128;

/// Vector type for embeddings - supports variable dimensions for Matryoshka embeddings
pub const Vector = struct {
    data: []f32,
    dimensions: u32,

    pub fn init(allocator: Allocator, dims: u32) !Vector {
        const data = try allocator.alloc(f32, dims);
        return Vector{
            .data = data,
            .dimensions = dims,
        };
    }

    pub fn deinit(self: *Vector, allocator: Allocator) void {
        allocator.free(self.data);
    }

    /// Truncate vector to lower dimensions for matryoshka embeddings
    pub fn truncate(self: *const Vector, new_dims: u32) Vector {
        const actual_dims = @min(new_dims, self.dimensions);
        return Vector{
            .data = self.data[0..actual_dims],
            .dimensions = actual_dims,
        };
    }

    /// Calculate cosine similarity between vectors
    pub fn cosineSimilarity(self: *const Vector, other: *const Vector) f32 {
        if (self.dimensions != other.dimensions) return 0.0;

        var dot_product: f32 = 0.0;
        var norm_a: f32 = 0.0;
        var norm_b: f32 = 0.0;

        for (0..self.dimensions) |i| {
            dot_product += self.data[i] * other.data[i];
            norm_a += self.data[i] * self.data[i];
            norm_b += other.data[i] * other.data[i];
        }

        const norm_product = @sqrt(norm_a * norm_b);
        if (norm_product == 0.0) return 0.0;

        return dot_product / norm_product;
    }

    /// Calculate Euclidean distance between vectors
    pub fn euclideanDistance(self: *const Vector, other: *const Vector) f32 {
        if (self.dimensions != other.dimensions) return std.math.inf(f32);

        var sum: f32 = 0.0;
        for (0..self.dimensions) |i| {
            const diff = self.data[i] - other.data[i];
            sum += diff * diff;
        }

        return @sqrt(sum);
    }
};

/// Matryoshka embedding with multiple precision levels
pub const MatryoshkaEmbedding = struct {
    full_vector: Vector,
    dimensions: []const u32, // Available dimension levels: [64, 256, 768, 3072]

    pub fn init(allocator: Allocator, full_dims: u32, available_dims: []const u32) !MatryoshkaEmbedding {
        const vector = try Vector.init(allocator, full_dims);
        const dims_copy = try allocator.dupe(u32, available_dims);

        return MatryoshkaEmbedding{
            .full_vector = vector,
            .dimensions = dims_copy,
        };
    }

    pub fn deinit(self: *MatryoshkaEmbedding, allocator: Allocator) void {
        self.full_vector.deinit(allocator);
        allocator.free(self.dimensions);
    }

    /// Create a deep copy of this embedding (owns its own memory)
    pub fn clone(self: *const MatryoshkaEmbedding, allocator: Allocator) !MatryoshkaEmbedding {
        const new_vector = try Vector.init(allocator, self.full_vector.dimensions);
        @memcpy(new_vector.data, self.full_vector.data);
        const new_dims = try allocator.dupe(u32, self.dimensions);

        return MatryoshkaEmbedding{
            .full_vector = new_vector,
            .dimensions = new_dims,
        };
    }

    /// Get vector at specific precision level
    pub fn atPrecision(self: *const MatryoshkaEmbedding, target_dims: u32) Vector {
        return self.full_vector.truncate(target_dims);
    }

    /// Get the coarsest (smallest dimension) vector for initial filtering
    pub fn coarse(self: *const MatryoshkaEmbedding) Vector {
        return self.full_vector.truncate(self.dimensions[0]);
    }

    /// Get the finest (full dimension) vector for final ranking
    pub fn fine(self: *const MatryoshkaEmbedding) Vector {
        return self.full_vector;
    }
};

/// HNSW node representing a graph vertex at a specific layer
pub const HNSWNode = struct {
    id: NodeID,
    vector: Vector,
    layer: u32,
    // Connections to other nodes at this layer
    connections: ArrayList(NodeID),

    pub fn init(allocator: Allocator, id: NodeID, vector: Vector, layer: u32) !HNSWNode {
        // Create a deep copy of the vector to own the data
        const owned_vector = try Vector.init(allocator, vector.dimensions);
        @memcpy(owned_vector.data, vector.data);

        return HNSWNode{
            .id = id,
            .vector = owned_vector,
            .layer = layer,
            .connections = ArrayList(NodeID).init(allocator),
        };
    }

    pub fn deinit(self: *HNSWNode, allocator: Allocator) void {
        self.vector.deinit(allocator);
        self.connections.deinit();
    }

    pub fn addConnection(self: *HNSWNode, target_id: NodeID) !void {
        // Avoid duplicate connections
        for (self.connections.items) |conn_id| {
            if (conn_id == target_id) return;
        }
        try self.connections.append(target_id);
    }

    pub fn removeConnection(self: *HNSWNode, target_id: NodeID) void {
        for (self.connections.items, 0..) |conn_id, i| {
            if (conn_id == target_id) {
                _ = self.connections.swapRemove(i);
                break;
            }
        }
    }
};

/// Search result with similarity score
pub const SearchResult = struct {
    node_id: NodeID,
    similarity: f32,
    distance: f32,
};

/// HNSW search parameters
pub const HNSWSearchParams = struct {
    k: usize, // Number of nearest neighbors to return
    ef: usize, // Size of the dynamic candidate list during search
    precision_target: f32 = 0.9, // Target precision level (0.0-1.0)
};

/// Priority queue for managing search candidates
const CandidateQueue = struct {
    items: ArrayList(SearchResult),
    is_max_heap: bool,

    pub fn init(allocator: Allocator, is_max_heap: bool) CandidateQueue {
        return CandidateQueue{
            .items = ArrayList(SearchResult).init(allocator),
            .is_max_heap = is_max_heap,
        };
    }

    pub fn deinit(self: *CandidateQueue) void {
        self.items.deinit();
    }

    pub fn push(self: *CandidateQueue, candidate: SearchResult) !void {
        try self.items.append(candidate);
        self.heapifyUp(self.items.items.len - 1);
    }

    pub fn pop(self: *CandidateQueue) ?SearchResult {
        if (self.items.items.len == 0) return null;

        const result = self.items.items[0];

        if (self.items.items.len == 1) {
            _ = self.items.pop();
            return result;
        }

        // Get the last item before popping
        const last = self.items.items[self.items.items.len - 1];
        _ = self.items.pop();

        self.items.items[0] = last;
        self.heapifyDown(0);

        return result;
    }

    pub fn peek(self: *const CandidateQueue) ?SearchResult {
        if (self.items.items.len == 0) return null;
        return self.items.items[0];
    }

    pub fn size(self: *const CandidateQueue) usize {
        return self.items.items.len;
    }

    fn heapifyUp(self: *CandidateQueue, index: usize) void {
        if (index == 0) return;

        const parent_index = (index - 1) / 2;
        const should_swap = if (self.is_max_heap)
            self.items.items[index].similarity > self.items.items[parent_index].similarity
        else
            self.items.items[index].similarity < self.items.items[parent_index].similarity;

        if (should_swap) {
            const temp = self.items.items[index];
            self.items.items[index] = self.items.items[parent_index];
            self.items.items[parent_index] = temp;
            self.heapifyUp(parent_index);
        }
    }

    fn heapifyDown(self: *CandidateQueue, index: usize) void {
        const left_child = 2 * index + 1;
        const right_child = 2 * index + 2;
        var target_index = index;

        if (left_child < self.items.items.len) {
            const should_update = if (self.is_max_heap)
                self.items.items[left_child].similarity > self.items.items[target_index].similarity
            else
                self.items.items[left_child].similarity < self.items.items[target_index].similarity;

            if (should_update) {
                target_index = left_child;
            }
        }

        if (right_child < self.items.items.len) {
            const should_update = if (self.is_max_heap)
                self.items.items[right_child].similarity > self.items.items[target_index].similarity
            else
                self.items.items[right_child].similarity < self.items.items[target_index].similarity;

            if (should_update) {
                target_index = right_child;
            }
        }

        if (target_index != index) {
            const temp = self.items.items[index];
            self.items.items[index] = self.items.items[target_index];
            self.items.items[target_index] = temp;
            self.heapifyDown(target_index);
        }
    }
};

/// Core HNSW index implementation
pub const HNSWIndex = struct {
    allocator: Allocator,
    vector_dimensions: u32,

    // HNSW parameters
    max_connections: u32, // M parameter - max connections per node
    max_connections_level0: u32, // M_L parameter - max connections at level 0
    level_multiplier: f32, // ml parameter for level generation
    ef_construction: usize, // ef parameter during construction

    // Multi-level graph structure
    // layers[i] contains all nodes at level i and above
    layers: ArrayList(HashMap(NodeID, HNSWNode, HashContext, std.hash_map.default_max_load_percentage)),
    entry_point: ?NodeID, // Entry point for search (highest level)
    node_count: usize,

    // Random number generation
    prng: std.Random.DefaultPrng,

    const HashContext = struct {
        pub fn hash(self: @This(), key: NodeID) u64 {
            _ = self;
            return @as(u64, @intCast(key & 0xFFFFFFFFFFFFFFFF));
        }

        pub fn eql(self: @This(), a: NodeID, b: NodeID) bool {
            _ = self;
            return a == b;
        }
    };

    /// Initialize HNSW index with parameters optimized for code embeddings
    pub fn init(allocator: Allocator, vector_dims: u32, max_connections: u32, ef_construction: usize, seed: u64) !HNSWIndex {
        var layers = ArrayList(HashMap(NodeID, HNSWNode, HashContext, std.hash_map.default_max_load_percentage)).init(allocator);

        // Initialize level 0 layer
        const level0_map = HashMap(NodeID, HNSWNode, HashContext, std.hash_map.default_max_load_percentage).init(allocator);
        try layers.append(level0_map);

        const prng = std.Random.DefaultPrng.init(seed);

        return HNSWIndex{
            .allocator = allocator,
            .vector_dimensions = vector_dims,
            .max_connections = max_connections,
            .max_connections_level0 = max_connections * 2, // Level 0 can have more connections
            .level_multiplier = 1.0 / @log(2.0), // ln(2.0)
            .ef_construction = ef_construction,
            .layers = layers,
            .entry_point = null,
            .node_count = 0,
            .prng = prng,
        };
    }

    pub fn deinit(self: *HNSWIndex) void {
        for (self.layers.items) |*layer| {
            var iterator = layer.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            layer.deinit();
        }
        self.layers.deinit();
    }

    /// Insert a new vector into the HNSW index
    pub fn insert(self: *HNSWIndex, node_id: NodeID, vector: Vector) !void {
        if (vector.dimensions != self.vector_dimensions) {
            return error.DimensionMismatch;
        }

        // Generate random level for the new node
        const level = self.generateLevel();

        // Ensure we have enough layers
        while (self.layers.items.len <= level) {
            const new_layer = HashMap(NodeID, HNSWNode, HashContext, std.hash_map.default_max_load_percentage).init(self.allocator);
            try self.layers.append(new_layer);
        }

        // Create node at each layer from level 0 to assigned level
        for (0..level + 1) |layer_idx| {
            const layer_num = @as(u32, @intCast(layer_idx));
            const node = try HNSWNode.init(self.allocator, node_id, vector, layer_num);
            try self.layers.items[layer_idx].put(node_id, node);
        }

        // If this is the first node or it's at a higher level than current entry point
        if (self.entry_point == null or level >= self.getNodeLevel(self.entry_point.?)) {
            self.entry_point = node_id;
        }

        // Connect the node to the graph
        try self.connectNewNode(node_id, level);

        self.node_count += 1;
    }

    /// Search for k nearest neighbors
    pub fn search(self: *HNSWIndex, query: Vector, params: HNSWSearchParams) ![]SearchResult {
        if (self.entry_point == null) {
            return &[_]SearchResult{};
        }

        if (query.dimensions != self.vector_dimensions) {
            return error.DimensionMismatch;
        }

        const entry_point = self.entry_point.?;
        const entry_level = self.getNodeLevel(entry_point);

        // Search from top layer down to layer 1
        var current_candidates = ArrayList(SearchResult).init(self.allocator);
        defer current_candidates.deinit();

        const entry_vector = self.getNodeVector(entry_point) orelse return error.NodeNotFound;
        const entry_similarity = query.cosineSimilarity(&entry_vector);
        try current_candidates.append(SearchResult{
            .node_id = entry_point,
            .similarity = entry_similarity,
            .distance = query.euclideanDistance(&entry_vector),
        });

        // Search from entry level down to level 1
        var level = entry_level;
        while (level > 0) : (level -= 1) {
            current_candidates = try self.searchLayer(&query, current_candidates.items, 1, level);
        }

        // Search level 0 with ef parameter
        const level0_candidates = try self.searchLayer(&query, current_candidates.items, params.ef, 0);
        defer level0_candidates.deinit();

        // Sort by similarity (descending) and return top k
        std.sort.pdq(SearchResult, level0_candidates.items, {}, compareSearchResults);

        const result_count = @min(params.k, level0_candidates.items.len);
        const results = try self.allocator.alloc(SearchResult, result_count);
        @memcpy(results[0..result_count], level0_candidates.items[0..result_count]);

        return results;
    }

    /// Search a specific layer for nearest neighbors
    fn searchLayer(self: *HNSWIndex, query: *const Vector, entry_points: []SearchResult, ef: usize, layer: u32) !ArrayList(SearchResult) {
        var visited = HashMap(NodeID, void, HashContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer visited.deinit();

        var candidates = CandidateQueue.init(self.allocator, false); // min-heap
        defer candidates.deinit();

        var w = CandidateQueue.init(self.allocator, true); // max-heap
        defer w.deinit();

        // Initialize with entry points
        for (entry_points) |ep| {
            try candidates.push(ep);
            try w.push(ep);
            try visited.put(ep.node_id, {});
        }

        while (candidates.size() > 0) {
            const current = candidates.pop().?;
            const w_top = w.peek() orelse break;

            // If current is further than the furthest in w, we can stop
            if (current.similarity < w_top.similarity) break;

            // Explore neighbors of current node
            if (self.layers.items[layer].get(current.node_id)) |node| {
                for (node.connections.items) |neighbor_id| {
                    if (visited.contains(neighbor_id)) continue;

                    try visited.put(neighbor_id, {});

                    const neighbor_vector = self.getNodeVector(neighbor_id) orelse continue;
                    const similarity = query.cosineSimilarity(&neighbor_vector);
                    const distance = query.euclideanDistance(&neighbor_vector);

                    const neighbor_result = SearchResult{
                        .node_id = neighbor_id,
                        .similarity = similarity,
                        .distance = distance,
                    };

                    const w_worst = w.peek() orelse SearchResult{ .node_id = 0, .similarity = -1.0, .distance = std.math.inf(f32) };

                    if (w.size() < ef or similarity > w_worst.similarity) {
                        try candidates.push(neighbor_result);
                        try w.push(neighbor_result);

                        if (w.size() > ef) {
                            _ = w.pop(); // Remove worst candidate
                        }
                    }
                }
            }
        }

        // Convert priority queue to array list
        var result = ArrayList(SearchResult).init(self.allocator);
        while (w.size() > 0) {
            try result.append(w.pop().?);
        }

        return result;
    }

    /// Generate random level for a new node using exponential decay
    fn generateLevel(self: *HNSWIndex) u32 {
        var level: u32 = 0;
        const random_val = self.prng.random().float(f32);
        while (random_val < @exp(-@as(f32, @floatFromInt(level)) / self.level_multiplier) and level < 16) {
            level += 1;
        }
        return level;
    }

    /// Get the maximum level of a node
    fn getNodeLevel(self: *HNSWIndex, node_id: NodeID) u32 {
        for (self.layers.items, 0..) |*layer, layer_idx| {
            const level = self.layers.items.len - 1 - layer_idx; // Start from top
            if (layer.contains(node_id)) {
                return @as(u32, @intCast(level));
            }
        }
        return 0; // Default to level 0
    }

    /// Get vector for a specific node
    fn getNodeVector(self: *HNSWIndex, node_id: NodeID) ?Vector {
        // Look for node starting from level 0
        if (self.layers.items[0].get(node_id)) |node| {
            return node.vector;
        }
        return null;
    }

    /// Connect a new node to the existing graph structure
    fn connectNewNode(self: *HNSWIndex, node_id: NodeID, max_level: u32) !void {
        if (self.node_count == 1) return; // First node, no connections needed

        // Connect at each level from max_level down to 0
        var level = max_level;
        while (true) {
            // Find candidate connections at this level
            const node_vector = self.getNodeVector(node_id) orelse return error.NodeNotFound;

            // Use a simple greedy approach for now - connect to closest nodes
            const max_conn = if (level == 0) self.max_connections_level0 else self.max_connections;

            var candidates = ArrayList(SearchResult).init(self.allocator);
            defer candidates.deinit();

            // Find all nodes at this level
            var layer_iterator = self.layers.items[level].iterator();
            while (layer_iterator.next()) |entry| {
                if (entry.key_ptr.* == node_id) continue; // Skip self

                const candidate_vector = entry.value_ptr.vector;
                const similarity = node_vector.cosineSimilarity(&candidate_vector);
                const distance = node_vector.euclideanDistance(&candidate_vector);

                try candidates.append(SearchResult{
                    .node_id = entry.key_ptr.*,
                    .similarity = similarity,
                    .distance = distance,
                });
            }

            // Sort by similarity and connect to best candidates
            std.sort.pdq(SearchResult, candidates.items, {}, compareSearchResults);

            const connection_count = @min(max_conn, candidates.items.len);
            for (candidates.items[0..connection_count]) |candidate| {
                // Add bidirectional connection
                if (self.layers.items[level].getPtr(node_id)) |node| {
                    try node.addConnection(candidate.node_id);
                }

                if (self.layers.items[level].getPtr(candidate.node_id)) |neighbor| {
                    try neighbor.addConnection(node_id);

                    // Prune connections if neighbor has too many
                    if (neighbor.connections.items.len > max_conn) {
                        try self.pruneConnections(candidate.node_id, level);
                    }
                }
            }

            if (level == 0) break;
            level -= 1;
        }
    }

    /// Prune excess connections for a node to maintain max connection limit
    fn pruneConnections(self: *HNSWIndex, node_id: NodeID, level: u32) !void {
        const node = self.layers.items[level].getPtr(node_id) orelse return;
        const node_vector = node.vector;

        const max_conn = if (level == 0) self.max_connections_level0 else self.max_connections;
        if (node.connections.items.len <= max_conn) return;

        // Calculate similarities to all connections
        var connection_scores = ArrayList(SearchResult).init(self.allocator);
        defer connection_scores.deinit();

        for (node.connections.items) |conn_id| {
            const conn_vector = self.getNodeVector(conn_id) orelse continue;
            const similarity = node_vector.cosineSimilarity(&conn_vector);
            const distance = node_vector.euclideanDistance(&conn_vector);

            try connection_scores.append(SearchResult{
                .node_id = conn_id,
                .similarity = similarity,
                .distance = distance,
            });
        }

        // Sort by similarity and keep only the best connections
        std.sort.pdq(SearchResult, connection_scores.items, {}, compareSearchResults);

        // Update connections list
        node.connections.clearRetainingCapacity();
        for (connection_scores.items[0..max_conn]) |score| {
            try node.connections.append(score.node_id);
        }

        // Remove bidirectional connections for pruned nodes
        for (connection_scores.items[max_conn..]) |pruned| {
            if (self.layers.items[level].getPtr(pruned.node_id)) |pruned_node| {
                pruned_node.removeConnection(node_id);
            }
        }
    }

    /// Get statistics about the HNSW index
    pub fn getStats(self: *const HNSWIndex) struct {
        node_count: usize,
        layer_count: usize,
        entry_point: ?NodeID,
        avg_connections: f32,
    } {
        var total_connections: usize = 0;
        var node_count: usize = 0;

        for (self.layers.items) |*layer| {
            var layer_iterator = layer.iterator();
            while (layer_iterator.next()) |entry| {
                total_connections += entry.value_ptr.connections.items.len;
                node_count += 1;
            }
        }

        const avg_connections = if (node_count > 0) @as(f32, @floatFromInt(total_connections)) / @as(f32, @floatFromInt(node_count)) else 0.0;

        return .{
            .node_count = self.node_count,
            .layer_count = self.layers.items.len,
            .entry_point = self.entry_point,
            .avg_connections = avg_connections,
        };
    }
};

/// Comparison function for sorting search results by similarity (descending)
fn compareSearchResults(context: void, a: SearchResult, b: SearchResult) bool {
    _ = context;
    return a.similarity > b.similarity;
}

// Unit Tests
test "Vector operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test vector creation and basic operations
    var vec1 = try Vector.init(allocator, 3);
    defer vec1.deinit(allocator);

    vec1.data[0] = 1.0;
    vec1.data[1] = 0.0;
    vec1.data[2] = 0.0;

    var vec2 = try Vector.init(allocator, 3);
    defer vec2.deinit(allocator);

    vec2.data[0] = 0.0;
    vec2.data[1] = 1.0;
    vec2.data[2] = 0.0;

    // Test cosine similarity (should be 0 for orthogonal vectors)
    const similarity = vec1.cosineSimilarity(&vec2);
    try testing.expectApproxEqAbs(@as(f32, 0.0), similarity, 0.001);

    // Test euclidean distance (should be sqrt(2) for unit vectors)
    const distance = vec1.euclideanDistance(&vec2);
    try testing.expectApproxEqAbs(@sqrt(@as(f32, 2.0)), distance, 0.001);
}

test "Matryoshka embedding truncation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dims = [_]u32{ 2, 4 };
    var embedding = try MatryoshkaEmbedding.init(allocator, 4, &dims);
    defer embedding.deinit(allocator);

    // Fill with test data
    embedding.full_vector.data[0] = 1.0;
    embedding.full_vector.data[1] = 2.0;
    embedding.full_vector.data[2] = 3.0;
    embedding.full_vector.data[3] = 4.0;

    // Test coarse vector (2D)
    const coarse = embedding.coarse();
    try testing.expect(coarse.dimensions == 2);
    try testing.expectApproxEqAbs(@as(f32, 1.0), coarse.data[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.0), coarse.data[1], 0.001);

    // Test fine vector (full 4D)
    const fine = embedding.fine();
    try testing.expect(fine.dimensions == 4);
    try testing.expectApproxEqAbs(@as(f32, 4.0), fine.data[3], 0.001);
}

test "HNSW index creation and basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var index = try HNSWIndex.init(allocator, 3, 16, 200, 12345);
    defer index.deinit();

    // Test initial state
    const initial_stats = index.getStats();
    try testing.expect(initial_stats.node_count == 0);
    try testing.expect(initial_stats.entry_point == null);

    // Insert a test vector
    var vec1 = try Vector.init(allocator, 3);
    defer vec1.deinit(allocator);

    vec1.data[0] = 1.0;
    vec1.data[1] = 0.0;
    vec1.data[2] = 0.0;

    try index.insert(1, vec1);

    // Check stats after insertion
    const stats_after_insert = index.getStats();
    try testing.expect(stats_after_insert.node_count == 1);
    try testing.expect(stats_after_insert.entry_point == 1);
}

test "HNSW search with multiple vectors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var index = try HNSWIndex.init(allocator, 3, 16, 200, 12345);
    defer index.deinit();

    // Insert multiple test vectors
    const vectors = [_][3]f32{
        [_]f32{ 1.0, 0.0, 0.0 },
        [_]f32{ 0.0, 1.0, 0.0 },
        [_]f32{ 0.0, 0.0, 1.0 },
        [_]f32{ 0.8, 0.6, 0.0 }, // Similar to first vector
    };

    for (vectors, 0..) |vec_data, i| {
        var vec = try Vector.init(allocator, 3);
        defer vec.deinit(allocator);

        @memcpy(vec.data, &vec_data);
        try index.insert(@as(NodeID, @intCast(i + 1)), vec);
    }

    // Search for vector similar to first one
    var query = try Vector.init(allocator, 3);
    defer query.deinit(allocator);

    query.data[0] = 0.9;
    query.data[1] = 0.1;
    query.data[2] = 0.0;

    const search_params = HNSWSearchParams{
        .k = 2,
        .ef = 10,
        .precision_target = 0.8,
    };

    const results = try index.search(query, search_params);
    defer allocator.free(results);

    // Should find at least one result
    try testing.expect(results.len > 0);

    // First result should be reasonably similar
    try testing.expect(results[0].similarity > 0.5);
}

test "CandidateQueue operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = CandidateQueue.init(allocator, false); // min-heap
    defer queue.deinit();

    // Test basic operations
    try queue.push(SearchResult{ .node_id = 1, .similarity = 0.5, .distance = 1.0 });
    try queue.push(SearchResult{ .node_id = 2, .similarity = 0.8, .distance = 0.5 });
    try queue.push(SearchResult{ .node_id = 3, .similarity = 0.3, .distance = 1.5 });

    try testing.expect(queue.size() == 3);

    // Min-heap should return smallest similarity first
    const first = queue.pop().?;
    try testing.expect(first.similarity == 0.3);

    const second = queue.pop().?;
    try testing.expect(second.similarity == 0.5);

    const third = queue.pop().?;
    try testing.expect(third.similarity == 0.8);

    try testing.expect(queue.size() == 0);
}
