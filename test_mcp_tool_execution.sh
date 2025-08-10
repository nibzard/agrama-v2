#!/bin/bash

# Test MCP tool execution
echo "Testing MCP tool execution..."

# Create test messages for a complete workflow
cat > /tmp/mcp_tool_test.json << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}
{"jsonrpc":"2.0","method":"initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"write_code","arguments":{"path":"test_mcp.txt","content":"Hello from MCP compliant server!"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_code","arguments":{"path":"test_mcp.txt"}}}
EOF

echo "=== MCP Tool Execution Test ==="
./zig-out/bin/agrama_v2 mcp < /tmp/mcp_tool_test.json 2>/dev/null | jq .

# Clean up
rm -f /tmp/mcp_tool_test.json