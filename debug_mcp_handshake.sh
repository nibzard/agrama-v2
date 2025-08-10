#!/bin/bash

echo "=== Testing MCP Server Handshake ==="
echo ""
echo "1. Testing basic initialization request/response:"
echo ""

# Test initialize request
INIT_REQUEST='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"roots":{"listChanged":true},"sampling":{}}}}'

echo "Sending initialize request:"
echo "$INIT_REQUEST"
echo ""
echo "Response from server:"
echo "$INIT_REQUEST" | timeout 5 ./zig-out/bin/agrama_v2 mcp 2>&1 | head -n 5
echo ""

echo "2. Testing full handshake sequence:"
echo ""

# Create temporary file for test messages
cat > /tmp/mcp_test_messages.txt << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"roots":{"listChanged":true},"sampling":{}}}}
{"jsonrpc":"2.0","method":"initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF

echo "Sending handshake sequence:"
cat /tmp/mcp_test_messages.txt
echo ""
echo "Server responses:"
timeout 5 ./zig-out/bin/agrama_v2 mcp < /tmp/mcp_test_messages.txt 2>&1
echo ""

echo "3. Testing with AGRAMA_DEBUG environment variable:"
echo ""
AGRAMA_DEBUG=1 timeout 5 ./zig-out/bin/agrama_v2 mcp < /tmp/mcp_test_messages.txt 2>&1

echo ""
echo "=== End of MCP Handshake Test ==="

# Clean up
rm -f /tmp/mcp_test_messages.txt