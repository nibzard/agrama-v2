#!/bin/bash

# Minimal MCP server for testing
# Just echoes back a basic response to any initialize message

while IFS= read -r line; do
    if [[ "$line" == *"initialize"* ]]; then
        echo '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"test","version":"1.0.0"}}}'
    elif [[ "$line" == *"tools/list"* ]]; then
        echo '{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}'
    elif [[ -z "$line" ]]; then
        # Empty line - exit gracefully
        break
    fi
done