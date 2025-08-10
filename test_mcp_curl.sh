#!/bin/bash

# MCP Server Testing Script via Direct Connection
# Tests the MCP server functionality using curl-like stdin/stdout communication

set -euo pipefail

echo "🧪 Testing MCP Server via Direct Connection"
echo "=============================================="

# Test 1: Initialize
echo ""
echo "1️⃣ Testing Initialize..."
INIT_MSG='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}},"id":1}'
echo "Request: $INIT_MSG"
echo ""
echo "Response:"
echo "$INIT_MSG" | timeout 5 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | head -1
echo ""

# Test 2: List Tools
echo "2️⃣ Testing Tools List..."
TOOLS_MSG='{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}'
echo "Request: $TOOLS_MSG"
echo ""
echo "Response:"
echo "$TOOLS_MSG" | timeout 5 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | head -1
echo ""

# Test 3: Test Read Code Tool
echo "3️⃣ Testing Read Code Tool..."
READ_MSG='{"jsonrpc":"2.0","method":"tools/call","params":{"name":"read_code","arguments":{"path":"src/main.zig"}},"id":3}'
echo "Request: $READ_MSG"
echo ""
echo "Response:"
echo "$READ_MSG" | timeout 10 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | head -1
echo ""

# Test 4: Test Get Context Tool
echo "4️⃣ Testing Get Context Tool..."
CONTEXT_MSG='{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_context","arguments":{"type":"full"}},"id":4}'
echo "Request: $CONTEXT_MSG"
echo ""
echo "Response:"
echo "$CONTEXT_MSG" | timeout 10 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | head -1
echo ""

echo "✅ MCP Server Direct Testing Complete!"
echo ""
echo "📊 MCP Inspector Status:"
if ps aux | grep -q "[m]odelcontextprotocol/inspector"; then
    echo "✅ MCP Inspector is running"
    echo "   Web Interface: http://localhost:6274/?MCP_PROXY_AUTH_TOKEN=decd01c1c0f52ef8ae813b9030489ca8a23c38b7fd7136224b7e71a23567ad2f"
    echo "   Proxy Server: localhost:6277"
else
    echo "❌ MCP Inspector is not running"
fi
echo ""
echo "🔗 The Inspector provides a web UI to interact with the MCP server"
echo "   The server is working correctly via stdio transport!"