---
title: AI Agent Integration Guide
description: Comprehensive guide for integrating AI agents with the Agrama MCP server
---

# AI Agent Integration Guide

This guide provides comprehensive documentation for integrating AI agents with the Agrama MCP server, including setup patterns, best practices, and real-world integration examples.

## Supported AI Agents

The Agrama MCP server supports integration with various AI agents and development environments:

### Native Integrations
- **Claude Code**: Full native support with enhanced capabilities
- **Cursor**: Configuration-based integration with VSCode compatibility
- **Custom Agents**: Direct MCP protocol integration

### Planned Integrations
- **GitHub Copilot**: MCP bridge integration (roadmap)
- **Anthropic API**: Direct API integration patterns
- **VS Code Extensions**: Native extension support

## Integration Architecture

### Connection Patterns

The MCP server supports multiple connection patterns for different use cases:

#### 1. Stdio Connection (Production Ready)
Standard stdin/stdout communication for local agent integration:

```bash
# Direct command execution
./zig-out/bin/agrama mcp

# With specific configuration
./zig-out/bin/agrama mcp --verbose --log-level debug
```

#### 2. WebSocket Connection (Planned)
Real-time bidirectional communication for advanced scenarios:

```bash
# WebSocket server mode
./zig-out/bin/agrama mcp --websocket --port 8080

# With authentication
./zig-out/bin/agrama mcp --websocket --port 8080 --auth-token <token>
```

#### 3. HTTP API Connection (Future)
RESTful API for web-based integrations:

```bash
# HTTP server mode
./zig-out/bin/agrama mcp --http --port 3000
```

## Claude Code Integration

### Quick Setup

Claude Code provides the most seamless integration experience with Agrama:

```bash
# Build Agrama
zig build

# Start in Claude Code directory
cd /path/to/your/project
./path/to/agrama/zig-out/bin/agrama mcp
```

### Configuration

Create a `.claude-mcp.json` configuration file:

```json
{
  "servers": {
    "agrama": {
      "command": "./zig-out/bin/agrama",
      "args": ["mcp"],
      "env": {
        "AGRAMA_DB_PATH": "./agrama.db",
        "AGRAMA_LOG_LEVEL": "info"
      }
    }
  }
}
```

### Usage Examples

#### Reading Code with Context
```javascript
// Claude Code automatically discovers and uses Agrama tools
// Request: "Read the database.zig file with semantic context"

// Behind the scenes, Claude Code calls:
{
  "method": "tools/call",
  "params": {
    "name": "read_code",
    "arguments": {
      "path": "src/database.zig",
      "include_semantic_context": true,
      "include_dependencies": true,
      "semantic_similarity_threshold": 0.8
    }
  }
}
```

#### Collaborative Code Writing
```javascript
// Request: "Implement a new search algorithm in search.zig"

// Claude Code uses multiple tools:
// 1. analyze_dependencies to understand current architecture
// 2. semantic_search to find similar implementations
// 3. write_code to create the new file
// 4. record_decision to document the implementation choice
```

### Advanced Features

#### Contextual Awareness
Claude Code leverages Agrama's contextual capabilities:

- **Automatic Context**: Semantic similarity detection
- **Dependency Awareness**: Understanding import relationships
- **Historical Context**: Accessing file evolution history
- **Collaborative Context**: Multi-agent decision tracking

#### Performance Integration
- **Sub-millisecond Responses**: Tool calls complete in 0.255ms P50
- **Memory Efficiency**: 50-70% allocation overhead reduction
- **Concurrent Operations**: Multiple agents supported simultaneously

## Cursor Integration

### Setup Configuration

Add Agrama to your Cursor settings:

```json
{
  "mcp.servers": {
    "agrama": {
      "command": "/path/to/agrama/zig-out/bin/agrama",
      "args": ["mcp"],
      "env": {
        "AGRAMA_DB_PATH": "./.agrama/database",
        "AGRAMA_MEMORY_LIMIT": "1GB"
      },
      "initializationOptions": {
        "enableSemanticSearch": true,
        "enableCollaboration": true
      }
    }
  }
}
```

### Cursor-Specific Features

#### VSCode Compatibility
Cursor's VSCode-based architecture enables:

- **Extension Integration**: Custom Agrama extension support
- **Workspace Awareness**: Project-level context integration
- **Language Server**: Enhanced language features through MCP

#### Usage Patterns
```typescript
// Cursor can use Agrama tools through MCP client
const mcpClient = new MCPClient({
  serverName: "agrama"
});

// Enhanced code completion with semantic search
const similarCode = await mcpClient.callTool("semantic_search", {
  query: getCurrentSelection(),
  embedding_dimension: 1024,
  max_results: 5
});
```

## Custom Agent Integration

### Direct MCP Protocol Implementation

For custom agents, implement the MCP protocol directly:

#### Python Implementation Example

```python
import json
import subprocess
import asyncio
from typing import Dict, Any, List

class AgramaMCPClient:
    def __init__(self, agrama_path: str):
        self.process = subprocess.Popen(
            [agrama_path, "mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0
        )
        self.request_id = 0
        self.initialized = False
    
    async def initialize(self) -> Dict[str, Any]:
        """Initialize MCP connection"""
        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {},
                    "resources": {},
                    "prompts": {}
                },
                "clientInfo": {
                    "name": "CustomAgent",
                    "version": "1.0.0"
                }
            }
        }
        
        response = await self._send_request(request)
        self.initialized = True
        return response
    
    async def list_tools(self) -> List[Dict[str, Any]]:
        """List available tools"""
        if not self.initialized:
            await self.initialize()
        
        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/list"
        }
        
        response = await self._send_request(request)
        return response.get("result", {}).get("tools", [])
    
    async def call_tool(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call an MCP tool"""
        self.request_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/call",
            "params": {
                "name": name,
                "arguments": arguments
            }
        }
        
        return await self._send_request(request)
    
    async def _send_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Send JSON-RPC request and get response"""
        request_str = json.dumps(request) + "\n"
        self.process.stdin.write(request_str)
        self.process.stdin.flush()
        
        response_str = self.process.stdout.readline()
        return json.loads(response_str)
    
    def close(self):
        """Close MCP connection"""
        if self.process:
            self.process.terminate()
            self.process.wait()

# Usage example
async def main():
    client = AgramaMCPClient("./zig-out/bin/agrama")
    
    try:
        # Initialize connection
        init_result = await client.initialize()
        print(f"Initialized: {init_result}")
        
        # List available tools
        tools = await client.list_tools()
        print(f"Available tools: {[tool['name'] for tool in tools]}")
        
        # Read code with context
        result = await client.call_tool("read_code", {
            "path": "src/main.zig",
            "include_semantic_context": True,
            "include_dependencies": True
        })
        
        print(f"Read result: {result}")
        
    finally:
        client.close()

if __name__ == "__main__":
    asyncio.run(main())
```

#### Node.js Implementation Example

```javascript
const { spawn } = require('child_process');

class AgramaMCPClient {
    constructor(agramaPath) {
        this.process = spawn(agramaPath, ['mcp']);
        this.requestId = 0;
        this.initialized = false;
        this.pendingRequests = new Map();
        
        // Handle responses
        this.process.stdout.on('data', (data) => {
            const lines = data.toString().split('\n').filter(line => line.trim());
            for (const line of lines) {
                try {
                    const response = JSON.parse(line);
                    const pending = this.pendingRequests.get(response.id);
                    if (pending) {
                        pending.resolve(response);
                        this.pendingRequests.delete(response.id);
                    }
                } catch (error) {
                    console.error('Failed to parse response:', error);
                }
            }
        });
    }
    
    async initialize() {
        const request = {
            jsonrpc: "2.0",
            id: ++this.requestId,
            method: "initialize",
            params: {
                protocolVersion: "2024-11-05",
                capabilities: { tools: {} },
                clientInfo: {
                    name: "NodeJSAgent",
                    version: "1.0.0"
                }
            }
        };
        
        const response = await this._sendRequest(request);
        this.initialized = true;
        return response;
    }
    
    async callTool(name, arguments) {
        if (!this.initialized) {
            await this.initialize();
        }
        
        const request = {
            jsonrpc: "2.0",
            id: ++this.requestId,
            method: "tools/call",
            params: { name, arguments }
        };
        
        return this._sendRequest(request);
    }
    
    _sendRequest(request) {
        return new Promise((resolve, reject) => {
            this.pendingRequests.set(request.id, { resolve, reject });
            this.process.stdin.write(JSON.stringify(request) + '\n');
        });
    }
    
    close() {
        this.process.kill();
    }
}

// Usage
(async () => {
    const client = new AgramaMCPClient('./zig-out/bin/agrama');
    
    try {
        await client.initialize();
        
        const result = await client.callTool('semantic_search', {
            query: 'database operations',
            max_results: 5,
            similarity_threshold: 0.8
        });
        
        console.log('Search results:', result);
    } finally {
        client.close();
    }
})();
```

## Multi-Agent Collaboration

### Session Management

The Agrama MCP server supports concurrent multi-agent sessions:

#### Creating Collaborative Sessions

```json
{
  "method": "tools/call",
  "params": {
    "name": "create_session",
    "arguments": {
      "session_name": "refactoring-database-layer",
      "participants": ["claude-code", "cursor-agent", "custom-reviewer"],
      "document_paths": ["src/database.zig", "src/memory_pools.zig"],
      "session_type": "editing"
    }
  }
}
```

#### Real-Time Synchronization

Agents receive real-time updates through WebSocket events:

```javascript
// Event types broadcasted to all session participants
const eventTypes = {
    TOOL_CALL: 'tool_call',           // Agent called a tool
    DATABASE_CHANGE: 'database_change', // Knowledge graph updated
    DOCUMENT_SYNC: 'document_sync',    // CRDT synchronization
    AGENT_JOIN: 'agent_join',          // New agent joined session
    AGENT_LEAVE: 'agent_leave',        // Agent left session
    DECISION_RECORDED: 'decision_recorded' // Decision logged
};
```

### Conflict Resolution

CRDT-based conflict resolution ensures seamless collaboration:

#### Automatic Conflict Resolution
- **Operational Transform**: Automatic operation reordering
- **Vector Clocks**: Causal consistency maintenance
- **Merge Strategies**: Content-aware merging for code

#### Manual Conflict Resolution
```json
{
  "method": "tools/call",
  "params": {
    "name": "resolve_conflict",
    "arguments": {
      "document_id": "src/database.zig",
      "conflict_id": "uuid-1234",
      "resolution_strategy": "manual",
      "chosen_version": "agent-a-version",
      "reasoning": "Agent A's version preserves type safety"
    }
  }
}
```

## Performance Optimization

### Agent-Specific Optimizations

#### Connection Pooling
```python
class AgramaMCPPool:
    def __init__(self, pool_size=3):
        self.pool = []
        self.pool_size = pool_size
        self.semaphore = asyncio.Semaphore(pool_size)
    
    async def get_client(self):
        async with self.semaphore:
            if not self.pool:
                client = AgramaMCPClient("./zig-out/bin/agrama")
                await client.initialize()
                return client
            return self.pool.pop()
    
    async def return_client(self, client):
        if len(self.pool) < self.pool_size:
            self.pool.append(client)
        else:
            client.close()
```

#### Request Batching
```python
async def batch_read_files(client, file_paths):
    """Read multiple files in parallel"""
    tasks = [
        client.call_tool("read_code", {"path": path})
        for path in file_paths
    ]
    return await asyncio.gather(*tasks)
```

#### Caching Strategies
```python
from functools import lru_cache
from typing import Dict, Any

class CachedMCPClient(AgramaMCPClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._semantic_cache = {}
        self._dependency_cache = {}
    
    async def cached_semantic_search(self, query: str, **kwargs) -> Dict[str, Any]:
        cache_key = f"{query}:{hash(str(sorted(kwargs.items())))}"
        
        if cache_key in self._semantic_cache:
            return self._semantic_cache[cache_key]
        
        result = await self.call_tool("semantic_search", {
            "query": query,
            **kwargs
        })
        
        self._semantic_cache[cache_key] = result
        return result
```

## Error Handling and Recovery

### Graceful Error Handling

```python
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class RobustMCPClient(AgramaMCPClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.retry_attempts = 3
        self.retry_delay = 1.0
    
    async def call_tool_with_retry(
        self, 
        name: str, 
        arguments: Dict[str, Any],
        max_retries: Optional[int] = None
    ) -> Dict[str, Any]:
        """Call tool with automatic retry logic"""
        max_retries = max_retries or self.retry_attempts
        
        for attempt in range(max_retries):
            try:
                return await self.call_tool(name, arguments)
            except Exception as error:
                logger.warning(
                    f"Tool call failed (attempt {attempt + 1}/{max_retries}): {error}"
                )
                
                if attempt == max_retries - 1:
                    logger.error(f"Tool call failed after {max_retries} attempts")
                    raise
                
                await asyncio.sleep(self.retry_delay * (attempt + 1))
```

### Health Monitoring

```python
class HealthMonitor:
    def __init__(self, client: AgramaMCPClient):
        self.client = client
        self.health_status = "unknown"
        self.last_check = None
    
    async def check_health(self) -> Dict[str, Any]:
        """Check server health status"""
        try:
            result = await self.client.call_tool("get_performance_metrics", {
                "metric_types": ["health"],
                "time_window": "1m"
            })
            
            self.health_status = "healthy"
            self.last_check = time.time()
            return result
            
        except Exception as error:
            self.health_status = "unhealthy"
            logger.error(f"Health check failed: {error}")
            return {"status": "error", "message": str(error)}
```

## Best Practices

### Agent Development Guidelines

#### 1. Initialize Properly
Always initialize the MCP connection before using tools:

```python
async def setup_agent():
    client = AgramaMCPClient("./zig-out/bin/agrama")
    await client.initialize()
    
    # Verify tools are available
    tools = await client.list_tools()
    required_tools = ["read_code", "write_code", "semantic_search"]
    
    available_tools = {tool["name"] for tool in tools}
    missing_tools = set(required_tools) - available_tools
    
    if missing_tools:
        raise RuntimeError(f"Missing required tools: {missing_tools}")
    
    return client
```

#### 2. Handle Errors Gracefully
Implement comprehensive error handling:

```python
async def robust_code_read(client, path: str):
    try:
        result = await client.call_tool("read_code", {"path": path})
        
        if "error" in result:
            logger.error(f"Tool error: {result['error']}")
            return None
            
        return result["result"]["content"][0]["text"]
        
    except json.JSONDecodeError:
        logger.error("Invalid JSON response from server")
        return None
    except KeyError as e:
        logger.error(f"Unexpected response format: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return None
```

#### 3. Optimize Performance
Use appropriate parameters for your use case:

```python
# For quick overviews
lightweight_read = {
    "path": "src/main.zig",
    "include_semantic_context": False,
    "include_dependencies": False,
    "include_history": False
}

# For comprehensive analysis
detailed_read = {
    "path": "src/database.zig",
    "include_semantic_context": True,
    "include_dependencies": True,
    "include_history": True,
    "semantic_similarity_threshold": 0.8,
    "history_limit": 10
}
```

#### 4. Leverage Collaboration Features
Use session management for multi-agent workflows:

```python
async def collaborative_refactoring(clients: List[AgramaMCPClient]):
    # Create session
    session = await clients[0].call_tool("create_session", {
        "session_name": "database-refactoring",
        "participants": [f"agent-{i}" for i in range(len(clients))],
        "document_paths": ["src/database.zig", "src/memory_pools.zig"]
    })
    
    # Each agent works on different aspects
    tasks = [
        clients[0].call_tool("analyze_dependencies", {"path": "src/database.zig"}),
        clients[1].call_tool("semantic_search", {"query": "memory management patterns"}),
        clients[2].call_tool("get_context", {"context_types": ["recent_changes"]})
    ]
    
    results = await asyncio.gather(*tasks)
    
    # Record collaborative decision
    await clients[0].call_tool("record_decision", {
        "decision": "Refactor memory management to use arena allocators",
        "reasoning": "Based on dependency analysis and semantic search results",
        "confidence": 0.9,
        "impact": "high"
    })
```

## Security Considerations

### Authentication (Planned)

Future versions will support agent authentication:

```json
{
  "method": "authenticate",
  "params": {
    "agent_id": "claude-code-assistant",
    "token": "secure-agent-token",
    "capabilities": ["read", "write", "analyze"]
  }
}
```

### Access Control (Planned)

Role-based access control for different agent types:

```json
{
  "roles": {
    "reader": ["read_code", "semantic_search", "get_context"],
    "writer": ["read_code", "write_code", "semantic_search"],
    "admin": ["*"]
  }
}
```

### Audit Logging

All agent actions are logged for security and debugging:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "agent_id": "claude-code",
  "tool": "write_code",
  "path": "src/new_feature.zig",
  "success": true,
  "duration_ms": 0.3
}
```

The Agrama MCP server provides a robust foundation for AI agent integration with exceptional performance, comprehensive functionality, and seamless collaboration capabilities.