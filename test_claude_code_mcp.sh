#!/bin/bash

echo "=== Testing Agrama MCP Server with Claude Code ==="
echo ""
echo "Prerequisites Check:"
echo "-------------------"

# Check if binary exists
if [ -f "./zig-out/bin/agrama_v2" ]; then
    echo "✓ Agrama binary found"
else
    echo "✗ Agrama binary not found. Run 'zig build' first."
    exit 1
fi

# Check if wrapper script exists
if [ -f "./agrama-mcp.sh" ]; then
    echo "✓ Wrapper script found"
else
    echo "✗ Wrapper script not found"
    exit 1
fi

# Check if .mcp.json exists
if [ -f "./.mcp.json" ]; then
    echo "✓ MCP configuration found"
    echo ""
    echo "MCP Configuration:"
    cat ./.mcp.json
else
    echo "✗ MCP configuration not found"
    exit 1
fi

echo ""
echo "Testing MCP Server Directly:"
echo "----------------------------"

# Test 1: Basic initialization
echo -n "1. Testing initialization... "
response=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' | ./agrama-mcp.sh 2>/dev/null)
if [[ "$response" == *'"result":{"protocolVersion":"2024-11-05"'* ]]; then
    echo "✓ PASSED"
else
    echo "✗ FAILED"
    echo "   Response: $response"
fi

# Test 2: Tools listing
echo -n "2. Testing tools/list... "
response=$(echo '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./agrama-mcp.sh 2>/dev/null)
if [[ "$response" == *'"tools":['* ]] && [[ "$response" == *'"read_code"'* ]]; then
    echo "✓ PASSED"
else
    echo "✗ FAILED"
    echo "   Response: $response"
fi

# Test 3: Tool execution
echo -n "3. Testing tool execution (get_context)... "
response=$(echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_context","arguments":{}}}' | ./agrama-mcp.sh 2>/dev/null)
if [[ "$response" == *'"content":['* ]] && [[ "$response" == *'Agrama CodeGraph'* ]]; then
    echo "✓ PASSED"
else
    echo "✗ FAILED"
    echo "   Response: $response"
fi

echo ""
echo "Testing Full Handshake Sequence:"
echo "--------------------------------"

# Create a test sequence file
cat > /tmp/mcp_handshake.txt << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"roots":{"listChanged":true},"sampling":{}},"clientInfo":{"name":"claude-code","version":"1.0.0"}}}
{"jsonrpc":"2.0","method":"initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_context","arguments":{}}}
EOF

echo "Sending full handshake sequence..."
responses=$(./agrama-mcp.sh < /tmp/mcp_handshake.txt 2>/dev/null)

# Count valid responses
response_count=$(echo "$responses" | grep -c '^{')
echo "Received $response_count responses"

# Validate each response
if [[ "$responses" == *'"protocolVersion":"2024-11-05"'* ]]; then
    echo "✓ Initialize response valid"
else
    echo "✗ Initialize response invalid"
fi

if [[ "$responses" == *'"tools":['* ]]; then
    echo "✓ Tools list response valid"
else
    echo "✗ Tools list response invalid"
fi

if [[ "$responses" == *'Agrama CodeGraph'* ]]; then
    echo "✓ Tool call response valid"
else
    echo "✗ Tool call response invalid"
fi

# Clean up
rm -f /tmp/mcp_handshake.txt

echo ""
echo "=== Claude Code Integration Instructions ==="
echo ""
echo "To use this MCP server with Claude Code:"
echo ""
echo "1. The .mcp.json file is already configured in this directory"
echo ""
echo "2. In Claude Code, run:"
echo "   /mcp"
echo ""
echo "3. Select 'agrama' from the list"
echo ""
echo "4. The server should connect successfully"
echo ""
echo "If connection fails, check:"
echo "- Run 'zig build' to ensure binary is up to date"
echo "- Check logs in: ~/.cache/claude-cli-nodejs/$(pwd | tr '/' '-')"
echo ""
echo "Available tools once connected:"
echo "- read_code: Read and analyze code files"
echo "- write_code: Write or modify code files"  
echo "- get_context: Get comprehensive contextual information"
echo ""