---
title: MCP Tool Reference
description: Comprehensive documentation for all MCP tools with usage examples and parameter schemas
---

# MCP Tool Reference

This document provides comprehensive documentation for all MCP tools available in the Agrama server, including usage examples, parameter schemas, and integration patterns.

## Core MCP Tools

### read_code

Read code files with comprehensive contextual information including semantic similarity, dependencies, and collaborative history.

**Performance**: 0.255ms P50 response time

#### Schema

```json
{
  "name": "read_code",
  "title": "Read Code with Context",
  "description": "Read code files with comprehensive context including semantic similarity, dependencies, and collaborative information",
  "inputSchema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "File path to read"
      },
      "include_history": {
        "type": "boolean",
        "default": false,
        "description": "Include temporal history of the file"
      },
      "history_limit": {
        "type": "integer",
        "default": 5,
        "description": "Maximum number of historical versions to include"
      },
      "include_semantic_context": {
        "type": "boolean",
        "default": true,
        "description": "Include semantically similar files"
      },
      "include_dependencies": {
        "type": "boolean",
        "default": true,
        "description": "Include dependency analysis"
      },
      "semantic_similarity_threshold": {
        "type": "number",
        "default": 0.7,
        "description": "Minimum similarity score for related files"
      }
    },
    "required": ["path"]
  }
}
```

#### Example Usage

```json
{
  "jsonrpc": "2.0",
  "id": 1,
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

#### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\n  \"path\": \"src/database.zig\",\n  \"content\": \"const std = @import(\\\"std\\\");\n...\",\n  \"exists\": true,\n  \"semantic_context\": {\n    \"similar_files\": [\n      {\"path\": \"src/memory_pools.zig\", \"similarity\": 0.85},\n      {\"path\": \"src/primitives.zig\", \"similarity\": 0.82}\n    ]\n  },\n  \"dependencies\": {\n    \"imports\": [\"std\", \"memory_pools.zig\"],\n    \"exports\": [\"Database\", \"TemporalNode\"]\n  }\n}"
      }
    ]
  }
}
```

### write_code

Modify code files with comprehensive provenance tracking, collaboration support, and impact analysis.

**Performance**: Sub-millisecond response with database persistence

#### Schema

```json
{
  "name": "write_code",
  "title": "Write Code with Provenance",
  "description": "Write or modify code files with provenance tracking and collaborative support",
  "inputSchema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "File path to write"
      },
      "content": {
        "type": "string",
        "description": "New file content"
      },
      "reason": {
        "type": "string",
        "description": "Reason for the modification"
      },
      "agent_id": {
        "type": "string",
        "description": "Agent identifier for provenance"
      },
      "create_backup": {
        "type": "boolean",
        "default": true,
        "description": "Create backup before modification"
      },
      "validate_syntax": {
        "type": "boolean",
        "default": true,
        "description": "Validate syntax before writing"
      },
      "update_dependencies": {
        "type": "boolean",
        "default": true,
        "description": "Update dependency graph"
      }
    },
    "required": ["path", "content", "reason"]
  }
}
```

#### Example Usage

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "write_code",
    "arguments": {
      "path": "src/new_feature.zig",
      "content": "const std = @import(\"std\");\n\npub const NewFeature = struct {\n    // Implementation\n};\n",
      "reason": "Add new feature implementation",
      "agent_id": "claude-code-assistant",
      "validate_syntax": true
    }
  }
}
```

### analyze_dependencies

Perform comprehensive dependency analysis using the Frontier Reduction Engine for efficient graph traversal.

**Performance**: Variable (5.7-43.2ms P50, optimization in progress)

#### Schema

```json
{
  "name": "analyze_dependencies",
  "title": "Analyze Dependencies",
  "description": "Analyze code dependencies using advanced graph traversal algorithms",
  "inputSchema": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Starting file path for analysis"
      },
      "analysis_type": {
        "type": "string",
        "enum": ["imports", "exports", "circular", "impact", "full"],
        "default": "full",
        "description": "Type of dependency analysis"
      },
      "max_depth": {
        "type": "integer",
        "default": 5,
        "description": "Maximum traversal depth"
      },
      "include_external": {
        "type": "boolean",
        "default": false,
        "description": "Include external dependencies"
      },
      "algorithm": {
        "type": "string",
        "enum": ["fre", "dijkstra", "dfs"],
        "default": "fre",
        "description": "Graph traversal algorithm to use"
      }
    },
    "required": ["path"]
  }
}
```

### get_context

Retrieve comprehensive contextual information for enhanced AI decision making.

**Performance**: Sub-millisecond for most context types

#### Schema

```json
{
  "name": "get_context",
  "title": "Get Contextual Information",
  "description": "Retrieve comprehensive contextual information for AI decision making",
  "inputSchema": {
    "type": "object",
    "properties": {
      "context_types": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["project", "recent_changes", "active_sessions", "performance", "errors"]
        },
        "description": "Types of context to retrieve"
      },
      "time_range": {
        "type": "string",
        "description": "Time range for temporal context (e.g., '1h', '1d', '1w')"
      },
      "include_metrics": {
        "type": "boolean",
        "default": true,
        "description": "Include performance metrics"
      }
    }
  }
}
```

### record_decision

Record AI agent decisions with comprehensive reasoning for audit and learning purposes.

#### Schema

```json
{
  "name": "record_decision",
  "title": "Record Decision",
  "description": "Record AI agent decisions with reasoning for audit and learning",
  "inputSchema": {
    "type": "object",
    "properties": {
      "decision": {
        "type": "string",
        "description": "The decision made"
      },
      "reasoning": {
        "type": "string",
        "description": "Detailed reasoning behind the decision"
      },
      "context": {
        "type": "object",
        "description": "Contextual information at decision time"
      },
      "confidence": {
        "type": "number",
        "minimum": 0.0,
        "maximum": 1.0,
        "description": "Confidence level in the decision"
      },
      "alternatives": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Alternative options considered"
      },
      "impact": {
        "type": "string",
        "enum": ["low", "medium", "high", "critical"],
        "description": "Expected impact of the decision"
      }
    },
    "required": ["decision", "reasoning"]
  }
}
```

## Search Tools

### hybrid_search

Perform combined semantic and graph-based searches for comprehensive code discovery.

**Performance**: 163ms P50 (optimization in progress - target <10ms)

#### Schema

```json
{
  "name": "hybrid_search",
  "title": "Hybrid Search",
  "description": "Combined semantic and graph-based search with advanced ranking",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search query text"
      },
      "max_results": {
        "type": "integer",
        "default": 10,
        "description": "Maximum number of results"
      },
      "search_types": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["semantic", "graph", "dependency", "temporal"]
        },
        "default": ["semantic", "graph"],
        "description": "Types of search to perform"
      },
      "semantic_threshold": {
        "type": "number",
        "default": 0.7,
        "description": "Minimum semantic similarity threshold"
      },
      "time_range": {
        "type": "string",
        "description": "Temporal search range"
      }
    },
    "required": ["query"]
  }
}
```

### semantic_search

Pure vector similarity search using HNSW indices for fast semantic code discovery.

**Performance**: 0.21ms P50 (5× faster than target)

#### Schema

```json
{
  "name": "semantic_search",
  "title": "Semantic Search",
  "description": "Vector similarity search using HNSW indices for semantic code discovery",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Semantic search query"
      },
      "embedding_model": {
        "type": "string",
        "default": "matryoshka",
        "description": "Embedding model to use"
      },
      "embedding_dimension": {
        "type": "integer",
        "enum": [64, 128, 256, 512, 1024, 2048, 3072],
        "default": 1024,
        "description": "Embedding dimension for search"
      },
      "max_results": {
        "type": "integer",
        "default": 10,
        "description": "Maximum number of results"
      },
      "similarity_threshold": {
        "type": "number",
        "default": 0.7,
        "description": "Minimum similarity score"
      }
    },
    "required": ["query"]
  }
}
```

### graph_search

Pure graph traversal search using the Frontier Reduction Engine for dependency and relationship discovery.

#### Schema

```json
{
  "name": "graph_search",
  "title": "Graph Search",
  "description": "Graph traversal search using FRE for dependency and relationship discovery",
  "inputSchema": {
    "type": "object",
    "properties": {
      "start_nodes": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Starting nodes for traversal"
      },
      "relationship_types": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["imports", "exports", "calls", "extends", "implements"]
        },
        "description": "Types of relationships to traverse"
      },
      "max_depth": {
        "type": "integer",
        "default": 5,
        "description": "Maximum traversal depth"
      },
      "algorithm": {
        "type": "string",
        "enum": ["fre", "dijkstra", "bfs"],
        "default": "fre",
        "description": "Graph traversal algorithm"
      },
      "direction": {
        "type": "string",
        "enum": ["forward", "backward", "both"],
        "default": "both",
        "description": "Traversal direction"
      }
    },
    "required": ["start_nodes"]
  }
}
```

## Collaboration Tools

### create_session

Initialize a collaborative session for multi-agent interaction with CRDT support.

#### Schema

```json
{
  "name": "create_session",
  "title": "Create Collaboration Session",
  "description": "Initialize a collaborative session for multi-agent interaction",
  "inputSchema": {
    "type": "object",
    "properties": {
      "session_name": {
        "type": "string",
        "description": "Name for the collaboration session"
      },
      "participants": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Agent IDs to include in session"
      },
      "document_paths": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Files to include in collaborative editing"
      },
      "session_type": {
        "type": "string",
        "enum": ["editing", "analysis", "review"],
        "default": "editing",
        "description": "Type of collaboration session"
      }
    },
    "required": ["session_name"]
  }
}
```

### sync_document

Synchronize document changes using CRDT operations for conflict-free collaboration.

#### Schema

```json
{
  "name": "sync_document",
  "title": "Synchronize Document",
  "description": "Synchronize document changes using CRDT operations",
  "inputSchema": {
    "type": "object",
    "properties": {
      "document_id": {
        "type": "string",
        "description": "Document identifier"
      },
      "operations": {
        "type": "array",
        "items": {"type": "object"},
        "description": "CRDT operations to apply"
      },
      "vector_clock": {
        "type": "object",
        "description": "Vector clock for operation ordering"
      },
      "agent_id": {
        "type": "string",
        "description": "Agent making the changes"
      }
    },
    "required": ["document_id", "operations", "agent_id"]
  }
}
```

## Advanced Tools

### query_history

Query the temporal history of the knowledge graph with advanced filtering capabilities.

#### Schema

```json
{
  "name": "query_history",
  "title": "Query History",
  "description": "Query temporal history with advanced filtering capabilities",
  "inputSchema": {
    "type": "object",
    "properties": {
      "entity_id": {
        "type": "string",
        "description": "Entity to query history for"
      },
      "time_range": {
        "type": "object",
        "properties": {
          "start": {"type": "string"},
          "end": {"type": "string"}
        },
        "description": "Time range for history query"
      },
      "change_types": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["create", "update", "delete", "move", "rename"]
        },
        "description": "Types of changes to include"
      },
      "include_diff": {
        "type": "boolean",
        "default": true,
        "description": "Include content diffs"
      }
    }
  }
}
```

## Performance Monitoring Tools

### get_performance_metrics

Retrieve real-time performance metrics from the MCP server and underlying systems.

#### Schema

```json
{
  "name": "get_performance_metrics",
  "title": "Get Performance Metrics",
  "description": "Retrieve real-time performance metrics and system health",
  "inputSchema": {
    "type": "object",
    "properties": {
      "metric_types": {
        "type": "array",
        "items": {
          "type": "string",
          "enum": ["latency", "throughput", "memory", "errors", "health"]
        },
        "default": ["latency", "throughput", "health"],
        "description": "Types of metrics to retrieve"
      },
      "time_window": {
        "type": "string",
        "default": "1h",
        "description": "Time window for metrics aggregation"
      },
      "include_percentiles": {
        "type": "boolean",
        "default": true,
        "description": "Include latency percentiles"
      }
    }
  }
}
```

## Error Handling

All tools follow consistent error handling patterns:

### Error Response Format

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
      "tool": "read_code"
    }
  }
}
```

### Common Error Codes

| Code | Name | Description |
|------|------|-------------|
| -32700 | Parse Error | Invalid JSON |
| -32600 | Invalid Request | Invalid JSON-RPC request |
| -32601 | Method Not Found | Tool not found |
| -32602 | Invalid Params | Invalid parameters |
| -32603 | Internal Error | Server error |
| -32000 | Tool Error | Tool-specific error |

## Best Practices

### Parameter Validation
- Always provide required parameters
- Use appropriate data types
- Respect parameter constraints and enums
- Include meaningful descriptions in requests

### Performance Optimization
- Use appropriate search thresholds
- Limit result counts for large datasets
- Leverage caching through repeated queries
- Monitor performance metrics

### Collaboration Patterns
- Initialize sessions before collaborative editing
- Use proper agent identification
- Synchronize documents regularly
- Handle conflicts gracefully

### Error Recovery
- Implement retry logic for transient errors
- Validate responses before processing
- Log errors for debugging
- Provide fallback mechanisms

The Agrama MCP tools provide unprecedented capabilities for AI agent collaboration with exceptional performance and comprehensive functionality.