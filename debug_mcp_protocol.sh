#!/bin/bash

# Debug script to capture what Claude Code sends to MCP server

echo "Capturing MCP protocol messages..."

# Start our MCP server and capture all input/output
timeout 10 bash -c '
    mkfifo /tmp/mcp_in /tmp/mcp_out 2>/dev/null || true
    
    # Start MCP server with debug logging
    ./zig-out/bin/agrama_v2 mcp < /tmp/mcp_in > /tmp/mcp_out 2>/tmp/mcp_stderr &
    SERVER_PID=$!
    
    # Monitor what comes in
    echo "Server started with PID $SERVER_PID"
    echo "Waiting for input..."
    
    # Wait a bit then kill
    sleep 5
    kill $SERVER_PID 2>/dev/null || true
    
    echo "=== STDERR OUTPUT ==="
    cat /tmp/mcp_stderr 2>/dev/null || echo "No stderr"
    
    echo "=== STDOUT OUTPUT ==="
    cat /tmp/mcp_out 2>/dev/null || echo "No stdout"
    
    # Cleanup
    rm -f /tmp/mcp_in /tmp/mcp_out /tmp/mcp_stderr
' || echo "Debug completed"