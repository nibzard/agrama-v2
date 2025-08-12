#!/bin/bash
# MCP Server Direct Execution Wrapper
# Simply executes the binary directly without background processes

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the Agrama binary
AGRAMA_BIN="$SCRIPT_DIR/zig-out/bin/agrama"

# Check if binary exists
if [ ! -f "$AGRAMA_BIN" ]; then
    echo "Error: Agrama binary not found at $AGRAMA_BIN" >&2
    echo "Please run 'zig build' first" >&2
    exit 1
fi

# Execute the MCP server directly (no background process)
# This preserves stdin/stdout for MCP protocol communication
# Enhanced mode is default, so just use mcp command
exec "$AGRAMA_BIN" mcp