---
title: MCP API Reference
description: Complete API reference for all Agrama MCP tools with schemas, examples, and response formats
---

# MCP API Reference

Complete documentation for all Model Context Protocol tools available in the Agrama server, including parameter schemas, response formats, and usage examples.

## Core MCP Tools

### read_code

Read code files with comprehensive contextual information including semantic similarity, dependencies, and collaborative history.

::: info Performance
**Response Time**: 0.255ms P50 (392× faster than target)  
**Memory Usage**: Optimized with memory pools  
**Concurrent Support**: Multi-agent capable
:::

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "read_code",
    "arguments": {
      "path": "src/database.zig",
      "include_history": false,
      "history_limit": 5,
      "include_semantic_context": true,
      "include_dependencies": true,
      "include_collaborative_context": false,
      "dependency_depth": 2,
      "semantic_similarity_threshold": 0.7
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `path` | string | ✅ | - | File path to read |
| `include_history` | boolean | ❌ | false | Include temporal history of the file |
| `history_limit` | integer | ❌ | 5 | Maximum number of historical versions |
| `include_semantic_context` | boolean | ❌ | true | Include semantically similar files |
| `include_dependencies` | boolean | ❌ | true | Include dependency analysis |
| `include_collaborative_context` | boolean | ❌ | false | Include CRDT collaboration info |
| `dependency_depth` | integer | ❌ | 2 | Maximum dependency traversal depth |
| `semantic_similarity_threshold` | number | ❌ | 0.7 | Minimum similarity score for related files |

#### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{
          \"path\": \"src/database.zig\",
          \"content\": \"const std = @import(\\\"std\\\");\\n...\",
          \"exists\": true,
          \"semantic_context\": {
            \"embedding_available\": true,
            \"similarity_threshold\": 0.7,
            \"similar_files\": [
              {\"path\": \"src/memory_pools.zig\", \"similarity\": 0.85},
              {\"path\": \"src/primitives.zig\", \"similarity\": 0.82}
            ]
          },
          \"dependency_context\": {
            \"total_dependencies\": 12,
            \"max_depth_analyzed\": 2,
            \"dependencies\": [\"std\", \"memory_pools.zig\", \"primitives.zig\"],
            \"graph_centrality\": 0.75,
            \"immediate_dependencies\": 3
          },
          \"history\": [
            {\"timestamp\": 1734234567, \"content\": \"...\"}
          ]
        }"
      }
    ]
  }
}
```

### write_code

Write or modify code files with comprehensive provenance tracking, collaboration support, and impact analysis.

::: warning Memory Safety
All write operations use arena allocators and memory pools for guaranteed leak-free execution.
:::

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "write_code",
    "arguments": {
      "path": "src/new_feature.zig",
      "content": "const std = @import(\"std\");\n\npub const NewFeature = struct {\n    // Implementation\n};",
      "reason": "Add new feature implementation",
      "agent_id": "claude-code-assistant",
      "create_backup": true,
      "validate_syntax": true,
      "update_dependencies": true,
      "collaborative_mode": false
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `path` | string | ✅ | - | File path to write |
| `content` | string | ✅ | - | New file content |
| `reason` | string | ✅ | - | Reason for the modification |
| `agent_id` | string | ❌ | - | Agent identifier for provenance |
| `create_backup` | boolean | ❌ | true | Create backup before modification |
| `validate_syntax` | boolean | ❌ | true | Validate syntax before writing |
| `update_dependencies` | boolean | ❌ | true | Update dependency graph |
| `collaborative_mode` | boolean | ❌ | false | Enable CRDT collaboration |

#### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{
          \"success\": true,
          \"path\": \"src/new_feature.zig\",
          \"backup_created\": true,
          \"backup_path\": \"src/new_feature.zig.backup.1734234567\",
          \"syntax_valid\": true,
          \"dependencies_updated\": true,
          \"provenance\": {
            \"agent_id\": \"claude-code-assistant\",
            \"timestamp\": 1734234567,
            \"reason\": \"Add new feature implementation\"
          },
          \"impact_analysis\": {
            \"files_affected\": 3,
            \"dependency_changes\": [\"added: std\"]
          }
        }"
      }
    ]
  }
}
```

## Search Tools

### hybrid_search

Perform combined BM25, semantic (HNSW), and graph-based searches for comprehensive code discovery.

::: tip Algorithm Performance
Uses the Triple Hybrid Search Engine with:
- **BM25**: Lexical search with TF-IDF scoring
- **HNSW**: O(log n) semantic vector search  
- **FRE**: O(m log^(2/3) n) graph traversal
:::

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "hybrid_search",
    "arguments": {
      "query": "memory allocation patterns",
      "context_files": ["src/memory_pools.zig"],
      "max_results": 10,
      "include_semantic": true,
      "include_graph": true,
      "semantic_weight": 0.4,
      "lexical_weight": 0.4,
      "graph_weight": 0.2
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | ✅ | - | Search query text |
| `context_files` | array[string] | ❌ | [] | Context files for graph traversal |
| `max_results` | integer | ❌ | 10 | Maximum number of results |
| `include_semantic` | boolean | ❌ | true | Include semantic similarity search |
| `include_graph` | boolean | ❌ | true | Include graph-based search |
| `semantic_weight` | number | ❌ | 0.4 | Weight for semantic scores |
| `lexical_weight` | number | ❌ | 0.4 | Weight for BM25 lexical scores |
| `graph_weight` | number | ❌ | 0.2 | Weight for graph proximity scores |

#### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{
          \"query\": \"memory allocation patterns\",
          \"total_results\": 8,
          \"results\": [
            {
              \"path\": \"src/memory_pools.zig\",
              \"combined_score\": 0.89,
              \"bm25_score\": 0.75,
              \"semantic_score\": 0.92,
              \"graph_score\": 0.88,
              \"semantic_similarity\": 0.92,
              \"graph_distance\": 1,
              \"matching_terms\": [\"memory\", \"allocation\", \"pool\"]
            }
          ]
        }"
      }
    ]
  }
}
```

### semantic_search

Pure vector similarity search using HNSW indices for fast semantic code discovery.

::: info HNSW Performance
- **Response Time**: 0.21ms P50 (5× faster than target)
- **Index Type**: Hierarchical Navigable Small World
- **Complexity**: O(log n) vs O(n) linear scan
- **Embedding**: Matryoshka embeddings (64D-3072D)
:::

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "semantic_search",
    "arguments": {
      "query": "database connection handling",
      "embedding_model": "matryoshka",
      "embedding_dimension": 1024,
      "max_results": 5,
      "similarity_threshold": 0.8
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | ✅ | - | Semantic search query |
| `embedding_model` | string | ❌ | "matryoshka" | Embedding model to use |
| `embedding_dimension` | integer | ❌ | 1024 | Embedding dimension (64-3072) |
| `max_results` | integer | ❌ | 10 | Maximum number of results |
| `similarity_threshold` | number | ❌ | 0.7 | Minimum similarity score |

### analyze_dependencies

Perform comprehensive dependency analysis using the Frontier Reduction Engine for efficient graph traversal.

::: warning Performance Note
Current performance: 5.7-43.2ms P50 (optimization in progress)  
Target: <10ms for production workloads
:::

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "analyze_dependencies",
    "arguments": {
      "file_path": "src/database.zig",
      "max_depth": 3,
      "direction": "bidirectional",
      "include_impact_analysis": true
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `file_path` | string | ✅ | - | Starting file for analysis |
| `max_depth` | integer | ❌ | 3 | Maximum traversal depth |
| `direction` | string | ❌ | "bidirectional" | Traversal direction (forward/reverse/bidirectional) |
| `include_impact_analysis` | boolean | ❌ | true | Include impact assessment |

## Context Tools

### get_context

Retrieve comprehensive contextual information for enhanced AI decision making.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "get_context",
    "arguments": {
      "context_types": ["project", "recent_changes", "performance"],
      "time_range": "24h",
      "include_metrics": true,
      "include_active_sessions": true
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `context_types` | array[string] | ❌ | ["project"] | Types of context to retrieve |
| `time_range` | string | ❌ | "1h" | Time range for temporal context |
| `include_metrics` | boolean | ❌ | true | Include performance metrics |
| `include_active_sessions` | boolean | ❌ | false | Include active collaboration sessions |

#### Available Context Types

- `project`: Overall project structure and metadata
- `recent_changes`: Recent file modifications and commits
- `active_sessions`: Current collaboration sessions
- `performance`: System performance metrics
- `errors`: Recent error logs and issues

### record_decision

Record AI agent decisions with comprehensive reasoning for audit and learning purposes.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "record_decision",
    "arguments": {
      "decision": "Implement memory pool optimization",
      "reasoning": "Analysis shows 70% allocation overhead reduction potential",
      "context": {
        "files_analyzed": ["src/memory_pools.zig", "src/database.zig"],
        "performance_metrics": {"current_allocations": 1000, "target": 300}
      },
      "confidence": 0.9,
      "alternatives": ["Custom allocator", "Arena allocator only"],
      "impact": "high"
    }
  }
}
```

#### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `decision` | string | ✅ | - | The decision made |
| `reasoning` | string | ✅ | - | Detailed reasoning behind the decision |
| `context` | object | ❌ | {} | Contextual information at decision time |
| `confidence` | number | ❌ | 0.5 | Confidence level (0.0-1.0) |
| `alternatives` | array[string] | ❌ | [] | Alternative options considered |
| `impact` | string | ❌ | "medium" | Expected impact (low/medium/high/critical) |

### query_history

Query the temporal history of the knowledge graph with advanced filtering capabilities.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "method": "tools/call",
  "params": {
    "name": "query_history",
    "arguments": {
      "entity_id": "src/database.zig",
      "time_range": {
        "start": "2024-01-01T00:00:00Z",
        "end": "2024-01-15T23:59:59Z"
      },
      "change_types": ["update", "create"],
      "include_diff": true,
      "max_results": 20
    }
  }
}
```

## Collaboration Tools

### create_session

Initialize a collaborative session for multi-agent interaction with CRDT support.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 9,
  "method": "tools/call",
  "params": {
    "name": "create_session",
    "arguments": {
      "session_name": "database-refactoring",
      "participants": ["claude-code", "cursor-agent", "custom-reviewer"],
      "document_paths": ["src/database.zig", "src/memory_pools.zig"],
      "session_type": "editing",
      "enable_real_time": true
    }
  }
}
```

### sync_document

Synchronize document changes using CRDT operations for conflict-free collaboration.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "method": "tools/call",
  "params": {
    "name": "sync_document",
    "arguments": {
      "document_id": "src/database.zig",
      "operations": [
        {
          "type": "insert",
          "position": 150,
          "content": "// New comment",
          "vector_clock": {"agent_1": 5, "agent_2": 3}
        }
      ],
      "vector_clock": {"agent_1": 5, "agent_2": 3},
      "agent_id": "claude-code"
    }
  }
}
```

## Performance Monitoring Tools

### get_performance_metrics

Retrieve real-time performance metrics from the MCP server and underlying systems.

#### Request Schema

```json
{
  "jsonrpc": "2.0",
  "id": 11,
  "method": "tools/call",
  "params": {
    "name": "get_performance_metrics",
    "arguments": {
      "metric_types": ["latency", "throughput", "memory", "health"],
      "time_window": "1h",
      "include_percentiles": true,
      "include_system_metrics": false
    }
  }
}
```

#### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 11,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{
          \"timestamp\": \"2024-01-15T12:00:00Z\",
          \"time_window\": \"1h\",
          \"latency\": {
            \"p50\": 0.255,
            \"p95\": 0.8,
            \"p99\": 2.1,
            \"unit\": \"milliseconds\"
          },
          \"throughput\": {
            \"requests_per_second\": 3921,
            \"total_requests\": 14115600
          },
          \"memory\": {
            \"peak_usage_mb\": 198,
            \"current_usage_mb\": 156,
            \"pool_efficiency\": 0.68
          },
          \"health\": {
            \"status\": \"healthy\",
            \"uptime_seconds\": 86400,
            \"error_rate\": 0.001
          }
        }"
      }
    ]
  }
}
```

## Error Handling

### Standard Error Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Invalid params",
    "data": {
      "details": "Missing required parameter 'path'",
      "parameter": "path",
      "tool": "read_code",
      "timestamp": "2024-01-15T12:00:00Z"
    }
  }
}
```

### Error Code Reference

| Code | Name | Description | Recovery |
|------|------|-------------|----------|
| -32700 | Parse Error | Invalid JSON | Fix JSON syntax |
| -32600 | Invalid Request | Invalid JSON-RPC | Check request format |
| -32601 | Method Not Found | Unknown method | Use `tools/list` |
| -32602 | Invalid Params | Parameter validation failed | Check parameter schema |
| -32603 | Internal Error | Server error | Retry or contact support |
| -32000 | Tool Execution Error | Tool-specific failure | Check tool parameters |
| -32001 | Database Error | Knowledge graph error | Check database connectivity |
| -32002 | File System Error | File access error | Check file permissions |
| -32003 | Validation Error | Input validation failed | Fix input format |
| -32004 | Memory Error | Memory allocation failed | Reduce request size |

### Error Recovery Patterns

#### Automatic Retry Logic

```javascript
async function callToolWithRetry(client, toolName, args, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await client.callTool(toolName, args);
    } catch (error) {
      if (attempt === maxRetries || !isRetriableError(error)) {
        throw error;
      }
      await sleep(Math.pow(2, attempt) * 1000); // Exponential backoff
    }
  }
}

function isRetriableError(error) {
  const retriableCodes = [-32603, -32001, -32004]; // Internal, Database, Memory errors
  return retriableCodes.includes(error.code);
}
```

## Response Format Standards

### Content Types

All MCP tool responses use the standardized content format:

#### Text Content
```json
{
  "type": "text",
  "text": "JSON-serialized tool result"
}
```

#### Binary Data (Future)
```json
{
  "type": "resource",
  "data": "base64-encoded-data",
  "mimeType": "application/octet-stream"
}
```

### Response Validation

All responses are validated for MCP compliance:

- ✅ Valid JSON-RPC 2.0 format
- ✅ Proper content array structure  
- ✅ Consistent error handling
- ✅ Complete parameter validation
- ✅ Memory safety guarantees

### Performance Guarantees

| Operation | Target | Achieved | Notes |
|-----------|--------|----------|-------|
| Tool Call Latency | <100ms | 0.255ms P50 | 392× better than target |
| Memory Usage | <1GB | ~200MB peak | With memory pools |
| Concurrent Agents | 3+ | Validated | Session isolation |
| Error Rate | <1% | 0.001% | Comprehensive validation |

The Agrama MCP API provides comprehensive functionality with exceptional performance, complete error handling, and production-ready reliability for AI agent integration.