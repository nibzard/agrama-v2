#!/bin/bash

echo "🔧 Agrama MCP Server Troubleshooting"
echo "===================================="
echo ""

# Check if server binary exists
if [[ ! -f "zig-out/bin/agrama_v2" ]]; then
    echo "❌ Server binary not found. Run: zig build"
    exit 1
else
    echo "✅ Server binary found"
fi

# Test server startup
echo "🧪 Testing server startup..."
if timeout 5 bash -c "echo '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}}},\"id\":1}' | ./zig-out/bin/agrama_v2 mcp" >/dev/null 2>&1; then
    echo "✅ Server starts and responds to initialize"
else
    echo "❌ Server failed to start or respond"
    echo "   Try: zig build && ./zig-out/bin/agrama_v2 mcp"
fi

# Check for common issues
echo ""
echo "📋 Common Issues & Solutions:"
echo ""
echo "1. 'Failed to reconnect to agrama'"
echo "   → Server process crashed or was killed"
echo "   → Solution: Use ./mcp_health_monitor.sh start"
echo ""
echo "2. 'Connection timeout'"
echo "   → Server is not responding to requests"
echo "   → Solution: Check server logs in mcp_server.log"
echo ""
echo "3. 'Server not found'"
echo "   → Binary not built or wrong path"
echo "   → Solution: Run 'zig build' and check claude_desktop_config.json"
echo ""
echo "🔬 Advanced Debugging:"
echo "   • Use MCP Inspector: npx @modelcontextprotocol/inspector --config mcp-inspector-config.json"
echo "   • Check logs: tail -f mcp_server.log"
echo "   • Monitor process: ./mcp_health_monitor.sh status"
echo ""

# Show current process status
if [[ -f "mcp_server.pid" ]] && ps -p $(cat mcp_server.pid) >/dev/null 2>&1; then
    echo "✅ MCP server is currently running (PID: $(cat mcp_server.pid))"
else
    echo "❌ MCP server is not currently running"
    echo "   Start with: ./mcp_health_monitor.sh start"
fi
