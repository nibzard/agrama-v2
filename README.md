# Agrama - Temporal Knowledge Graph for AI Collaboration

A database that tracks how AI agents work together on code, creating a living history of decisions and changes.

## Quick Start

```bash
# Step 1: Build the database
zig build

# Step 2: Start the MCP server  
agrama serve

# Step 3: Connect your AI agent
# Add to Claude/Cursor config:
{
  "mcpServers": {
    "agrama": {
      "command": "agrama",
      "args": ["serve"]
    }
  }
}
```

## What It Does

**For AI Agents**: Provides tools to read/write code with full context and history
**For Humans**: Shows real-time visualization of what agents are doing
**For Teams**: Creates a searchable history of all development decisions

## Core Features (MVP)

1. **Temporal Storage**: Every change is tracked with who/what/when/why
2. **MCP Tools**: AI agents can read_code, write_code, get_context
3. **Web Observatory**: Real-time view of agent activities at localhost:3000

## Development

See [IMPLEMENTATION.md](IMPLEMENTATION.md) for the step-by-step build plan.

## Why Agrama?

Traditional development loses context with every change. Agrama captures the *why* behind code evolution, making AI agents smarter and human oversight easier.