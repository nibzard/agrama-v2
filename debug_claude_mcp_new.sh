#!/bin/bash

# Debug script to capture what Claude Code sends to MCP server

LOG_FILE="/tmp/mcp_debug_$(date +%s).log"

echo "=== MCP Debug Server Started ===" >> "$LOG_FILE"
echo "PID: $$" >> "$LOG_FILE"
echo "Time: $(date)" >> "$LOG_FILE"

# Read and log all input, then pass to actual server
while IFS= read -r line; do
    echo "RECEIVED: $line" >> "$LOG_FILE"
    echo "$line"
done | ./zig-out/bin/agrama_v2 mcp 2>> "$LOG_FILE" | while IFS= read -r response; do
    echo "SENT: $response" >> "$LOG_FILE"
    echo "$response"
done

echo "=== Server Exited ===" >> "$LOG_FILE"
echo "Log saved to: $LOG_FILE" >&2