# Quick Reference

## Architecture (Simple Version)

```
AI Agents → MCP Server → Database → File System
                ↓
         Web UI (localhost:3000)
```

## Database API

```zig
const Database = struct {
    // Phase 1 - Basic Operations
    saveFile(path, content) 
    getFile(path)
    getHistory(path, limit)
    
    // Phase 2 - Search (later)
    search(query)
    getDependencies(path)
    
    // Phase 3 - Advanced (much later)
    semanticSearch(embedding)
    graphTraversal(start, end)
};
```

## MCP Tools

```javascript
// Phase 1 - Essential
read_code    - Read file with history
write_code   - Write file with reason
get_context  - Get recent changes

// Phase 2 - Helpful (later)
search       - Find code patterns
analyze      - Show dependencies

// Phase 3 - Advanced (much later)  
explain      - AI explanations
refactor     - Guided refactoring
```

## Commands

```bash
# Development
zig build           # Compile
zig build test      # Run tests
zig fmt .           # Format code

# Running
agrama init         # Setup project
agrama serve        # Start MCP server
agrama web          # Open Observatory UI
```

## Performance Targets (For Later)

Only optimize after measuring:
- MCP response: <100ms
- File operations: <10ms  
- Web UI updates: <500ms

## Testing Strategy

1. **Now**: Manual testing with Claude
2. **Soon**: Basic unit tests for Database
3. **Later**: Integration tests for MCP
4. **Eventually**: Performance benchmarks

## What We're Building

✅ **NOW**
- File storage with history
- Basic MCP server
- Simple web UI

⏸️ **LATER**
- Search and indexing
- Multi-agent support
- Dependency analysis

❌ **MAYBE NEVER**
- Complex graph algorithms
- CRDT conflict resolution
- GPU acceleration
- Distributed storage

## Success Metrics

**Week 1**: Can track file changes
**Week 2**: Claude can use it
**Week 3**: Humans can watch
**Week 4**: Actually useful