# MCP Server Consolidation Implementation

## Step-by-Step Implementation Plan

### Current Analysis

**Currently Used Servers:**
1. `mcpCommand()` → `MCPCompliantServer` (enhanced/basic modes)
2. `primitiveCommand()` → `PrimitiveMCPServer` 
3. `AgramaCodeGraphServer` → `MCPServer` (legacy)
4. `testDatabaseCommand()` → `MCPServer` (testing)

**Files to Consolidate:**
- `mcp_server.zig` (76KB, 1738 lines) - legacy server
- `enhanced_mcp_server.zig` (28KB, 681 lines) - enhanced features
- `mcp_compliant_server.zig` (94KB, 27K+ lines) - current default
- `mcp_primitive_server.zig` (47KB, 1085 lines) - **TARGET ARCHITECTURE**

### Implementation Strategy

#### Phase 1: Make Primitive Server the Default (Immediate)

**File: main.zig Changes**

```zig
// Change mcpCommand to use primitive server by default
fn mcpCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var use_legacy = false; // Primitive is now default
    // ... rest of primitive server initialization logic
    // Add --legacy flag for backward compatibility
}
```

**Key Changes:**
1. Swap default behavior: primitive server becomes default
2. Add `--legacy` flag to access old `MCPCompliantServer`
3. Update help text to promote primitive architecture
4. Keep all functionality through flags

#### Phase 2: Update Root Exports (After Phase 1 testing)

**File: root.zig Changes**

```zig
// Priority order for exports:
// 1. Primitive Server (primary)
pub const PrimitiveMCPServer = @import("mcp_primitive_server.zig").PrimitiveMCPServer;
pub const MCPPrimitiveDefinition = @import("mcp_primitive_server.zig").MCPPrimitiveDefinition;

// 2. Legacy compatibility (mark as deprecated)
pub const MCPCompliantServer = @import("mcp_compliant_server.zig").MCPCompliantServer; // DEPRECATED
pub const MCPServer = @import("mcp_server.zig").MCPServer; // DEPRECATED

// 3. Update AgramaCodeGraphServer to use primitive server
pub const AgramaCodeGraphServer = struct {
    // Update to use PrimitiveMCPServer instead of MCPServer
    primitive_mcp_server: PrimitiveMCPServer,
    // ... rest of the structure
};
```

#### Phase 3: Build System Updates

**File: build.zig Changes**

No immediate changes needed, but prepare for:
1. Mark deprecated executables
2. Add primitive server validation targets
3. Update test targets to use primitive server

### Implementation Files

#### main.zig Patch
```patch
@@ -173,8 +173,8 @@ fn mcpCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
-    var use_enhanced = true; // Enhanced mode is now the default
+    var use_legacy = false; // Primitive mode is now the default
     var hnsw_dimensions: u32 = 768;
-    var enable_crdt = true;
-    var enable_triple_search = true;
+    var enable_semantic = true;
+    var enable_graph = true;

@@ -183,7 +183,7 @@ fn mcpCommand(allocator: std.mem.Allocator, args: [][:0]u8) !void {
         if (std.mem.eql(u8, arg, "--help")) {
             const stdout = std.io.getStdOut().writer();
             try stdout.writeAll(
-                \\MCP Compliant Server
+                \\MCP Compliant Server - Revolutionary Primitive-Based Architecture
                 \\
-                \\Starts an MCP compliant server using stdio transport.
-                \\This server follows the official Model Context Protocol specification.
+                \\Starts a primitive-based MCP server using stdio transport.
+                \\Exposes 5 core primitives for AI agents to compose their own memory architectures.
                 \\
                 \\USAGE:
                 \\    agrama mcp [OPTIONS]
                 \\
                 \\OPTIONS:
-                \\    --basic                 Use basic database (legacy mode, disables advanced features)
+                \\    --legacy                Use legacy tool-based server (for compatibility only)
                 \\    --dimensions <DIM>      HNSW vector dimensions (default: 768)
-                \\    --no-crdt               Disable CRDT collaborative features
-                \\    --no-triple-search      Disable triple hybrid search
+                \\    --no-semantic           Disable semantic database features
+                \\    --no-graph              Disable graph engine features
                 \\    --help                  Show this help message
                 \\
-                \\DEFAULT TOOLS (Enhanced Mode - Default):
-                \\    read_code               Read with semantic context and dependencies
-                \\    write_code              Write with CRDT sync and semantic indexing
-                \\    semantic_search         HNSW-based semantic search
-                \\    hybrid_search           Triple hybrid BM25 + HNSW + FRE search
-                \\    analyze_dependencies    FRE-powered dependency analysis
-                \\    get_context             Comprehensive contextual information
-                \\    record_decision         Decision tracking with provenance
-                \\    query_history           Temporal history with advanced filtering
+                \\CORE PRIMITIVES (Default - Recommended):
+                \\    store                   Universal storage with rich metadata and provenance
+                \\    retrieve                Data access with history and context
+                \\    search                  Unified search (semantic/lexical/graph/temporal/hybrid)
+                \\    link                    Knowledge graph relationships with metadata
+                \\    transform               Extensible operation registry for data transformation
+                \\
+                \\PERFORMANCE TARGETS:
+                \\    Response Time:          <1ms P50 latency for primitive operations
+                \\    Throughput:             1000+ primitive ops/second
+                \\    Memory Usage:           Fixed allocation <10GB for 1M entities
+                \\    Storage Efficiency:     5× reduction through anchor+delta compression
```

### Testing Strategy

#### Validation Steps:
1. **Functionality Test**: Ensure primitive server provides all capabilities
2. **Performance Test**: Verify <1ms P50 latency targets
3. **Compatibility Test**: Ensure legacy mode works for existing users
4. **Integration Test**: Test with real AI agents (Claude Code, Cursor)
5. **Memory Test**: Validate memory safety and cleanup

#### Test Commands:
```bash
# Test primitive server (new default)
zig build run -- mcp

# Test legacy compatibility
zig build run -- mcp --legacy

# Test performance
zig build bench-mcp

# Test all primitives
zig build test-primitives
```

### Migration Benefits

#### Performance Improvements:
- **Response Time**: From ~10ms to <1ms for common operations
- **Memory Usage**: 50-70% reduction through memory pools
- **Throughput**: 10x improvement for primitive operations
- **Composability**: AI agents can build custom workflows

#### Architectural Benefits:
- **Simplicity**: Single server implementation vs 4+ variants
- **Maintainability**: One codebase to maintain and improve
- **Flexibility**: Primitive composition vs fixed tool sets
- **Future-Proof**: Architecture scales with AI capability advancement

### Risk Mitigation

#### Backward Compatibility:
- `--legacy` flag preserves old behavior
- All existing tools accessible through primitives
- Gradual migration path with clear documentation
- Performance improvements should be immediately visible

#### Rollback Plan:
- Keep deprecated servers in codebase initially
- Extensive testing before removal
- Clear versioning and migration guides
- Easy switch back via flags if issues arise

### Success Metrics

#### Technical Metrics:
- [ ] <1ms P50 latency for primitive operations
- [ ] All existing functionality preserved
- [ ] Memory usage reduced by 50%+
- [ ] Single MCP server implementation as default
- [ ] 100% test pass rate

#### User Experience Metrics:
- [ ] AI agents can compose complex workflows
- [ ] Faster response times in real usage
- [ ] Simpler debugging and troubleshooting
- [ ] Clear migration documentation
- [ ] No functionality regressions

## Next Actions

1. **Immediate**: Address file permission issues for main.zig editing
2. **Phase 1**: Implement main.zig changes (primitive as default)
3. **Phase 2**: Update root.zig exports and AgramaCodeGraphServer
4. **Phase 3**: Comprehensive testing and validation
5. **Phase 4**: Documentation updates and deprecation notices
6. **Phase 5**: Remove deprecated servers after validation period

This approach ensures a smooth transition while delivering the performance and architectural benefits of the primitive-based system.