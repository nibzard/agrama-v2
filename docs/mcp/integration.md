---
title: MCP Integration Guide
description: Step-by-step guide for integrating AI agents with the Agrama MCP server
---

# MCP Integration Guide

Comprehensive guide for integrating AI agents with the Agrama MCP server, covering setup, configuration, and best practices for various development environments.

## Quick Start

### Prerequisites

- Zig 0.12+ for building from source
- 4GB+ RAM for optimal performance
- Linux/macOS/Windows support

### Build and Installation

```bash
# Clone the repository
git clone https://github.com/your-org/agrama-v2.git
cd agrama-v2

# Build the server
zig build

# Verify installation
./zig-out/bin/agrama --version
```

### Basic Server Setup

```bash
# Start MCP server
./zig-out/bin/agrama mcp

# Start with verbose logging
./zig-out/bin/agrama mcp --verbose

# Start with custom database path
AGRAMA_DB_PATH=./custom.db ./zig-out/bin/agrama mcp
```

## Claude Code Integration

Claude Code provides the most seamless integration experience with native MCP support.

### Automatic Discovery

Claude Code automatically discovers and connects to MCP servers in your project directory:

1. **Place the binary** in your project root or PATH
2. **Start the server** with `./zig-out/bin/agrama mcp`
3. **Claude Code detects** the server automatically
4. **Tools become available** in the Claude Code interface

### Manual Configuration

Create a `.claude-mcp.json` configuration file in your project root:

```json
{
  "servers": {
    "agrama": {
      "command": "./zig-out/bin/agrama",
      "args": ["mcp"],
      "env": {
        "AGRAMA_DB_PATH": "./.agrama/database",
        "AGRAMA_LOG_LEVEL": "info",
        "AGRAMA_MEMORY_LIMIT": "1GB"
      },
      "initializationOptions": {
        "enableSemanticSearch": true,
        "enableCollaboration": true,
        "performanceMode": "balanced"
      }
    }
  },
  "global": {
    "timeout": 30000,
    "retries": 3
  }
}
```

### Usage Examples

::: code-group

```bash [Basic Usage]
# Claude Code automatically uses Agrama tools
"Read the database.zig file with semantic context"
# → Claude calls read_code with semantic_context=true

"Search for memory allocation patterns"  
# → Claude calls hybrid_search with appropriate query

"Analyze dependencies of main.zig"
# → Claude calls analyze_dependencies
```

```javascript [Advanced Usage]
// Claude Code can chain tool calls automatically
"Refactor the memory management system":
// 1. analyze_dependencies(path="src/memory_pools.zig") 
// 2. semantic_search(query="memory management patterns")
// 3. read_code(path="src/database.zig", include_dependencies=true)
// 4. write_code(path="src/memory_pools_v2.zig", ...)
// 5. record_decision(decision="Implemented arena allocators", ...)
```

:::

## Cursor Integration

Cursor integrates with MCP servers through its settings configuration.

### Settings Configuration

Add to your Cursor settings (`settings.json`):

```json
{
  "mcp.servers": {
    "agrama": {
      "command": "/absolute/path/to/agrama",
      "args": ["mcp"],
      "env": {
        "AGRAMA_DB_PATH": "/absolute/path/to/.agrama/database",
        "AGRAMA_PERFORMANCE_MODE": "high"
      },
      "initializationOptions": {
        "features": {
          "semanticSearch": true,
          "dependencyAnalysis": true,
          "collaboration": false
        }
      }
    }
  },
  "mcp.client": {
    "timeout": 10000,
    "retryAttempts": 2,
    "logLevel": "info"
  }
}
```

### Workspace Configuration

For project-specific settings, create `.vscode/settings.json`:

```json
{
  "mcp.servers": {
    "agrama-project": {
      "command": "${workspaceFolder}/zig-out/bin/agrama",
      "args": ["mcp"],
      "env": {
        "AGRAMA_DB_PATH": "${workspaceFolder}/.agrama",
        "AGRAMA_PROJECT_ROOT": "${workspaceFolder}"
      }
    }
  }
}
```

### Usage in Cursor

```typescript
// Cursor can access Agrama tools through MCP client
import { MCPClient } from '@cursor/mcp-client';

const client = new MCPClient({
  serverName: 'agrama'
});

// Use tools in extensions or custom commands
const searchResults = await client.callTool('hybrid_search', {
  query: 'error handling patterns',
  max_results: 10,
  include_semantic: true
});
```

## Custom Agent Integration

For building custom AI agents that integrate with Agrama.

### Node.js Integration

```javascript
import { spawn } from 'child_process';
import { EventEmitter } from 'events';

class AgramaMCPClient extends EventEmitter {
  constructor(serverPath, options = {}) {
    super();
    this.serverPath = serverPath;
    this.options = options;
    this.process = null;
    this.requestId = 0;
    this.pendingRequests = new Map();
    this.initialized = false;
  }

  async connect() {
    this.process = spawn(this.serverPath, ['mcp'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, ...this.options.env }
    });

    this.process.stdout.on('data', (data) => {
      const lines = data.toString().split('\n').filter(line => line.trim());
      for (const line of lines) {
        try {
          this.handleResponse(JSON.parse(line));
        } catch (error) {
          this.emit('error', new Error(`Invalid JSON response: ${error.message}`));
        }
      }
    });

    this.process.stderr.on('data', (data) => {
      this.emit('error', new Error(`Server error: ${data.toString()}`));
    });

    await this.initialize();
  }

  async initialize() {
    const response = await this.sendRequest({
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        clientInfo: {
          name: 'Custom Agent',
          version: '1.0.0'
        }
      }
    });

    this.initialized = true;
    this.emit('initialized', response.result);
    return response.result;
  }

  async listTools() {
    return this.sendRequest({ method: 'tools/list' });
  }

  async callTool(name, arguments_) {
    return this.sendRequest({
      method: 'tools/call',
      params: { name, arguments: arguments_ }
    });
  }

  sendRequest(request) {
    return new Promise((resolve, reject) => {
      const id = ++this.requestId;
      const fullRequest = {
        jsonrpc: '2.0',
        id,
        ...request
      };

      this.pendingRequests.set(id, { resolve, reject });
      this.process.stdin.write(JSON.stringify(fullRequest) + '\n');
    });
  }

  handleResponse(response) {
    const pending = this.pendingRequests.get(response.id);
    if (!pending) return;

    this.pendingRequests.delete(response.id);

    if (response.error) {
      pending.reject(new Error(`MCP Error ${response.error.code}: ${response.error.message}`));
    } else {
      pending.resolve(response);
    }
  }

  disconnect() {
    if (this.process) {
      this.process.kill();
      this.process = null;
    }
  }
}

// Usage example
const client = new AgramaMCPClient('./zig-out/bin/agrama');

client.on('initialized', (serverInfo) => {
  console.log('Connected to Agrama MCP server:', serverInfo);
});

client.on('error', (error) => {
  console.error('MCP Client error:', error);
});

await client.connect();

// Use the client
const tools = await client.listTools();
console.log('Available tools:', tools.result.tools.map(t => t.name));

const result = await client.callTool('read_code', {
  path: 'src/main.zig',
  include_semantic_context: true
});

console.log('File content:', JSON.parse(result.result.content[0].text));
```

### Python Integration

```python
import json
import subprocess
import asyncio
from typing import Dict, Any, Optional
import logging

class AgramaMCPClient:
    def __init__(self, server_path: str, env: Optional[Dict[str, str]] = None):
        self.server_path = server_path
        self.env = env or {}
        self.process = None
        self.request_id = 0
        self.pending_requests = {}
        self.initialized = False
        self.logger = logging.getLogger(__name__)

    async def connect(self):
        """Connect to the Agrama MCP server"""
        self.process = await asyncio.create_subprocess_exec(
            self.server_path, 'mcp',
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, **self.env}
        )

        # Start reading responses
        asyncio.create_task(self._read_responses())

        # Initialize the connection
        await self.initialize()

    async def initialize(self) -> Dict[str, Any]:
        """Initialize MCP connection"""
        response = await self._send_request({
            'method': 'initialize',
            'params': {
                'protocolVersion': '2024-11-05',
                'capabilities': {'tools': {}},
                'clientInfo': {
                    'name': 'Python Agent',
                    'version': '1.0.0'
                }
            }
        })

        self.initialized = True
        self.logger.info("Successfully initialized MCP connection")
        return response['result']

    async def list_tools(self) -> Dict[str, Any]:
        """List available tools"""
        return await self._send_request({'method': 'tools/list'})

    async def call_tool(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call an MCP tool"""
        return await self._send_request({
            'method': 'tools/call',
            'params': {
                'name': name,
                'arguments': arguments
            }
        })

    async def _send_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Send JSON-RPC request"""
        self.request_id += 1
        full_request = {
            'jsonrpc': '2.0',
            'id': self.request_id,
            **request
        }

        future = asyncio.Future()
        self.pending_requests[self.request_id] = future

        request_json = json.dumps(full_request) + '\n'
        self.process.stdin.write(request_json.encode())
        await self.process.stdin.drain()

        return await future

    async def _read_responses(self):
        """Read and handle responses from server"""
        try:
            async for line in self.process.stdout:
                line = line.decode().strip()
                if not line:
                    continue

                try:
                    response = json.loads(line)
                    await self._handle_response(response)
                except json.JSONDecodeError as e:
                    self.logger.error(f"Invalid JSON response: {e}")
        except Exception as e:
            self.logger.error(f"Error reading responses: {e}")

    async def _handle_response(self, response: Dict[str, Any]):
        """Handle incoming response"""
        request_id = response.get('id')
        if request_id not in self.pending_requests:
            return

        future = self.pending_requests.pop(request_id)

        if 'error' in response:
            error = response['error']
            future.set_exception(Exception(f"MCP Error {error['code']}: {error['message']}"))
        else:
            future.set_result(response)

    async def disconnect(self):
        """Disconnect from server"""
        if self.process:
            self.process.terminate()
            await self.process.wait()

# Advanced usage example with error handling and retries
class RobustAgramaMCPClient(AgramaMCPClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_retries = 3
        self.base_delay = 1.0

    async def call_tool_with_retry(self, name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call tool with exponential backoff retry"""
        last_error = None
        
        for attempt in range(self.max_retries):
            try:
                return await self.call_tool(name, arguments)
            except Exception as e:
                last_error = e
                if attempt < self.max_retries - 1:
                    delay = self.base_delay * (2 ** attempt)
                    self.logger.warning(f"Tool call failed (attempt {attempt + 1}/{self.max_retries}), retrying in {delay}s: {e}")
                    await asyncio.sleep(delay)

        raise last_error

# Usage
async def main():
    client = RobustAgramaMCPClient('./zig-out/bin/agrama', env={
        'AGRAMA_DB_PATH': './.agrama/db',
        'AGRAMA_LOG_LEVEL': 'info'
    })

    try:
        await client.connect()
        
        # List tools
        tools_response = await client.list_tools()
        tools = tools_response['result']['tools']
        print(f"Available tools: {[t['name'] for t in tools]}")

        # Use tools with retry
        result = await client.call_tool_with_retry('read_code', {
            'path': 'src/database.zig',
            'include_semantic_context': True,
            'semantic_similarity_threshold': 0.8
        })

        file_info = json.loads(result['result']['content'][0]['text'])
        print(f"File: {file_info['path']}")
        print(f"Similar files: {len(file_info.get('semantic_context', {}).get('similar_files', []))}")

    finally:
        await client.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```

### Go Integration

```go
package main

import (
    "bufio"
    "encoding/json"
    "fmt"
    "log"
    "os"
    "os/exec"
    "sync"
)

type MCPClient struct {
    cmd          *exec.Cmd
    stdin        io.WriteCloser
    stdout       io.ReadCloser
    requestID    int
    requests     map[int]chan MCPResponse
    requestMutex sync.Mutex
    initialized  bool
}

type MCPRequest struct {
    JSONRPC string      `json:"jsonrpc"`
    ID      int         `json:"id"`
    Method  string      `json:"method"`
    Params  interface{} `json:"params,omitempty"`
}

type MCPResponse struct {
    JSONRPC string          `json:"jsonrpc"`
    ID      int             `json:"id"`
    Result  json.RawMessage `json:"result,omitempty"`
    Error   *MCPError       `json:"error,omitempty"`
}

type MCPError struct {
    Code    int         `json:"code"`
    Message string      `json:"message"`
    Data    interface{} `json:"data,omitempty"`
}

func NewMCPClient(serverPath string) (*MCPClient, error) {
    cmd := exec.Command(serverPath, "mcp")
    
    stdin, err := cmd.StdinPipe()
    if err != nil {
        return nil, err
    }
    
    stdout, err := cmd.StdoutPipe()
    if err != nil {
        return nil, err
    }
    
    client := &MCPClient{
        cmd:      cmd,
        stdin:    stdin,
        stdout:   stdout,
        requests: make(map[int]chan MCPResponse),
    }
    
    if err := cmd.Start(); err != nil {
        return nil, err
    }
    
    go client.readResponses()
    
    return client, nil
}

func (c *MCPClient) Initialize() error {
    response, err := c.sendRequest("initialize", map[string]interface{}{
        "protocolVersion": "2024-11-05",
        "capabilities":    map[string]interface{}{"tools": map[string]interface{}{}},
        "clientInfo": map[string]interface{}{
            "name":    "Go Agent",
            "version": "1.0.0",
        },
    })
    
    if err != nil {
        return err
    }
    
    if response.Error != nil {
        return fmt.Errorf("initialization failed: %s", response.Error.Message)
    }
    
    c.initialized = true
    return nil
}

func (c *MCPClient) CallTool(name string, arguments interface{}) (*MCPResponse, error) {
    if !c.initialized {
        if err := c.Initialize(); err != nil {
            return nil, err
        }
    }
    
    return c.sendRequest("tools/call", map[string]interface{}{
        "name":      name,
        "arguments": arguments,
    })
}

func (c *MCPClient) sendRequest(method string, params interface{}) (*MCPResponse, error) {
    c.requestMutex.Lock()
    c.requestID++
    id := c.requestID
    responseChan := make(chan MCPResponse, 1)
    c.requests[id] = responseChan
    c.requestMutex.Unlock()
    
    request := MCPRequest{
        JSONRPC: "2.0",
        ID:      id,
        Method:  method,
        Params:  params,
    }
    
    data, err := json.Marshal(request)
    if err != nil {
        return nil, err
    }
    
    _, err = c.stdin.Write(append(data, '\n'))
    if err != nil {
        return nil, err
    }
    
    response := <-responseChan
    return &response, nil
}

func (c *MCPClient) readResponses() {
    scanner := bufio.NewScanner(c.stdout)
    for scanner.Scan() {
        var response MCPResponse
        if err := json.Unmarshal(scanner.Bytes(), &response); err != nil {
            log.Printf("Error parsing response: %v", err)
            continue
        }
        
        c.requestMutex.Lock()
        if responseChan, ok := c.requests[response.ID]; ok {
            responseChan <- response
            delete(c.requests, response.ID)
        }
        c.requestMutex.Unlock()
    }
}

func (c *MCPClient) Close() error {
    c.stdin.Close()
    return c.cmd.Wait()
}

// Usage example
func main() {
    client, err := NewMCPClient("./zig-out/bin/agrama")
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()
    
    if err := client.Initialize(); err != nil {
        log.Fatal(err)
    }
    
    // Call a tool
    response, err := client.CallTool("read_code", map[string]interface{}{
        "path":                    "src/main.zig",
        "include_semantic_context": true,
    })
    
    if err != nil {
        log.Fatal(err)
    }
    
    if response.Error != nil {
        log.Fatalf("Tool error: %s", response.Error.Message)
    }
    
    fmt.Printf("Response: %s\n", string(response.Result))
}
```

## Environment Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGRAMA_DB_PATH` | `./agrama.db` | Database file path |
| `AGRAMA_LOG_LEVEL` | `info` | Logging level (debug/info/warn/error) |
| `AGRAMA_MEMORY_LIMIT` | `1GB` | Maximum memory usage |
| `AGRAMA_PERFORMANCE_MODE` | `balanced` | Performance mode (low/balanced/high) |
| `AGRAMA_THREAD_POOL_SIZE` | `4` | Thread pool size for concurrent operations |

### Configuration Files

#### `.agrama.toml`

```toml
[database]
path = "./.agrama/database"
max_size = "10GB"
backup_enabled = true
backup_interval = "24h"

[performance]
mode = "high"           # low, balanced, high
memory_limit = "2GB"
thread_pool_size = 8
enable_caching = true

[features]
semantic_search = true
dependency_analysis = true
collaboration = true
real_time_sync = false

[logging]
level = "info"
file = "./.agrama/logs/server.log"
max_size = "100MB"
max_files = 5
```

#### Docker Configuration

```dockerfile
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache zig

# Copy Agrama binary
COPY zig-out/bin/agrama /usr/local/bin/agrama
RUN chmod +x /usr/local/bin/agrama

# Create data directory
RUN mkdir -p /data/.agrama

# Set environment
ENV AGRAMA_DB_PATH=/data/.agrama/database
ENV AGRAMA_LOG_LEVEL=info

# Expose MCP port (for future WebSocket support)
EXPOSE 8080

# Start server
CMD ["agrama", "mcp"]
```

## Best Practices

### Connection Management

```javascript
class ManagedMCPClient {
  constructor(serverPath, options = {}) {
    this.serverPath = serverPath;
    this.options = options;
    this.client = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 1000;
  }

  async ensureConnected() {
    if (!this.client || !this.client.isConnected()) {
      await this.connect();
    }
  }

  async connect() {
    try {
      this.client = new AgramaMCPClient(this.serverPath, this.options);
      await this.client.connect();
      this.reconnectAttempts = 0;
    } catch (error) {
      if (this.reconnectAttempts < this.maxReconnectAttempts) {
        this.reconnectAttempts++;
        const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
        setTimeout(() => this.connect(), delay);
      } else {
        throw error;
      }
    }
  }

  async callTool(name, args) {
    await this.ensureConnected();
    return this.client.callTool(name, args);
  }
}
```

### Error Handling

```python
import logging
from enum import Enum

class MCPErrorCode(Enum):
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    TOOL_ERROR = -32000

class MCPErrorHandler:
    def __init__(self):
        self.logger = logging.getLogger(__name__)

    def handle_error(self, error):
        """Handle MCP errors with appropriate recovery strategies"""
        code = error.get('code', 0)
        
        if code == MCPErrorCode.INVALID_PARAMS.value:
            self.logger.error(f"Invalid parameters: {error.get('message')}")
            # Validate and fix parameters
            return self.suggest_parameter_fix(error)
        
        elif code == MCPErrorCode.METHOD_NOT_FOUND.value:
            self.logger.error(f"Tool not found: {error.get('message')}")
            # List available tools
            return self.suggest_available_tools()
        
        elif code == MCPErrorCode.INTERNAL_ERROR.value:
            self.logger.error(f"Internal server error: {error.get('message')}")
            # Retry with backoff
            return {'retry': True, 'delay': 5}
        
        else:
            self.logger.error(f"Unknown error: {error}")
            return {'retry': False}
```

### Performance Optimization

```typescript
interface CacheEntry {
  result: any;
  timestamp: number;
  ttl: number;
}

class OptimizedMCPClient {
  private cache = new Map<string, CacheEntry>();
  private readonly CACHE_TTL = 5 * 60 * 1000; // 5 minutes

  async callToolCached(name: string, args: any): Promise<any> {
    const cacheKey = this.getCacheKey(name, args);
    
    // Check cache first
    const cached = this.getFromCache(cacheKey);
    if (cached) {
      return cached;
    }
    
    // Call tool and cache result
    const result = await this.callTool(name, args);
    this.setCache(cacheKey, result);
    
    return result;
  }

  private getCacheKey(name: string, args: any): string {
    return `${name}:${JSON.stringify(args)}`;
  }

  private getFromCache(key: string): any | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    
    const now = Date.now();
    if (now - entry.timestamp > entry.ttl) {
      this.cache.delete(key);
      return null;
    }
    
    return entry.result;
  }

  private setCache(key: string, result: any): void {
    this.cache.set(key, {
      result,
      timestamp: Date.now(),
      ttl: this.CACHE_TTL
    });
  }

  // Batch multiple tool calls
  async batchToolCalls(calls: Array<{name: string, args: any}>): Promise<any[]> {
    return Promise.all(
      calls.map(call => this.callToolCached(call.name, call.args))
    );
  }
}
```

## Troubleshooting

### Common Issues

#### Connection Failed

```bash
Error: spawn ENOENT
```

**Solution**: Ensure the Agrama binary is in PATH or use absolute path:

```javascript
// Instead of
const client = new AgramaMCPClient('agrama');

// Use
const client = new AgramaMCPClient('/absolute/path/to/zig-out/bin/agrama');
```

#### Tool Not Found

```json
{"error": {"code": -32601, "message": "Method not found"}}
```

**Solution**: Check available tools:

```javascript
const tools = await client.listTools();
console.log('Available tools:', tools.result.tools.map(t => t.name));
```

#### Invalid Parameters

```json
{"error": {"code": -32602, "message": "Invalid params"}}
```

**Solution**: Validate parameters against tool schema:

```javascript
// Check tool schema first
const tools = await client.listTools();
const readCodeTool = tools.result.tools.find(t => t.name === 'read_code');
console.log('Required parameters:', readCodeTool.inputSchema.required);
```

### Debug Mode

```bash
# Enable debug logging
AGRAMA_LOG_LEVEL=debug ./zig-out/bin/agrama mcp --verbose

# Save logs to file
AGRAMA_LOG_LEVEL=debug ./zig-out/bin/agrama mcp 2> debug.log
```

### Performance Monitoring

```bash
# Monitor performance metrics
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_performance_metrics","arguments":{"metric_types":["latency","memory"]}}}' | ./zig-out/bin/agrama mcp
```

This comprehensive integration guide provides everything needed to successfully integrate AI agents with the Agrama MCP server across different platforms and use cases.