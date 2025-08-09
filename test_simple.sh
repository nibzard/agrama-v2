#!/bin/bash

echo "Testing MCP server manually..."

# Test initialize
echo "Initialize:"
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' | ./zig-out/bin/agrama_v2 mcp

echo ""
echo "Error test:"
echo '{"jsonrpc":"2.0","id":1,"method":"nonexistent","params":{}}' | ./zig-out/bin/agrama_v2 mcp