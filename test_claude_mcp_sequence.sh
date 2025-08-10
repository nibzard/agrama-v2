#!/bin/bash

# Test the exact sequence Claude Code might use for MCP health check

set -euo pipefail

echo "Testing Claude Code MCP sequence..."

# Test 1: Basic initialize request
echo "=== Test 1: Initialize Request ==="
timeout 5 bash -c '
cat << EOF | ./zig-out/bin/agrama_v2 mcp
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-code","version":"1.0.0"}}}
EOF
' 2>&1 || echo "Exit code: $?"

echo
echo "=== Test 2: Full Handshake ==="
timeout 5 bash -c '
cat << EOF | ./zig-out/bin/agrama_v2 mcp
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-code","version":"1.0.0"}}}
{"jsonrpc":"2.0","method":"initialized","params":{}}
EOF
' 2>&1 || echo "Exit code: $?"

echo
echo "=== Test 3: Quick Connection Test ==="
timeout 2 bash -c '
echo "" | ./zig-out/bin/agrama_v2 mcp
' 2>&1 || echo "Exit code: $?"

echo
echo "Test completed."