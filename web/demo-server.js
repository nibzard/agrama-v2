#!/usr/bin/env node

/**
 * Demo WebSocket server for testing Observatory interface
 * Simulates MCP server events without requiring the full Zig implementation
 */

import WebSocket, { WebSocketServer } from 'ws';

const PORT = 8080;

// Create WebSocket server
const wss = new WebSocketServer({ port: PORT });

console.log(`🔬 Demo Observatory Server running on ws://localhost:${PORT}`);

// Demo agent data
const agents = new Map();
let eventCounter = 0;

// Sample file paths for demo
const sampleFiles = [
  '/src/main.zig',
  '/src/database.zig', 
  '/src/temporal_graph.zig',
  '/src/hnsw_index.zig',
  '/src/crdt.zig',
  '/web/src/App.tsx',
  '/web/src/components/ActivityFeed.tsx',
  '/build.zig',
  '/README.md',
  '/TODO.md'
];

// Sample agent tools
const tools = ['read_code', 'write_code', 'get_context', 'analyze_dependencies', 'record_decision'];

// Sample agent names
const agentNames = ['Claude Code', 'Cursor Agent', 'VSCode Copilot', 'Custom Agent'];

function generateEventId() {
  return `event_${++eventCounter}_${Date.now()}`;
}

function getRandomElement(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function createAgent(ws) {
  const agentId = `agent_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  const agent = {
    id: agentId,
    name: getRandomElement(agentNames),
    status: 'connected',
    lastActivity: new Date(),
    ws: ws
  };
  
  agents.set(agentId, agent);
  return agent;
}

function broadcastEvent(event) {
  const message = JSON.stringify(event);
  
  agents.forEach(agent => {
    if (agent.ws && agent.ws.readyState === WebSocket.OPEN) {
      agent.ws.send(message);
    }
  });
}

function simulateAgentActivity() {
  if (agents.size === 0) return;
  
  const agentList = Array.from(agents.values());
  const agent = getRandomElement(agentList);
  const tool = getRandomElement(tools);
  const file = getRandomElement(sampleFiles);
  
  // Create activity event
  const activity = {
    id: generateEventId(),
    agentId: agent.id,
    agentName: agent.name,
    tool: tool,
    action: `${tool} ${file}`,
    timestamp: new Date(),
    params: { file_path: file },
    result: { success: true, content: `Sample result for ${tool}` },
    duration: Math.random() * 1000 + 50, // 50-1050ms
    status: Math.random() > 0.1 ? 'success' : 'error'
  };
  
  const event = {
    type: 'agent_activity',
    data: activity,
    timestamp: new Date()
  };
  
  // Update agent status
  agent.status = 'active';
  agent.lastActivity = new Date();
  
  broadcastEvent(event);
  
  // Also send file change event
  const fileChange = {
    path: file,
    action: tool === 'read_code' ? 'read' : tool === 'write_code' ? 'write' : 'analyze',
    timestamp: new Date(),
    agentId: agent.id,
    content: tool === 'write_code' ? 'Sample file content...' : undefined
  };
  
  const fileEvent = {
    type: 'file_changed',
    data: fileChange,
    timestamp: new Date()
  };
  
  setTimeout(() => {
    broadcastEvent(fileEvent);
  }, 100);
  
  // Reset agent to connected after activity
  setTimeout(() => {
    agent.status = 'connected';
  }, 2000);
}

function handleHumanCommand(ws, message) {
  try {
    const command = JSON.parse(message);
    
    if (command.type === 'human_command') {
      const response = {
        ...command.data,
        status: 'acknowledged',
        response: `Command "${command.data.command}" received and will be processed.`
      };
      
      const responseEvent = {
        type: 'human_command_response',
        data: response,
        timestamp: new Date()
      };
      
      // Send acknowledgment
      setTimeout(() => {
        broadcastEvent(responseEvent);
      }, 500);
      
      // Simulate command completion
      setTimeout(() => {
        const completedResponse = {
          ...response,
          status: 'completed',
          response: `Command "${command.data.command}" completed successfully.`
        };
        
        const completedEvent = {
          type: 'human_command_response',
          data: completedResponse,
          timestamp: new Date()
        };
        
        broadcastEvent(completedEvent);
      }, 3000);
    }
  } catch (error) {
    console.error('Failed to parse command:', error);
  }
}

// Handle WebSocket connections
wss.on('connection', (ws) => {
  console.log('🔌 New client connected');
  
  // Create demo agent for this connection
  const agent = createAgent(ws);
  
  // Send agent connected event
  const connectEvent = {
    type: 'agent_connected',
    data: agent,
    timestamp: new Date()
  };
  broadcastEvent(connectEvent);
  
  // Handle incoming messages (human commands)
  ws.on('message', (message) => {
    handleHumanCommand(ws, message.toString());
  });
  
  // Handle disconnect
  ws.on('close', () => {
    console.log(`🔌 Agent ${agent.name} disconnected`);
    
    // Send disconnect event
    const disconnectEvent = {
      type: 'agent_disconnected',
      data: { ...agent, status: 'disconnected' },
      timestamp: new Date()
    };
    broadcastEvent(disconnectEvent);
    
    // Remove agent
    agents.delete(agent.id);
  });
  
  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

// Simulate periodic agent activity
setInterval(() => {
  if (agents.size > 0) {
    simulateAgentActivity();
  }
}, 2000 + Math.random() * 3000); // Every 2-5 seconds

// Create some initial demo agents after a short delay
setTimeout(() => {
  // Create a fake connection for demo purposes
  for (let i = 0; i < 2; i++) {
    const fakeWs = {
      readyState: WebSocket.OPEN,
      send: () => {} // No-op since these are demo agents
    };
    
    const agent = createAgent(fakeWs);
    const connectEvent = {
      type: 'agent_connected',
      data: agent,
      timestamp: new Date()
    };
    
    console.log(`🤖 Created demo agent: ${agent.name}`);
    
    // Don't broadcast these initial demo agents to avoid confusion
    // They're just for generating activity
  }
}, 1000);

console.log('🚀 Demo server ready! Connect Observatory at http://localhost:5173');
console.log('📊 Simulating agent activity every 2-5 seconds');
console.log('💬 Send commands from Observatory to test human-agent interaction');