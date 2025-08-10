#!/bin/bash

# Test MCP protocol compliance
echo "Testing MCP protocol compliance..."

# Create test messages
cat > /tmp/mcp_test_messages.json << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}
{"jsonrpc":"2.0","method":"initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_context","arguments":{}}}
EOF

# Run MCP server with test messages, capturing only stdout (the protocol)
echo "=== MCP Protocol Output (stdout only) ==="
./zig-out/bin/agrama_v2 mcp < /tmp/mcp_test_messages.json 2>/dev/null

# Clean up
rm -f /tmp/mcp_test_messages.json