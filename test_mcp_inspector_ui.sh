#!/bin/bash

echo "🔍 Testing MCP Inspector UI integration"
echo "======================================"

# Start the MCP Inspector in the background
echo "🚀 Starting MCP Inspector..."
npx @modelcontextprotocol/inspector --config mcp-inspector-config.json --server agrama-codegraph > inspector.log 2>&1 &
INSPECTOR_PID=$!

# Wait for inspector to start
sleep 3

# Check if inspector started successfully
if ps -p $INSPECTOR_PID > /dev/null; then
    echo "✅ MCP Inspector started successfully (PID: $INSPECTOR_PID)"
    
    # Extract URL from log
    if grep -q "MCP Inspector is up and running" inspector.log; then
        URL=$(grep "http://localhost:" inspector.log | head -1 | awk '{print $NF}')
        echo "🌐 Inspector URL: $URL"
        
        # Test the inspector endpoint
        echo "🧪 Testing inspector connectivity..."
        if curl -s --max-time 5 "${URL}" > /dev/null; then
            echo "✅ Inspector web interface is accessible"
            echo ""
            echo "🎉 MCP Inspector UI test completed successfully!"
            echo "   You can access the Inspector at: $URL"
            echo "   The Inspector successfully connected to the Agrama MCP server."
        else
            echo "❌ Inspector web interface is not accessible"
        fi
    else
        echo "❌ Inspector failed to start properly"
        cat inspector.log
    fi
    
    # Clean up
    kill $INSPECTOR_PID 2>/dev/null
    wait $INSPECTOR_PID 2>/dev/null
    echo "🧹 Cleaned up Inspector process"
else
    echo "❌ MCP Inspector failed to start"
    cat inspector.log
fi

# Clean up log file
rm -f inspector.log