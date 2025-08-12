#!/bin/bash

# Claude Code MCP Integration Setup Script
# Configures Claude Code to work reliably with Agrama MCP server

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[Claude Code MCP Setup]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if we're in the right directory
check_environment() {
    if [[ ! -f "build.zig" ]] || [[ ! -d "src" ]]; then
        log_error "This script must be run from the agrama-v2 project root directory"
        exit 1
    fi
    
    if [[ ! -f "zig-out/bin/agrama" ]]; then
        log_warning "Agrama MCP server binary not found. Building..."
        if ! zig build; then
            log_error "Failed to build Agrama MCP server"
            exit 1
        fi
    fi
}

# Test MCP server functionality
test_mcp_server() {
    log "Testing MCP server functionality..."
    
    # Test basic protocol compliance
    local test_message='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}},"id":1}'
    
    if timeout 10 bash -c "echo '$test_message' | ./zig-out/bin/agrama mcp" > /dev/null 2>/dev/null; then
        log_success "MCP server basic functionality test passed"
        return 0
    else
        log_error "MCP server basic functionality test failed"
        return 1
    fi
}

# Generate Claude Code configuration
generate_claude_config() {
    local config_dir="$HOME/.config/claude-desktop"
    local config_file="$config_dir/claude_desktop_config.json"
    local current_dir=$(pwd)
    
    log "Generating Claude Code MCP configuration..."
    
    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"
    
    # Generate configuration
    cat > "$config_file" << EOF
{
  "mcpServers": {
    "agrama-codegraph": {
      "command": "$current_dir/zig-out/bin/agrama",
      "args": ["mcp"],
      "env": {
        "PATH": "$current_dir:$PATH"
      }
    }
  },
  "globalShortcuts": {
    "claude.sendMessage": "Cmd+Return"
  }
}
EOF
    
    log_success "Claude Code configuration written to: $config_file"
    log "Please restart Claude Code to load the new configuration"
}

# Generate troubleshooting script
generate_troubleshoot_script() {
    cat > "troubleshoot_mcp.sh" << 'EOF'
#!/bin/bash

echo "🔧 Agrama MCP Server Troubleshooting"
echo "===================================="
echo ""

# Check if server binary exists
if [[ ! -f "zig-out/bin/agrama" ]]; then
    echo "❌ Server binary not found. Run: zig build"
    exit 1
else
    echo "✅ Server binary found"
fi

# Test server startup
echo "🧪 Testing server startup..."
if timeout 5 bash -c "echo '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}}},\"id\":1}' | ./zig-out/bin/agrama mcp" >/dev/null 2>&1; then
    echo "✅ Server starts and responds to initialize"
else
    echo "❌ Server failed to start or respond"
    echo "   Try: zig build && ./zig-out/bin/agrama mcp"
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
EOF
    
    chmod +x troubleshoot_mcp.sh
    log_success "Troubleshooting script created: troubleshoot_mcp.sh"
}

# Main setup function
main() {
    log "🚀 Setting up Claude Code MCP integration for Agrama"
    echo ""
    
    check_environment
    
    if ! test_mcp_server; then
        log_error "MCP server is not working. Please fix the server first."
        exit 1
    fi
    
    generate_claude_config
    generate_troubleshoot_script
    
    echo ""
    log_success "✨ Claude Code MCP integration setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Restart Claude Code to load the new configuration"
    echo "2. Start the health monitor: ./mcp_health_monitor.sh start"
    echo "3. Test the connection in Claude Code"
    echo ""
    echo "Troubleshooting:"
    echo "• Run ./troubleshoot_mcp.sh for diagnostics"
    echo "• Check logs: tail -f mcp_server.log"
    echo "• Use MCP Inspector for debugging"
    echo ""
    echo "The health monitor will automatically restart the server if it fails."
}

# Usage information
usage() {
    echo "Usage: $0 [setup|test|config|troubleshoot]"
    echo ""
    echo "Commands:"
    echo "  setup       - Complete setup (default)"
    echo "  test        - Test MCP server only"
    echo "  config      - Generate Claude Code configuration only"
    echo "  troubleshoot - Generate troubleshooting script only"
}

# Command handling
case "${1:-setup}" in
    "setup")
        main
        ;;
    "test")
        check_environment
        test_mcp_server
        ;;
    "config")
        check_environment
        generate_claude_config
        ;;
    "troubleshoot")
        generate_troubleshoot_script
        ;;
    *)
        usage
        exit 1
        ;;
esac