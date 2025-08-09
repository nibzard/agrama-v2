#!/bin/bash

echo "Testing full MCP session..."

# Create a session with multiple messages
{
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}}}'
    echo '{"jsonrpc":"2.0","id":2,"method":"initialized","params":{}}'
    echo '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}'
    echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_context","arguments":{}}}'
    echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"write_code","arguments":{"path":"test.txt","content":"Hello MCP!"}}}'
    echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"read_code","arguments":{"path":"test.txt","include_history":true}}}'
} | ./zig-out/bin/agrama_v2 mcp

echo ""
echo "Session complete!"