#!/bin/bash
# MCP Server Wrapper for Agrama
# This ensures the binary is properly executed with correct paths

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the Agrama binary
AGRAMA_BIN="$SCRIPT_DIR/zig-out/bin/agrama_v2"

# Check if binary exists
if [ ! -f "$AGRAMA_BIN" ]; then
    echo "Error: Agrama binary not found at $AGRAMA_BIN" >&2
    echo "Please run 'zig build' first" >&2
    exit 1
fi

# Execute the MCP server
exec "$AGRAMA_BIN" mcp