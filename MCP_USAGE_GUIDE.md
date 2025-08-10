# Agrama MCP Server Usage Guide

The Agrama CodeGraph MCP server is now fully compliant with the Model Context Protocol specification and ready for use with MCP clients.

## ✅ Validation Status

**All tests passing:** 100% success rate across comprehensive validation suite including:
- MCP Protocol compliance
- Stdio transport compliance 
- Tool execution (read_code, write_code, get_context)
- Error handling
- Memory safety
- MCP Inspector compatibility

## 🚀 Quick Start

### Option 1: Use with Claude Code

Add to your Claude Code configuration:

```json
{
  "mcpServers": {
    "agrama-codegraph": {
      "command": "/home/dev/agrama-v2/zig-out/bin/agrama_v2",
      "args": ["mcp"],
      "env": {}
    }
  }
}
```

### Option 2: Use with Cursor

Configure in Cursor settings:

```json
{
  "mcp": {
    "servers": {
      "agrama-codegraph": {
        "command": "/home/dev/agrama-v2/zig-out/bin/agrama_v2",
        "args": ["mcp"]
      }
    }
  }
}
```

### Option 3: Direct CLI Usage

```bash
# Start MCP server (stdio transport)
./zig-out/bin/agrama_v2 mcp

# The server will read JSON-RPC messages from stdin 
# and write responses to stdout
```

## 🛠️ Available Tools

### `read_code`
Read and analyze code files with optional history.

**Parameters:**
- `path` (required): File path to read
- `include_history` (optional): Include file change history

**Example:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "read_code",
    "arguments": {
      "path": "src/main.zig",
      "include_history": true
    }
  }
}
```

### `write_code`
Write or modify code files with provenance tracking.

**Parameters:**
- `path` (required): File path to write
- `content` (required): File content

**Example:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "write_code",
    "arguments": {
      "path": "src/new_file.zig",
      "content": "const std = @import(\"std\");\n\npub fn main() !void {\n    // New file content\n}"
    }
  }
}
```

### `get_context`
Get comprehensive contextual information about the project.

**Parameters:**
- `path` (optional): Specific file path for context
- `type` (optional): Context type - 'full', 'metrics', or 'agents' (default: 'full')

**Example:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "get_context",
    "arguments": {
      "type": "full"
    }
  }
}
```

## 🧪 Testing

### Run All Validation Tests
```bash
./final_mcp_validation.sh
```

### Test Individual Components
```bash
# MCP compliance
./test_mcp_compliance.sh

# Protocol communication  
./test_mcp_protocol.sh

# Tool execution
./test_mcp_tool_execution.sh

# Comprehensive inspector tests
node test_mcp_inspector.js
```

### Use MCP Inspector for Interactive Testing
```bash
npx @modelcontextprotocol/inspector --config mcp-inspector-config.json --server agrama-codegraph
```

## 📋 MCP Specification Compliance

✅ **Transport**: stdio with proper JSON-RPC message framing  
✅ **Protocol**: JSON-RPC 2.0 specification  
✅ **Version**: MCP 2024-11-05 (latest)  
✅ **Lifecycle**: Complete initialize/initialized flow  
✅ **Tools**: Dynamic tool discovery with JSON Schema validation  
✅ **Error Handling**: Proper JSON-RPC error responses  
✅ **Content Format**: MCP-compliant response content structure  
✅ **Memory Safety**: No leaks or use-after-free bugs  

## 🔍 Troubleshooting

### Common Issues

1. **Server not responding**: Ensure the binary is built with `zig build`
2. **JSON parse errors**: Verify messages end with newlines
3. **Tool not found**: Check tool names match exactly: `read_code`, `write_code`, `get_context`
4. **Permission errors**: Ensure binary has execute permissions

### Debug Mode

For debugging, you can see stderr output:
```bash
./zig-out/bin/agrama_v2 mcp 2>&1
```

Note: In production MCP usage, stderr is ignored by clients as only stdout carries the protocol.

## 🏗️ Architecture

The Agrama MCP server implements:
- **Temporal Knowledge Graph Database**: Version-controlled code storage
- **Collaborative AI Tools**: Multi-agent code editing support  
- **Semantic Context**: AI-powered code understanding
- **Real-time Collaboration**: CRDT-based conflict resolution

This makes it ideal for AI-assisted development workflows where multiple agents need to understand and modify code collaboratively.