# Implementation Plan

## Phase 1: Core Database (Week 1)
**Job**: Store and retrieve code entities with temporal tracking

```zig
// Start simple - just these 3 operations
pub const Database = struct {
    pub fn saveFile(path: []const u8, content: []const u8) !void
    pub fn getFile(path: []const u8) ![]const u8  
    pub fn getHistory(path: []const u8, limit: usize) ![]Change
};
```

**Success Criteria**: Can track file changes over time

## Phase 2: MCP Server (Week 2)
**Job**: Let AI agents interact with the database

```zig
// Just 3 essential tools to start
const tools = [_]Tool{
    .{ .name = "read_code", .handler = readFile },
    .{ .name = "write_code", .handler = writeFile },
    .{ .name = "get_context", .handler = getRecentChanges },
};
```

**Success Criteria**: Claude/Cursor can read/write files through MCP

## Phase 3: Web UI (Week 3)
**Job**: Show humans what agents are doing

```typescript
// Minimal viable interface
<ActivityFeed />     // List of agent actions
<FileExplorer />     // Current project state
<CommandInput />     // Send instructions to agents
```

**Success Criteria**: Can see agent activity in real-time

## Phase 4: Iterate (Week 4+)
Based on actual usage, add:
- Search capabilities (start with simple text search)
- Better context awareness (add dependencies gradually)
- Performance optimizations (only after measuring bottlenecks)

## Development Rules

1. **No feature without a user** - Someone must need it TODAY
2. **No optimization without measurement** - Profile first, optimize second
3. **No abstraction without repetition** - Extract only after 3+ uses
4. **Test the happy path first** - Make it work, then make it robust

## Current Sprint Focus

```bash
# This week's single goal:
# Make `agrama serve` work with basic file operations

zig init-lib                    # Create project
# Implement Database struct     # 3 methods only
# Add MCP server                # 3 tools only  
# Test with Claude              # Must actually work
```

## What We're NOT Building Yet

- ❌ Complex graph algorithms (FRE, HNSW)
- ❌ CRDT conflict resolution
- ❌ Multi-agent coordination
- ❌ Matryoshka embeddings
- ❌ GPU acceleration

These come AFTER we have working basics and real usage data.