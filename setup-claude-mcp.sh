#!/bin/bash
# Setup script for Claude Code MCP integration

AGRAMA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGRAMA_BIN="$AGRAMA_DIR/zig-out/bin/agrama_v2"

echo "Setting up Agrama MCP server for Claude Code..."
echo "Agrama directory: $AGRAMA_DIR"
echo "Binary path: $AGRAMA_BIN"

# Check if binary exists
if [ ! -f "$AGRAMA_BIN" ]; then
    echo "Error: Agrama binary not found. Running build..."
    cd "$AGRAMA_DIR"
    zig build
    if [ $? -ne 0 ]; then
        echo "Build failed. Please fix build errors first."
        exit 1
    fi
fi

# Test if MCP server works
echo "Testing MCP server..."
if echo '{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "test", "version": "1.0.0"}}}' | timeout 3s "$AGRAMA_BIN" mcp > /dev/null 2>&1; then
    echo "✅ MCP server is working correctly"
else
    echo "❌ MCP server test failed"
    exit 1
fi

# Create MCP configuration
cat > "$AGRAMA_DIR/claude-mcp-config.json" << EOF
{
  "mcpServers": {
    "agrama": {
      "command": "$AGRAMA_BIN",
      "args": ["mcp"],
      "cwd": "$AGRAMA_DIR",
      "env": {},
      "description": "Agrama temporal knowledge graph database with enhanced MCP tools"
    }
  }
}
EOF

echo "✅ MCP configuration created: $AGRAMA_DIR/claude-mcp-config.json"
echo ""
echo "To use with Claude Code:"
echo "1. Copy the configuration to your Claude Code MCP settings directory"
echo "2. Or configure Claude Code to use: $AGRAMA_DIR/claude-mcp-config.json"
echo "3. Restart Claude Code"
echo ""
echo "Server provides 8 enhanced tools:"
echo "  - read_code: Read with semantic context and dependencies"  
echo "  - write_code: Write with CRDT collaboration"
echo "  - semantic_search: HNSW-powered semantic search"
echo "  - analyze_dependencies: FRE graph traversal"
echo "  - hybrid_search: Combined BM25+HNSW+FRE search"
echo "  - get_context: Comprehensive system information"
echo "  - record_decision: Agent decision tracking"
echo "  - query_history: Temporal history queries"
echo ""
echo "Manual test command:"
echo "echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}' | $AGRAMA_BIN mcp"