#!/bin/bash

# Claude Code MCP Debugging Script
# Comprehensive diagnostics for MCP connection issues

set -euo pipefail

echo "🔍 Claude Code MCP Debugging Report"
echo "===================================="
echo "Date: $(date)"
echo "Working Directory: $(pwd)"
echo ""

# Check configuration files
echo "📋 Configuration Files Status:"
echo "--------------------------------"

if [[ -f ".mcp.json" ]]; then
    echo "✅ Project .mcp.json found"
    echo "Content:"
    cat .mcp.json | jq '.' 2>/dev/null || cat .mcp.json
    echo ""
else
    echo "❌ Project .mcp.json NOT FOUND"
    echo ""
fi

# Check server binary
echo "🔧 Server Binary Status:"
echo "------------------------"

if [[ -f "zig-out/bin/agrama_v2" ]]; then
    echo "✅ Server binary exists"
    echo "   Path: $(realpath zig-out/bin/agrama_v2)"
    echo "   Size: $(du -h zig-out/bin/agrama_v2 | cut -f1)"
    echo "   Permissions: $(ls -l zig-out/bin/agrama_v2 | cut -d' ' -f1)"
    echo "   Executable: $(if [[ -x zig-out/bin/agrama_v2 ]]; then echo 'Yes'; else echo 'No'; fi)"
else
    echo "❌ Server binary NOT FOUND"
    echo "   Running build..."
    if zig build; then
        echo "   ✅ Build successful"
    else
        echo "   ❌ Build failed"
        exit 1
    fi
fi
echo ""

# Check wrapper script
echo "📜 Wrapper Script Status:"
echo "-------------------------"

if [[ -f "agrama-mcp-wrapper.sh" ]]; then
    echo "✅ Wrapper script exists"
    echo "   Executable: $(if [[ -x agrama-mcp-wrapper.sh ]]; then echo 'Yes'; else echo 'No'; fi)"
else
    echo "❌ Wrapper script NOT FOUND"
fi
echo ""

# Test server functionality
echo "🧪 Server Functionality Test:"
echo "------------------------------"

TEST_MSG='{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}},"id":1}'

echo "Testing direct binary..."
if echo "$TEST_MSG" | timeout 5 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | grep -q '"result"'; then
    echo "✅ Direct binary test passed"
else
    echo "❌ Direct binary test failed"
fi

echo "Testing wrapper script..."
if echo "$TEST_MSG" | timeout 5 ./agrama-mcp-wrapper.sh 2>/dev/null | grep -q '"result"'; then
    echo "✅ Wrapper script test passed"
else
    echo "❌ Wrapper script test failed"
fi
echo ""

# Environment check
echo "🌍 Environment Status:"
echo "----------------------"
echo "PWD: $PWD"
echo "USER: ${USER:-unknown}"
echo "PATH: $PATH"
echo "Zig available: $(if command -v zig >/dev/null; then echo 'Yes'; else echo 'No'; fi)"
echo ""

# Process check
echo "🔄 Process Status:"
echo "------------------"
if pgrep -f "agrama_v2.*mcp" >/dev/null; then
    echo "⚠️  Agrama MCP server processes currently running:"
    pgrep -fa "agrama_v2.*mcp" || true
    echo "   (These might interfere with Claude Code)"
else
    echo "✅ No Agrama MCP server processes currently running"
fi
echo ""

# Configuration validation
echo "🔍 Configuration Validation:"
echo "-----------------------------"

# Test the exact configuration
if [[ -f ".mcp.json" ]]; then
    CONFIG_CMD=$(jq -r '.mcpServers.agrama.command' .mcp.json 2>/dev/null)
    CONFIG_ARGS=$(jq -r '.mcpServers.agrama.args[]? // empty' .mcp.json 2>/dev/null | tr '\n' ' ')
    CONFIG_CWD=$(jq -r '.mcpServers.agrama.cwd // "."' .mcp.json 2>/dev/null)
    
    echo "Configured command: $CONFIG_CMD"
    echo "Configured args: ${CONFIG_ARGS:-none}"
    echo "Configured cwd: $CONFIG_CWD"
    echo ""
    
    # Test the configured command
    if [[ -f "$CONFIG_CMD" ]] && [[ -x "$CONFIG_CMD" ]]; then
        echo "✅ Configured command is executable"
        
        echo "Testing configured command..."
        if cd "$CONFIG_CWD" && echo "$TEST_MSG" | timeout 5 "$CONFIG_CMD" $CONFIG_ARGS 2>/dev/null | grep -q '"result"'; then
            echo "✅ Configured command test passed"
        else
            echo "❌ Configured command test failed"
        fi
    else
        echo "❌ Configured command is not executable or not found"
    fi
else
    echo "❌ No .mcp.json configuration found"
fi
echo ""

# Recommendations
echo "💡 Troubleshooting Recommendations:"
echo "-----------------------------------"

if [[ ! -f ".mcp.json" ]]; then
    echo "1. ❗ Create .mcp.json configuration file"
fi

if ! pgrep -f "agrama_v2.*mcp" >/dev/null; then
    echo "2. ✅ Server not running (good for Claude Code connection)"
else
    echo "2. ⚠️  Kill existing server processes: pkill -f 'agrama_v2.*mcp'"
fi

if [[ -f "agrama-mcp-wrapper.sh" ]] && [[ -x "agrama-mcp-wrapper.sh" ]]; then
    echo "3. ✅ Use wrapper script in configuration"
else
    echo "3. ❗ Ensure agrama-mcp-wrapper.sh is executable"
fi

echo "4. 🔄 After fixing issues, restart Claude Code"
echo "5. 📋 Use 'claude --debug' to see detailed logs"
echo ""

echo "🎯 Quick Test Command:"
echo "----------------------"
echo "Run this command to test your configuration:"
echo "echo '$TEST_MSG' | ./.mcp.json | jq -r '.mcpServers.agrama.command'"
echo ""

echo "🏥 Status Summary:"
echo "------------------"

# Count issues
ISSUES=0

[[ ! -f ".mcp.json" ]] && ((ISSUES++))
[[ ! -f "zig-out/bin/agrama_v2" ]] && ((ISSUES++))
[[ ! -x "agrama-mcp-wrapper.sh" ]] && ((ISSUES++))

if (( ISSUES == 0 )); then
    echo "✅ All checks passed! Configuration should work with Claude Code."
    echo "   If still failing, check Claude Code logs and restart the application."
else
    echo "❌ Found $ISSUES issue(s) that need to be fixed."
fi
echo ""

echo "📞 For additional help:"
echo "-----------------------"
echo "• Run: ./troubleshoot_mcp.sh"
echo "• Check: claude --debug"
echo "• Logs: ~/.cache/claude-cli-nodejs/"
echo ""