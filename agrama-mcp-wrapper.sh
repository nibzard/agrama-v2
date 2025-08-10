#!/bin/bash

# Agrama MCP Server Wrapper
# This script ensures the MCP server starts correctly for Claude Code

set -euo pipefail

# Change to the project directory
cd "$(dirname "$0")"

# Ensure the binary is built and executable
if [[ ! -f "zig-out/bin/agrama_v2" ]]; then
    # Try to build the server
    if command -v zig >/dev/null 2>&1; then
        zig build >/dev/null 2>&1 || {
            echo "Error: Failed to build Agrama MCP server" >&2
            exit 1
        }
    else
        echo "Error: Agrama MCP server binary not found and zig not available" >&2
        exit 1
    fi
fi

# Make sure the binary is executable
chmod +x "zig-out/bin/agrama_v2"

# Only log startup in debug mode (Claude Code treats stderr as error)
if [[ "${AGRAMA_DEBUG:-}" == "1" ]]; then
    echo "[$(date)] Starting Agrama MCP Server..." >&2
fi

# Execute the MCP server
exec "./zig-out/bin/agrama_v2" mcp