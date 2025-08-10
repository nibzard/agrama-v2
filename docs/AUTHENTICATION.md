# Agrama Authentication System

This document provides comprehensive guidance on deploying and using the Agrama MCP Server authentication system.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [API Key Management](#api-key-management)
- [Role-Based Access Control](#role-based-access-control)
- [Production Deployment](#production-deployment)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

The Agrama authentication system provides comprehensive security for MCP (Model Context Protocol) operations including:

- **API Key Authentication** - Secure API keys with role-based permissions
- **JWT Token Support** - Industry-standard JWT tokens for authentication
- **Role-Based Access Control** - Fine-grained permissions for different user types
- **Rate Limiting** - Protection against abuse and DoS attacks
- **Audit Logging** - Complete audit trail of all authentication events
- **WebSocket Security** - Authenticated real-time connections

### Supported Authentication Methods

1. **API Key** - Simple and secure API key in `X-API-Key` header
2. **Bearer Token** - JWT tokens in `Authorization: Bearer <token>` header
3. **Development Mode** - Bypass authentication for development (not for production)

## Quick Start

### 1. Development Setup (No Authentication)

For local development, you can disable authentication:

```bash
# Start server with authentication disabled
agrama serve --no-auth --port 8080

# Or enable development mode with relaxed security
agrama serve --dev-mode --port 8080
```

### 2. Basic Production Setup

```bash
# Set environment variables
export AGRAMA_AUTH_ENABLED=true
export AGRAMA_API_KEY="your-secret-api-key-here"
export AGRAMA_API_KEY_NAME="MyApplication"
export AGRAMA_API_KEY_ROLE="developer"

# Start authenticated server
agrama serve --port 8080
```

### 3. Test Authentication

```bash
# Test with curl
curl -H "X-API-Key: your-secret-api-key-here" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' \
     http://localhost:8080/mcp
```

## Configuration

### Environment Variables

#### Core Authentication Settings

```bash
# Enable/disable authentication (default: true)
export AGRAMA_AUTH_ENABLED=true

# Development mode - bypasses authentication (default: false)
export AGRAMA_DEV_MODE=false

# Require HTTPS connections (default: true)
export AGRAMA_REQUIRE_HTTPS=true

# Enable rate limiting (default: true)  
export AGRAMA_RATE_LIMITING=true

# Enable audit logging (default: true)
export AGRAMA_AUDIT_LOGGING=true
```

#### JWT Configuration

```bash
# JWT signing secret (minimum 32 characters)
export AGRAMA_JWT_SECRET="your-super-secret-jwt-key-minimum-32-characters"

# JWT issuer claim (default: "agrama-codegraph")
export AGRAMA_JWT_ISSUER="your-organization"

# JWT audience claim (default: "mcp-tools") 
export AGRAMA_JWT_AUDIENCE="your-application"
```

#### Security Settings

```bash
# Maximum failed authentication attempts before lockout (default: 5)
export AGRAMA_MAX_FAILED_ATTEMPTS=5

# Account lockout duration in minutes (default: 15)
export AGRAMA_LOCKOUT_DURATION_MINUTES=15

# Custom header names (optional)
export AGRAMA_API_KEY_HEADER="X-API-Key"
export AGRAMA_BEARER_TOKEN_HEADER="Authorization"
```

## API Key Management

### Single API Key

```bash
export AGRAMA_API_KEY="your-secret-api-key"
export AGRAMA_API_KEY_NAME="MyApplication" 
export AGRAMA_API_KEY_ROLE="developer"
export AGRAMA_API_KEY_EXPIRES="1672531200"  # Optional: Unix timestamp
export AGRAMA_API_KEY_TOOLS="read_code,write_code,get_context"  # Optional: specific tools
export AGRAMA_API_KEY_RATE_LIMIT="1000"  # Optional: requests per hour
```

### Multiple API Keys

```bash
# Format: key:name:role[:expires[:tools[:rate_limit]]]
export AGRAMA_API_KEYS="key1:App1:admin:1672531200,key2:App2:developer:,key3:App3:read_only"
```

### API Key Examples

```bash
# Production admin key with expiration
export AGRAMA_API_KEYS="prod-admin-key-123:ProdAdmin:admin:1672531200"

# Development keys with different permissions
export AGRAMA_API_KEYS="dev-key-456:DevApp:developer:,readonly-key-789:Analytics:read_only:"

# Restricted key with specific tools
export AGRAMA_API_KEYS="restricted-key-abc:SpecialApp:restricted::read_code,get_context:100"
```

## Role-Based Access Control

### Available Roles

#### Admin Role
- **Access**: Full access to all operations and administrative functions
- **Default Rate Limit**: 10,000 requests/hour
- **Can Access**:
  - All MCP tools
  - Server management endpoints
  - User and agent management
  - Security reports and audit logs

#### Developer Role  
- **Access**: Read/write access to code operations and collaborative tools
- **Default Rate Limit**: 1,000 requests/hour
- **Can Access**:
  - `read_code`, `write_code`
  - `get_context`, `get_collaborative_context`
  - `update_cursor`
  - All collaborative editing tools

#### Read-Only Role
- **Access**: Read-only access to analysis and context tools
- **Default Rate Limit**: 500 requests/hour
- **Can Access**:
  - `read_code`, `get_context`
  - Analysis and inspection tools
  - Metrics and statistics (non-sensitive)

#### Restricted Role
- **Access**: Limited access based on explicit tool allowlist
- **Default Rate Limit**: 100 requests/hour  
- **Can Access**: Only tools specified in `allowed_tools` list

### Tool-Specific Permissions

The system automatically configures security for standard MCP tools:

```bash
# Read operations (read_only role minimum)
read_code
get_context  
read_code_collaborative

# Write operations (developer role minimum)
write_code
write_code_collaborative

# Administrative operations (admin role only)
get_server_stats
manage_agents

# Collaborative tools (developer role minimum)
update_cursor
get_collaborative_context
```

## Production Deployment

### 1. Generate Strong JWT Secret

```bash
# Generate a secure random secret
export AGRAMA_JWT_SECRET=$(openssl rand -base64 32)
```

### 2. Configure TLS/SSL

```bash
export AGRAMA_TLS_CERT_PATH="/etc/ssl/certs/agrama.pem"
export AGRAMA_TLS_KEY_PATH="/etc/ssl/private/agrama.key"
export AGRAMA_REQUIRE_HTTPS=true
```

### 3. Production Environment Variables

```bash
#!/bin/bash
# Production configuration

# Authentication
export AGRAMA_AUTH_ENABLED=true
export AGRAMA_DEV_MODE=false
export AGRAMA_REQUIRE_HTTPS=true

# JWT Configuration
export AGRAMA_JWT_SECRET="your-production-jwt-secret-32-chars-minimum"
export AGRAMA_JWT_ISSUER="your-organization-prod"

# API Keys (replace with your actual keys)
export AGRAMA_API_KEYS="prod-admin:ProductionAdmin:admin:1672531200,app-dev:AppDeveloper:developer:,analytics:AnalyticsService:read_only:"

# Security Settings
export AGRAMA_MAX_FAILED_ATTEMPTS=5
export AGRAMA_LOCKOUT_DURATION_MINUTES=15
export AGRAMA_RATE_LIMITING=true
export AGRAMA_AUDIT_LOGGING=true

# TLS Settings
export AGRAMA_TLS_CERT_PATH="/path/to/your/cert.pem"
export AGRAMA_TLS_KEY_PATH="/path/to/your/private.key"

# Monitoring
export AGRAMA_METRICS_ENABLED=true
export AGRAMA_ALERT_FAILED_AUTH_THRESHOLD=10
export AGRAMA_ALERT_WEBHOOK_URL="https://your-monitoring.com/webhooks/security"

# Logging
export AGRAMA_LOG_LEVEL="info"

# Start server
agrama serve --port 8080
```

### 4. Docker Deployment

```dockerfile
FROM zig:latest as builder

# Build application
WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseSafe

FROM debian:bullseye-slim

# Install CA certificates for HTTPS
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy binary
COPY --from=builder /app/zig-out/bin/agrama /usr/local/bin/

# Create non-root user
RUN useradd -r -s /bin/false agrama

# Set up SSL certificates directory
RUN mkdir -p /etc/ssl/agrama && chown agrama:agrama /etc/ssl/agrama

USER agrama

EXPOSE 8080

# Production-ready command
CMD ["agrama", "serve", "--port", "8080"]
```

### 5. Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agrama-mcp-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: agrama-mcp-server
  template:
    metadata:
      labels:
        app: agrama-mcp-server
    spec:
      containers:
      - name: agrama
        image: agrama-mcp-server:latest
        ports:
        - containerPort: 8080
        env:
        - name: AGRAMA_AUTH_ENABLED
          value: "true"
        - name: AGRAMA_JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: agrama-secrets
              key: jwt-secret
        - name: AGRAMA_API_KEYS
          valueFrom:
            secretKeyRef:
              name: agrama-secrets
              key: api-keys
        - name: AGRAMA_LOG_LEVEL
          value: "info"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready  
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: agrama-mcp-service
spec:
  selector:
    app: agrama-mcp-server
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  type: LoadBalancer
```

## Security Best Practices

### 1. API Key Security

```bash
# Generate strong API keys
openssl rand -hex 32

# Use different keys for different environments
PROD_KEY=$(openssl rand -hex 32)
DEV_KEY=$(openssl rand -hex 32)  
TEST_KEY=$(openssl rand -hex 32)

# Set appropriate expiration dates
EXPIRES_NEXT_YEAR=$(($(date +%s) + 31536000))  # 1 year from now
```

### 2. JWT Token Security

```bash
# Generate strong JWT secret
export AGRAMA_JWT_SECRET=$(openssl rand -base64 32)

# Use environment-specific issuer/audience
export AGRAMA_JWT_ISSUER="agrama-production"
export AGRAMA_JWT_AUDIENCE="mcp-tools-prod"
```

### 3. Network Security

```bash
# Always use HTTPS in production
export AGRAMA_REQUIRE_HTTPS=true

# Configure proper TLS certificates
export AGRAMA_TLS_CERT_PATH="/etc/ssl/certs/agrama.pem"
export AGRAMA_TLS_KEY_PATH="/etc/ssl/private/agrama.key"

# Enable security headers
export AGRAMA_SECURITY_HEADERS=true
```

### 4. Monitoring and Alerting

```bash
# Enable comprehensive logging
export AGRAMA_AUDIT_LOGGING=true
export AGRAMA_LOG_LEVEL="info"

# Configure security alerts
export AGRAMA_ALERT_FAILED_AUTH_THRESHOLD=10
export AGRAMA_ALERT_WEBHOOK_URL="https://your-alerting-system.com/webhook"

# Enable metrics
export AGRAMA_METRICS_ENABLED=true
```

### 5. Rate Limiting

```bash
# Enable rate limiting
export AGRAMA_RATE_LIMITING=true

# Configure appropriate limits per role
# Admin: 10,000/hour, Developer: 1,000/hour, Read-only: 500/hour, Restricted: 100/hour

# Set lockout policies
export AGRAMA_MAX_FAILED_ATTEMPTS=5
export AGRAMA_LOCKOUT_DURATION_MINUTES=15
```

## Client Authentication Examples

### 1. API Key Authentication

```javascript
// JavaScript/Node.js
const fetch = require('node-fetch');

async function callMCPTool(toolName, args) {
    const response = await fetch('https://your-agrama-server.com/mcp', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-API-Key': 'your-api-key-here'
        },
        body: JSON.stringify({
            jsonrpc: '2.0',
            id: '1',
            method: 'tools/call',
            params: {
                name: toolName,
                arguments: args
            }
        })
    });
    
    return await response.json();
}

// Example usage
const result = await callMCPTool('read_code', { path: 'src/main.zig' });
```

### 2. Bearer Token Authentication

```python
# Python
import requests
import json

def call_mcp_tool(tool_name, args, jwt_token):
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {jwt_token}'
    }
    
    payload = {
        'jsonrpc': '2.0',
        'id': '1',
        'method': 'tools/call',
        'params': {
            'name': tool_name,
            'arguments': args
        }
    }
    
    response = requests.post(
        'https://your-agrama-server.com/mcp',
        headers=headers,
        data=json.dumps(payload)
    )
    
    return response.json()

# Example usage  
result = call_mcp_tool('write_code', {
    'path': 'src/new_feature.zig',
    'content': 'const std = @import("std");'
}, jwt_token='your-jwt-token-here')
```

### 3. WebSocket Authentication

```javascript
// WebSocket with authentication
const WebSocket = require('ws');

const ws = new WebSocket('wss://your-agrama-server.com:8080', {
    headers: {
        'X-API-Key': 'your-api-key-here'
    }
});

ws.on('open', function open() {
    console.log('Authenticated WebSocket connection established');
});

ws.on('message', function message(data) {
    const event = JSON.parse(data);
    console.log('Received event:', event);
});

ws.on('error', function error(err) {
    console.error('WebSocket error:', err);
});
```

## Troubleshooting

### Common Issues

#### 1. Authentication Failed

```bash
# Check API key format
curl -v -H "X-API-Key: your-key" http://localhost:8080/mcp

# Check environment variables
env | grep AGRAMA

# Check server logs
agrama serve --port 8080  # Look for authentication errors
```

#### 2. Permission Denied

```bash
# Check user role and tool permissions
# Admin can access all tools
# Developer can access read_code, write_code
# Read-only can only access read_code, get_context
# Restricted needs explicit tool allowlist
```

#### 3. Rate Limited

```bash
# Check rate limiting settings
export AGRAMA_RATE_LIMITING=false  # Temporarily disable for testing

# Increase rate limits for your role
export AGRAMA_API_KEYS="your-key:YourApp:developer::your-tools:10000"
```

#### 4. WebSocket Authentication Failed

```bash
# Ensure authentication header is included in WebSocket handshake
# Check that API key has appropriate permissions
# Verify WebSocket endpoint is correct (ws:// vs wss://)
```

### Debug Mode

```bash
# Enable debug logging
export AGRAMA_LOG_LEVEL=debug

# Disable authentication for testing
export AGRAMA_AUTH_ENABLED=false

# Enable development mode
export AGRAMA_DEV_MODE=true
```

### Security Audit

```bash
# Get security statistics
curl -H "X-API-Key: admin-key" http://localhost:8080/security/stats

# Get security report with recommendations  
curl -H "X-API-Key: admin-key" http://localhost:8080/security/report

# View audit log (admin only)
curl -H "X-API-Key: admin-key" http://localhost:8080/security/audit?limit=100
```

### Performance Monitoring

```bash
# Monitor authentication performance
# Target: <1ms per authentication
# Target: <100ms for MCP tool calls

# Check rate limiting effectiveness
# Monitor failed authentication patterns
# Track API key usage patterns
```

## Advanced Configuration

### Custom Tool Security

You can configure custom security settings for specific tools:

```zig
// In your server initialization code
try authenticated_server.addToolSecurity("custom_tool", .admin, 10, .detailed);
```

### JWT Token Generation

For generating JWT tokens programmatically:

```python
import jwt
import time

# JWT payload
payload = {
    'sub': 'user123',
    'iss': 'agrama-codegraph',
    'aud': 'mcp-tools', 
    'exp': int(time.time()) + 3600,  # 1 hour expiration
    'iat': int(time.time()),
    'role': 'developer'
}

# Generate token
token = jwt.encode(payload, 'your-jwt-secret', algorithm='HS256')
```

### Health Check Endpoints

The authenticated server provides health check endpoints:

```bash
# Basic health check
curl http://localhost:8080/health

# Readiness check (includes auth system status)
curl http://localhost:8080/ready

# Security status (requires admin role)
curl -H "X-API-Key: admin-key" http://localhost:8080/security/status
```

For more advanced configuration options, see the [Configuration Reference](./CONFIGURATION.md).

## Support

- **Documentation**: [https://docs.agrama.dev](https://docs.agrama.dev)
- **Issues**: [GitHub Issues](https://github.com/nibzard/agrama-v2/issues)
- **Security Issues**: security@agrama.dev
- **Community**: [Discord](https://discord.gg/agrama)