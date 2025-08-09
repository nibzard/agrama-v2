# Agrama CodeGraph Observatory

Real-time web interface for monitoring AI-human collaborative development with the Agrama CodeGraph MCP server.

## Features

### 🔍 **Real-time Agent Activity Feed**
- Live stream of all agent actions (read_code, write_code, get_context, etc.)
- Performance metrics (response times, success rates)
- Agent status indicators with connection monitoring
- Detailed activity logging with timestamps

### 📁 **Project File Explorer**
- Real-time file tree with agent activity indicators
- Change counters and recent activity highlighting
- File type icons and directory structure
- Visual feedback for files being actively modified

### 💬 **Human Command Interface**
- Natural language commands to direct AI agents
- Pre-built command templates for common tasks
- Agent targeting (send commands to specific agents)
- Command history and status tracking
- Auto-suggestions for faster interaction

### 📊 **Performance Dashboard**
- Overall system metrics (agent count, event throughput)
- Individual agent performance tracking
- Success rates and response time analysis
- Connection status and health monitoring

## Quick Start

### 1. Start the Observatory Interface
```bash
cd web
npm install
npm run dev
```

The interface will be available at `http://localhost:5173`

### 2. Start the MCP Server
```bash
# In another terminal
cd /path/to/agrama-v2
zig run src/main.zig
```

The MCP server runs on `ws://localhost:8080` with WebSocket broadcasting.

### 3. Connect AI Agents
Connect Claude Code, Cursor, or other MCP clients to `http://localhost:8080`

## Interface Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  🔬 Agrama CodeGraph Observatory                    🟢 Connected │
├─────────────┬─────────────────────────────┬─────────────────────┤
│ Agent Status│      Activity Feed          │  Human Commands     │
│ ┌─────────┐ │ ┌─────────────────────────┐ │ ┌─────────────────┐ │
│ │Agents: 2│ │ │✅📖 Agent1: read main.zig│ │ │ Enter command...│ │
│ │Active: 1│ │ │⏳✏️ Agent2: write test.zig│ │ │ [Send]          │ │
│ │Success:98%│ │ │🔍📊 Agent1: analyze deps│ │ │                 │ │
│ └─────────┘ │ └─────────────────────────┘ │ │ Suggestions:    │ │
│             │                             │ │ • Analyze main  │ │
│ File Tree   │                             │ │ • Find TODOs    │ │
│ 📁 src/     │                             │ │ • Write tests   │ │
│   📘 main.zig                             │ └─────────────────┘ │
│   📙 test.zig ✏️                          │                     │
│ 📁 web/ 🔄                                │                     │
└─────────────┴─────────────────────────────┴─────────────────────┘
```

## Usage Examples

### Directing Agent Actions
```
"Analyze the main function and explain what it does"
"Find all TODO comments in the codebase"
"Add error handling to the database module"
"Write unit tests for the authentication system"
```

### Monitoring Development
- Watch real-time file changes as agents work
- Monitor agent performance and connection health
- Track decision history and collaboration patterns
- Review command responses and agent feedback

### Collaboration Features
- Send targeted commands to specific agents
- Monitor multi-agent coordination
- Track progress on complex tasks
- Maintain visibility into all AI activities

## Architecture

### WebSocket Integration
- Connects to MCP server at `ws://localhost:8080`
- Real-time event streaming with auto-reconnection
- Sub-500ms latency for UI updates
- Efficient state management for large datasets

### Component Structure
```
src/
├── components/
│   ├── ActivityFeed.tsx      # Real-time activity stream
│   ├── AgentStatus.tsx       # Agent monitoring dashboard
│   ├── CommandInput.tsx      # Human-agent interface
│   └── FileExplorer.tsx      # Project file visualization
├── hooks/
│   └── useWebSocket.ts       # WebSocket management
├── types/
│   └── index.ts              # TypeScript definitions
└── App.tsx                   # Main application
```

### Event Types
- `agent_connected` - New agent joins
- `agent_disconnected` - Agent leaves
- `agent_activity` - Tool execution events
- `file_changed` - File read/write operations
- `human_command_response` - Command acknowledgments

## Development

### Build for Production
```bash
npm run build
```

### Lint Code
```bash
npm run lint
```

### Preview Production Build
```bash
npm run preview
```

## Integration Points

### MCP Server Events
The Observatory expects WebSocket events in this format:
```json
{
  "type": "agent_activity",
  "data": {
    "id": "activity_123",
    "agentId": "claude_agent_1",
    "agentName": "Claude Code",
    "tool": "read_code",
    "action": "read file",
    "timestamp": "2024-01-01T12:00:00Z",
    "params": { "file_path": "/path/to/file.zig" },
    "result": { "content": "file contents..." },
    "duration": 150,
    "status": "success"
  },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Human Command Format
Commands sent to agents use this format:
```json
{
  "type": "human_command",
  "data": {
    "id": "cmd_123",
    "command": "Analyze the main function",
    "timestamp": "2024-01-01T12:00:00Z",
    "targetAgents": ["claude_agent_1"],
    "status": "sent"
  }
}
```

## Performance Targets

- ✅ **Sub-500ms UI updates** - Real-time responsiveness
- ✅ **Auto-reconnection** - Resilient WebSocket connection
- ✅ **Efficient rendering** - Smooth updates with large datasets
- ✅ **Memory optimization** - Limited history buffers prevent memory leaks
- ✅ **Responsive design** - Works on various screen sizes

## Future Enhancements

- 🔄 **Knowledge Graph Visualization** - D3.js force-directed graph
- 📈 **Advanced Analytics** - Pattern recognition and insights
- 🎯 **Smart Agent Routing** - Automatic task distribution
- 🔄 **Real-time Collaboration** - Multi-human interfaces
- 📊 **Performance Optimization** - Advanced caching and rendering

---

**Agrama v2.0** - Temporal Knowledge Graph Database  
Observatory Interface - Phase 3  
WebSocket: ws://localhost:8080
