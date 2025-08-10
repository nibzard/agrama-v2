#!/bin/bash

echo "=== Agrama MCP Server Readiness Check ==="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

READY=true

# 1. Check binary exists and is executable
echo -n "1. Checking Agrama binary... "
if [ -x "./zig-out/bin/agrama_v2" ]; then
    echo -e "${GREEN}✓${NC} Found and executable"
else
    echo -e "${RED}✗${NC} Not found or not executable"
    echo "   Run: zig build"
    READY=false
fi

# 2. Check wrapper script
echo -n "2. Checking wrapper script... "
if [ -x "./agrama-mcp.sh" ]; then
    echo -e "${GREEN}✓${NC} Found and executable"
else
    echo -e "${RED}✗${NC} Not found or not executable"
    echo "   Run: chmod +x agrama-mcp.sh"
    READY=false
fi

# 3. Check MCP configuration
echo -n "3. Checking .mcp.json configuration... "
if [ -f "./.mcp.json" ]; then
    if grep -q "agrama-mcp.sh" ./.mcp.json; then
        echo -e "${GREEN}✓${NC} Configured correctly"
    else
        echo -e "${YELLOW}⚠${NC} Found but may need updating"
        READY=false
    fi
else
    echo -e "${RED}✗${NC} Not found"
    READY=false
fi

# 4. Test basic MCP protocol
echo -n "4. Testing MCP protocol compliance... "
response=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' | ./agrama-mcp.sh 2>/dev/null)
if [[ "$response" == *'"jsonrpc":"2.0"'* ]] && [[ "$response" != *'"error":null'* ]]; then
    echo -e "${GREEN}✓${NC} Protocol compliant"
else
    echo -e "${RED}✗${NC} Protocol issues detected"
    READY=false
fi

# 5. Test tool availability
echo -n "5. Testing tool availability... "
response=$(echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./agrama-mcp.sh 2>/dev/null)
tool_count=$(echo "$response" | grep -o '"name":"[^"]*"' | wc -l)
if [ "$tool_count" -ge 3 ]; then
    echo -e "${GREEN}✓${NC} $tool_count tools available"
else
    echo -e "${RED}✗${NC} Only $tool_count tools found"
    READY=false
fi

# 6. Check for common issues
echo -n "6. Checking for common issues... "
issues=0

# Check if there's a stale process
if pgrep -f "agrama_v2 mcp" > /dev/null; then
    echo -e "\n   ${YELLOW}⚠${NC} Found running MCP process. Kill with: pkill -f 'agrama_v2 mcp'"
    issues=$((issues + 1))
fi

# Check file permissions
if [ ! -r "./.mcp.json" ]; then
    echo -e "\n   ${YELLOW}⚠${NC} .mcp.json is not readable"
    issues=$((issues + 1))
fi

if [ $issues -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No issues found"
else
    echo -e "\n   ${YELLOW}Found $issues issue(s)${NC}"
fi

echo ""
echo "========================================"
if [ "$READY" = true ]; then
    echo -e "${GREEN}✓ MCP Server is READY for Claude Code${NC}"
    echo ""
    echo "To connect in Claude Code:"
    echo "1. Run: /mcp"
    echo "2. Select 'agrama' from the list"
    echo "3. The connection should succeed"
    echo ""
    echo "Available tools:"
    echo "- read_code: Read and analyze code files"
    echo "- write_code: Write or modify code files"
    echo "- get_context: Get contextual information"
else
    echo -e "${RED}✗ MCP Server needs fixes before use${NC}"
    echo ""
    echo "Fix the issues above, then run this script again."
fi
echo "========================================"