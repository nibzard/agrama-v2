#!/bin/bash

echo "=== MCP Protocol Compliance Test ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to test a request and validate response
test_request() {
    local test_name="$1"
    local request="$2"
    local expected_contains="$3"
    local should_not_contain="$4"
    
    echo -n "Testing $test_name... "
    
    local response=$(echo "$request" | timeout 2 ./zig-out/bin/agrama_v2 mcp 2>/dev/null)
    
    # Check if response contains expected content
    if [[ "$response" == *"$expected_contains"* ]]; then
        # Check if response does NOT contain forbidden content
        if [[ -n "$should_not_contain" && "$response" == *"$should_not_contain"* ]]; then
            echo -e "${RED}FAILED${NC}"
            echo "  Response incorrectly contains: $should_not_contain"
            echo "  Full response: $response"
            ((TESTS_FAILED++))
        else
            echo -e "${GREEN}PASSED${NC}"
            ((TESTS_PASSED++))
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Expected to contain: $expected_contains"
        echo "  Full response: $response"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Initialize request
test_request "initialize" \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' \
    '"result":{"protocolVersion":"2024-11-05"' \
    '"error":null'

# Test 2: Tools list request
test_request "tools/list" \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '"result":{"tools":[' \
    '"error":null'

# Test 3: Invalid method (should return error)
test_request "invalid method error" \
    '{"jsonrpc":"2.0","id":3,"method":"invalid_method"}' \
    '"error":{"code":-32601' \
    '"result":'

# Test 4: Malformed JSON (should return parse error)
test_request "parse error" \
    '{invalid json}' \
    '"error":{"code":-32700' \
    '"result":'

# Test 5: Missing method (should return error)
test_request "missing method error" \
    '{"jsonrpc":"2.0","id":5}' \
    '"error":{"code":-32600' \
    '"result":'

# Test 6: Notification (no id, should not return response)
echo -n "Testing notification (initialized)... "
response=$(echo '{"jsonrpc":"2.0","method":"initialized"}' | timeout 2 ./zig-out/bin/agrama_v2 mcp 2>/dev/null | head -1)
if [[ -z "$response" || "$response" == "" ]]; then
    echo -e "${GREEN}PASSED${NC} (no response expected for notifications)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}FAILED${NC}"
    echo "  Unexpected response for notification: $response"
    ((TESTS_FAILED++))
fi

# Test 7: Tool call
test_request "tool call (get_context)" \
    '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_context","arguments":{}}}' \
    '"result":{"content":[' \
    '"error":null'

# Test 8: Multiple requests in sequence
echo -n "Testing request sequence... "
cat > /tmp/mcp_sequence.txt << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","method":"initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
EOF

response_count=$(timeout 2 ./zig-out/bin/agrama_v2 mcp < /tmp/mcp_sequence.txt 2>/dev/null | grep -c '^{')
if [[ "$response_count" -eq "2" ]]; then
    echo -e "${GREEN}PASSED${NC} (2 responses for 2 requests with ids)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}FAILED${NC}"
    echo "  Expected 2 responses, got $response_count"
    ((TESTS_FAILED++))
fi

rm -f /tmp/mcp_sequence.txt

echo ""
echo "=== Test Summary ==="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}✓ All tests passed! MCP server is protocol compliant.${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed. Please fix the issues above.${NC}"
    exit 1
fi