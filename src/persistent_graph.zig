//! Persistent Graph Storage Format
//!
//! Serialization and deserialization system for temporal benchmark graphs
//! derived from AI coding sessions. Provides efficient binary storage with
//! metadata for benchmark reproducibility and version control.
//!
//! Storage Format:
//! - Binary header with metadata (graph name, project, density, algorithm)
//! - Node section with all graph nodes (id, type, content, embeddings)
//! - Edge section with all relationships (from, to, type, weight, strength)
//! - Index section for fast node lookup by name
//! - Checksum for data integrity validation
//!

const std = @import("std");
const graph_builder = @import("graph_builder.zig");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const TemporalGraph = graph_builder.TemporalGraph;
const GraphNode = graph_builder.GraphNode;
const GraphEdge = graph_builder.GraphEdge;
const GraphDensity = graph_builder.GraphDensity;

/// Binary file format version for compatibility
const PERSISTENT_GRAPH_VERSION: u32 = 1;
const MAGIC_BYTES: [4]u8 = [_]u8{ 'A', 'G', 'R', 'M' }; // "AGRM"

/// Persistent graph storage with metadata
pub const PersistentGraph = struct {
    // Header metadata
    version: u32,
    name: []const u8,
    project: []const u8,
    density: GraphDensity,
    expected_algorithm: TemporalGraph.Algorithm,
    conversation_count: u32,
    creation_timestamp: i64,

    // Graph data
    nodes: ArrayList(SerializedNode),
    edges: ArrayList(SerializedEdge),
    node_name_index: HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    // Statistics
    node_count: u32,
    edge_count: u32,
    avg_degree: f32,
    density_ratio: f32,

    // Data integrity
    checksum: u64,

    pub fn init(allocator: Allocator) PersistentGraph {
        return PersistentGraph{
            .version = PERSISTENT_GRAPH_VERSION,
            .name = "",
            .project = "",
            .density = .sparse,
            .expected_algorithm = .dijkstra,
            .conversation_count = 0,
            .creation_timestamp = std.time.timestamp(),
            .nodes = ArrayList(SerializedNode).init(allocator),
            .edges = ArrayList(SerializedEdge).init(allocator),
            .node_name_index = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .node_count = 0,
            .edge_count = 0,
            .avg_degree = 0.0,
            .density_ratio = 0.0,
            .checksum = 0,
        };
    }

    pub fn deinit(self: *PersistentGraph, allocator: Allocator) void {
        for (self.nodes.items) |*node| {
            node.deinit(allocator);
        }
        self.nodes.deinit();

        for (self.edges.items) |*edge| {
            edge.deinit(allocator);
        }
        self.edges.deinit();

        self.node_name_index.deinit();
    }
};

/// Serialized node optimized for storage
pub const SerializedNode = struct {
    id: u32,
    node_type: GraphNode.NodeType,
    name: []const u8,
    content: ?[]const u8,
    project: []const u8,
    conversation_turn: u32,
    timestamp: i64,
    embedding_size: u32,
    embedding: ?[]f32,
    metadata_count: u32,
    metadata_keys: [][]const u8,
    metadata_values: [][]const u8,

    pub fn deinit(self: *SerializedNode, allocator: Allocator) void {
        if (self.embedding) |embedding| {
            allocator.free(embedding);
        }
        for (self.metadata_keys) |key| {
            allocator.free(key);
        }
        allocator.free(self.metadata_keys);
        for (self.metadata_values) |value| {
            allocator.free(value);
        }
        allocator.free(self.metadata_values);
    }
};

/// Serialized edge optimized for storage
pub const SerializedEdge = struct {
    id: u32,
    from_node: u32,
    to_node: u32,
    edge_type: GraphEdge.EdgeType,
    weight: f32,
    strength: f32,
    conversation_turn: u32,
    metadata_count: u32,
    metadata_keys: [][]const u8,
    metadata_values: [][]const u8,

    pub fn deinit(self: *SerializedEdge, allocator: Allocator) void {
        for (self.metadata_keys) |key| {
            allocator.free(key);
        }
        allocator.free(self.metadata_keys);
        for (self.metadata_values) |value| {
            allocator.free(value);
        }
        allocator.free(self.metadata_values);
    }
};

/// Convert TemporalGraph to PersistentGraph format
pub fn fromTemporalGraph(allocator: Allocator, temporal_graph: *TemporalGraph) !PersistentGraph {
    var persistent = PersistentGraph.init(allocator);

    // Copy metadata
    persistent.name = try allocator.dupe(u8, temporal_graph.name);
    persistent.project = try allocator.dupe(u8, temporal_graph.project);
    persistent.density = temporal_graph.density;
    persistent.expected_algorithm = temporal_graph.expected_algorithm;
    persistent.conversation_count = temporal_graph.conversation_count;
    persistent.creation_timestamp = temporal_graph.creation_timestamp;

    // Convert nodes
    try persistent.nodes.ensureTotalCapacity(temporal_graph.nodes.items.len);
    for (temporal_graph.nodes.items) |*node| {
        const serialized_node = try serializeNode(allocator, node);
        try persistent.nodes.append(serialized_node);
        try persistent.node_name_index.put(serialized_node.name, serialized_node.id);
    }

    // Convert edges
    try persistent.edges.ensureTotalCapacity(temporal_graph.edges.items.len);
    for (temporal_graph.edges.items) |*edge| {
        const serialized_edge = try serializeEdge(allocator, edge);
        try persistent.edges.append(serialized_edge);
    }

    // Calculate statistics
    const stats = temporal_graph.getStats();
    persistent.node_count = stats.node_count;
    persistent.edge_count = stats.edge_count;
    persistent.avg_degree = stats.avg_degree;
    persistent.density_ratio = stats.density_ratio;

    // Calculate checksum for integrity
    persistent.checksum = calculateChecksum(&persistent);

    return persistent;
}

/// Convert PersistentGraph back to TemporalGraph format
pub fn toTemporalGraph(allocator: Allocator, persistent: *PersistentGraph) !TemporalGraph {
    var temporal = TemporalGraph.init(allocator, persistent.name, persistent.project, persistent.density);

    temporal.conversation_count = persistent.conversation_count;
    temporal.creation_timestamp = persistent.creation_timestamp;

    // Convert nodes back
    try temporal.nodes.ensureTotalCapacity(persistent.nodes.items.len);
    for (persistent.nodes.items) |*serialized_node| {
        const node = try deserializeNode(allocator, serialized_node);
        try temporal.nodes.append(node);
        try temporal.node_lookup.put(node.name, node.id);
    }

    // Convert edges back
    try temporal.edges.ensureTotalCapacity(persistent.edges.items.len);
    for (persistent.edges.items) |*serialized_edge| {
        const edge = try deserializeEdge(allocator, serialized_edge);
        try temporal.edges.append(edge);
    }

    return temporal;
}

/// Serialize a graph node for storage
fn serializeNode(allocator: Allocator, node: *GraphNode) !SerializedNode {
    // Convert metadata HashMap to arrays
    var keys = ArrayList([]const u8).init(allocator);
    defer keys.deinit();
    var values = ArrayList([]const u8).init(allocator);
    defer values.deinit();

    var iter = node.metadata.iterator();
    while (iter.next()) |entry| {
        try keys.append(try allocator.dupe(u8, entry.key_ptr.*));
        try values.append(try allocator.dupe(u8, entry.value_ptr.*));
    }

    return SerializedNode{
        .id = node.id,
        .node_type = node.node_type,
        .name = try allocator.dupe(u8, node.name),
        .content = if (node.content) |c| try allocator.dupe(u8, c) else null,
        .project = try allocator.dupe(u8, node.project),
        .conversation_turn = node.conversation_turn,
        .timestamp = node.timestamp,
        .embedding_size = if (node.embedding) |e| @as(u32, @intCast(e.len)) else 0,
        .embedding = if (node.embedding) |e| try allocator.dupe(f32, e) else null,
        .metadata_count = @as(u32, @intCast(keys.items.len)),
        .metadata_keys = try keys.toOwnedSlice(),
        .metadata_values = try values.toOwnedSlice(),
    };
}

/// Serialize a graph edge for storage
fn serializeEdge(allocator: Allocator, edge: *GraphEdge) !SerializedEdge {
    // Convert metadata HashMap to arrays
    var keys = ArrayList([]const u8).init(allocator);
    defer keys.deinit();
    var values = ArrayList([]const u8).init(allocator);
    defer values.deinit();

    var iter = edge.metadata.iterator();
    while (iter.next()) |entry| {
        try keys.append(try allocator.dupe(u8, entry.key_ptr.*));
        try values.append(try allocator.dupe(u8, entry.value_ptr.*));
    }

    return SerializedEdge{
        .id = edge.id,
        .from_node = edge.from_node,
        .to_node = edge.to_node,
        .edge_type = edge.edge_type,
        .weight = edge.weight,
        .strength = edge.strength,
        .conversation_turn = edge.conversation_turn,
        .metadata_count = @as(u32, @intCast(keys.items.len)),
        .metadata_keys = try keys.toOwnedSlice(),
        .metadata_values = try values.toOwnedSlice(),
    };
}

/// Deserialize a node back to runtime format
fn deserializeNode(allocator: Allocator, serialized: *SerializedNode) !GraphNode {
    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

    for (serialized.metadata_keys, 0..) |key, i| {
        const value = serialized.metadata_values[i];
        try metadata.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
    }

    return GraphNode{
        .id = serialized.id,
        .node_type = serialized.node_type,
        .name = try allocator.dupe(u8, serialized.name),
        .content = if (serialized.content) |c| try allocator.dupe(u8, c) else null,
        .project = try allocator.dupe(u8, serialized.project),
        .conversation_turn = serialized.conversation_turn,
        .timestamp = serialized.timestamp,
        .embedding = if (serialized.embedding) |e| try allocator.dupe(f32, e) else null,
        .metadata = metadata,
    };
}

/// Deserialize an edge back to runtime format
fn deserializeEdge(allocator: Allocator, serialized: *SerializedEdge) !GraphEdge {
    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);

    for (serialized.metadata_keys, 0..) |key, i| {
        const value = serialized.metadata_values[i];
        try metadata.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
    }

    return GraphEdge{
        .id = serialized.id,
        .from_node = serialized.from_node,
        .to_node = serialized.to_node,
        .edge_type = serialized.edge_type,
        .weight = serialized.weight,
        .strength = serialized.strength,
        .conversation_turn = serialized.conversation_turn,
        .metadata = metadata,
    };
}

/// Calculate checksum for data integrity
fn calculateChecksum(persistent: *PersistentGraph) u64 {
    var hasher = std.hash.Wyhash.init(42);

    // Hash metadata
    hasher.update(persistent.name);
    hasher.update(persistent.project);
    hasher.update(std.mem.asBytes(&persistent.node_count));
    hasher.update(std.mem.asBytes(&persistent.edge_count));

    // Hash node data
    for (persistent.nodes.items) |*node| {
        hasher.update(std.mem.asBytes(&node.id));
        hasher.update(node.name);
        hasher.update(std.mem.asBytes(&node.conversation_turn));
    }

    // Hash edge data
    for (persistent.edges.items) |*edge| {
        hasher.update(std.mem.asBytes(&edge.id));
        hasher.update(std.mem.asBytes(&edge.from_node));
        hasher.update(std.mem.asBytes(&edge.to_node));
        hasher.update(std.mem.asBytes(&edge.weight));
    }

    return hasher.final();
}

/// Save persistent graph to binary file
pub fn saveToFile(persistent: *PersistentGraph, file_path: []const u8, allocator: Allocator) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var writer = file.writer();

    // Write magic bytes and version
    try writer.writeAll(&MAGIC_BYTES);
    try writer.writeInt(u32, persistent.version, .little);

    // Write header metadata
    try writeString(writer, persistent.name);
    try writeString(writer, persistent.project);
    try writer.writeInt(u32, @intFromEnum(persistent.density), .little);
    try writer.writeInt(u32, @intFromEnum(persistent.expected_algorithm), .little);
    try writer.writeInt(u32, persistent.conversation_count, .little);
    try writer.writeInt(i64, persistent.creation_timestamp, .little);

    // Write statistics
    try writer.writeInt(u32, persistent.node_count, .little);
    try writer.writeInt(u32, persistent.edge_count, .little);
    try writer.writeInt(u32, @as(u32, @bitCast(persistent.avg_degree)), .little);
    try writer.writeInt(u32, @as(u32, @bitCast(persistent.density_ratio)), .little);

    // Write nodes
    try writer.writeInt(u32, @as(u32, @intCast(persistent.nodes.items.len)), .little);
    for (persistent.nodes.items) |*node| {
        try writeSerializedNode(writer, node, allocator);
    }

    // Write edges
    try writer.writeInt(u32, @as(u32, @intCast(persistent.edges.items.len)), .little);
    for (persistent.edges.items) |*edge| {
        try writeSerializedEdge(writer, edge);
    }

    // Write checksum
    try writer.writeInt(u64, persistent.checksum, .little);

    print("Saved persistent graph '{s}' to {s} ({d} nodes, {d} edges)\n", .{
        persistent.name, file_path, persistent.node_count, persistent.edge_count,
    });
}

/// Load persistent graph from binary file
pub fn loadFromFile(file_path: []const u8, allocator: Allocator) !PersistentGraph {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var reader = file.reader();

    // Validate magic bytes and version
    var magic: [4]u8 = undefined;
    try reader.readNoEof(&magic);
    if (!std.mem.eql(u8, &magic, &MAGIC_BYTES)) {
        return error.InvalidFileFormat;
    }

    const version = try reader.readInt(u32, .little);
    if (version != PERSISTENT_GRAPH_VERSION) {
        return error.UnsupportedVersion;
    }

    var persistent = PersistentGraph.init(allocator);
    persistent.version = version;

    // Read header metadata
    persistent.name = try readString(reader, allocator);
    persistent.project = try readString(reader, allocator);
    persistent.density = @enumFromInt(try reader.readInt(u32, .little));
    persistent.expected_algorithm = @enumFromInt(try reader.readInt(u32, .little));
    persistent.conversation_count = try reader.readInt(u32, .little);
    persistent.creation_timestamp = try reader.readInt(i64, .little);

    // Read statistics
    persistent.node_count = try reader.readInt(u32, .little);
    persistent.edge_count = try reader.readInt(u32, .little);
    persistent.avg_degree = @as(f32, @bitCast(try reader.readInt(u32, .little)));
    persistent.density_ratio = @as(f32, @bitCast(try reader.readInt(u32, .little)));

    // Read nodes
    const node_count = try reader.readInt(u32, .little);
    try persistent.nodes.ensureTotalCapacity(node_count);
    for (0..node_count) |_| {
        const node = try readSerializedNode(reader, allocator);
        try persistent.nodes.append(node);
        try persistent.node_name_index.put(node.name, node.id);
    }

    // Read edges
    const edge_count = try reader.readInt(u32, .little);
    try persistent.edges.ensureTotalCapacity(edge_count);
    for (0..edge_count) |_| {
        const edge = try readSerializedEdge(reader, allocator);
        try persistent.edges.append(edge);
    }

    // Validate checksum
    const stored_checksum = try reader.readInt(u64, .little);
    const calculated_checksum = calculateChecksum(&persistent);
    if (stored_checksum != calculated_checksum) {
        return error.ChecksumMismatch;
    }
    persistent.checksum = stored_checksum;

    print("Loaded persistent graph '{s}' from {s} ({d} nodes, {d} edges)\n", .{
        persistent.name, file_path, persistent.node_count, persistent.edge_count,
    });

    return persistent;
}

/// Helper functions for binary I/O
fn writeString(writer: anytype, str: []const u8) !void {
    try writer.writeInt(u32, @as(u32, @intCast(str.len)), .little);
    try writer.writeAll(str);
}

fn readString(reader: anytype, allocator: Allocator) ![]u8 {
    const len = try reader.readInt(u32, .little);
    const str = try allocator.alloc(u8, len);
    try reader.readNoEof(str);
    return str;
}

fn writeSerializedNode(writer: anytype, node: *SerializedNode, allocator: Allocator) !void {
    _ = allocator;
    try writer.writeInt(u32, node.id, .little);
    try writer.writeInt(u32, @intFromEnum(node.node_type), .little);
    try writeString(writer, node.name);

    // Write content
    const has_content = node.content != null;
    try writer.writeByte(if (has_content) 1 else 0);
    if (has_content) {
        try writeString(writer, node.content.?);
    }

    try writeString(writer, node.project);
    try writer.writeInt(u32, node.conversation_turn, .little);
    try writer.writeInt(i64, node.timestamp, .little);

    // Write embedding
    try writer.writeInt(u32, node.embedding_size, .little);
    if (node.embedding) |embedding| {
        for (embedding) |value| {
            try writer.writeInt(u32, @as(u32, @bitCast(value)), .little);
        }
    }

    // Write metadata
    try writer.writeInt(u32, node.metadata_count, .little);
    for (node.metadata_keys, 0..) |key, i| {
        try writeString(writer, key);
        try writeString(writer, node.metadata_values[i]);
    }
}

fn readSerializedNode(reader: anytype, allocator: Allocator) !SerializedNode {
    const id = try reader.readInt(u32, .little);
    const node_type: GraphNode.NodeType = @enumFromInt(try reader.readInt(u32, .little));
    const name = try readString(reader, allocator);

    // Read content
    const has_content = (try reader.readByte()) != 0;
    const content = if (has_content) try readString(reader, allocator) else null;

    const project = try readString(reader, allocator);
    const conversation_turn = try reader.readInt(u32, .little);
    const timestamp = try reader.readInt(i64, .little);

    // Read embedding
    const embedding_size = try reader.readInt(u32, .little);
    const embedding = if (embedding_size > 0) blk: {
        const embedding_slice = try allocator.alloc(f32, embedding_size);
        for (embedding_slice) |*value| {
            value.* = @as(f32, @bitCast(try reader.readInt(u32, .little)));
        }
        break :blk embedding_slice;
    } else null;

    // Read metadata
    const metadata_count = try reader.readInt(u32, .little);
    const keys = try allocator.alloc([]const u8, metadata_count);
    const values = try allocator.alloc([]const u8, metadata_count);

    for (0..metadata_count) |i| {
        keys[i] = try readString(reader, allocator);
        values[i] = try readString(reader, allocator);
    }

    return SerializedNode{
        .id = id,
        .node_type = node_type,
        .name = name,
        .content = content,
        .project = project,
        .conversation_turn = conversation_turn,
        .timestamp = timestamp,
        .embedding_size = embedding_size,
        .embedding = embedding,
        .metadata_count = metadata_count,
        .metadata_keys = keys,
        .metadata_values = values,
    };
}

fn writeSerializedEdge(writer: anytype, edge: *SerializedEdge) !void {
    try writer.writeInt(u32, edge.id, .little);
    try writer.writeInt(u32, edge.from_node, .little);
    try writer.writeInt(u32, edge.to_node, .little);
    try writer.writeInt(u32, @intFromEnum(edge.edge_type), .little);
    try writer.writeInt(u32, @as(u32, @bitCast(edge.weight)), .little);
    try writer.writeInt(u32, @as(u32, @bitCast(edge.strength)), .little);
    try writer.writeInt(u32, edge.conversation_turn, .little);

    // Write metadata
    try writer.writeInt(u32, edge.metadata_count, .little);
    for (edge.metadata_keys, 0..) |key, i| {
        try writeString(writer, key);
        try writeString(writer, edge.metadata_values[i]);
    }
}

fn readSerializedEdge(reader: anytype, allocator: Allocator) !SerializedEdge {
    const id = try reader.readInt(u32, .little);
    const from_node = try reader.readInt(u32, .little);
    const to_node = try reader.readInt(u32, .little);
    const edge_type: GraphEdge.EdgeType = @enumFromInt(try reader.readInt(u32, .little));
    const weight = @as(f32, @bitCast(try reader.readInt(u32, .little)));
    const strength = @as(f32, @bitCast(try reader.readInt(u32, .little)));
    const conversation_turn = try reader.readInt(u32, .little);

    // Read metadata
    const metadata_count = try reader.readInt(u32, .little);
    const keys = try allocator.alloc([]const u8, metadata_count);
    const values = try allocator.alloc([]const u8, metadata_count);

    for (0..metadata_count) |i| {
        keys[i] = try readString(reader, allocator);
        values[i] = try readString(reader, allocator);
    }

    return SerializedEdge{
        .id = id,
        .from_node = from_node,
        .to_node = to_node,
        .edge_type = edge_type,
        .weight = weight,
        .strength = strength,
        .conversation_turn = conversation_turn,
        .metadata_count = metadata_count,
        .metadata_keys = keys,
        .metadata_values = values,
    };
}

/// Test the serialization/deserialization process
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🔄 Testing persistent graph storage format...\n", .{});
    print("===============================================\n\n", .{});

    // Create sample temporal graph
    var temporal_graph = TemporalGraph.init(allocator, "test_graph", "test_project", .medium);
    defer temporal_graph.deinit(allocator);

    // Add sample data
    temporal_graph.conversation_count = 5;

    // Sample node
    var metadata = HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
    defer metadata.deinit();
    try metadata.put("type", "test");

    const node = GraphNode{
        .id = 1,
        .node_type = .code_file,
        .name = try allocator.dupe(u8, "test_file.zig"),
        .content = try allocator.dupe(u8, "test content"),
        .project = try allocator.dupe(u8, "test_project"),
        .conversation_turn = 1,
        .timestamp = std.time.timestamp(),
        .embedding = null,
        .metadata = metadata,
    };

    try temporal_graph.nodes.append(node);
    try temporal_graph.node_lookup.put("test_file.zig", 1);

    // Convert to persistent format
    print("📦 Converting to persistent format...\n", .{});
    var persistent_graph = try fromTemporalGraph(allocator, &temporal_graph);
    defer persistent_graph.deinit(allocator);

    // Save to file
    const test_file = "test_graph.agrm";
    print("💾 Saving to file: {s}...\n", .{test_file});
    try saveToFile(&persistent_graph, test_file, allocator);

    // Load from file
    print("📁 Loading from file: {s}...\n", .{test_file});
    var loaded_graph = try loadFromFile(test_file, allocator);
    defer loaded_graph.deinit(allocator);

    // Convert back to temporal format
    print("🔄 Converting back to temporal format...\n", .{});
    var restored_graph = try toTemporalGraph(allocator, &loaded_graph);
    defer restored_graph.deinit(allocator);

    // Verify integrity
    print("\n✅ Verification Results:\n", .{});
    print("   Original nodes: {d}, Restored nodes: {d}\n", .{ temporal_graph.nodes.items.len, restored_graph.nodes.items.len });
    print("   Original edges: {d}, Restored edges: {d}\n", .{ temporal_graph.edges.items.len, restored_graph.edges.items.len });
    print("   Original name: {s}, Restored name: {s}\n", .{ temporal_graph.name, restored_graph.name });
    print("   Original project: {s}, Restored project: {s}\n", .{ temporal_graph.project, restored_graph.project });
    print("   Checksum: {x}\n", .{loaded_graph.checksum});

    // Clean up test file
    std.fs.cwd().deleteFile(test_file) catch {};

    print("\n✅ Persistent graph storage format validated!\n", .{});
}
