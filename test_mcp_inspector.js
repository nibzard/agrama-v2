#!/usr/bin/env node

const { spawn } = require('child_process');
const readline = require('readline');

console.log('🧪 Testing Agrama MCP Server with comprehensive validation');
console.log('='.repeat(60));

// Test cases to validate
const testCases = [
  {
    name: 'Initialize Protocol',
    request: {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'test-client', version: '1.0.0' }
      }
    },
    validate: (response) => {
      return response.result && 
             response.result.protocolVersion === '2024-11-05' &&
             response.result.serverInfo &&
             response.result.serverInfo.name === 'agrama-codegraph';
    }
  },
  {
    name: 'Initialization Complete',
    request: {
      jsonrpc: '2.0',
      method: 'initialized'
    },
    validate: () => true // No response expected
  },
  {
    name: 'List Tools',
    request: {
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/list'
    },
    validate: (response) => {
      const tools = response.result?.tools;
      return Array.isArray(tools) && 
             tools.length === 3 &&
             tools.some(t => t.name === 'read_code') &&
             tools.some(t => t.name === 'write_code') &&
             tools.some(t => t.name === 'get_context');
    }
  },
  {
    name: 'Call get_context Tool',
    request: {
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: {
        name: 'get_context',
        arguments: {}
      }
    },
    validate: (response) => {
      return response.result &&
             Array.isArray(response.result.content) &&
             response.result.content.length > 0 &&
             response.result.content[0].type === 'text';
    }
  },
  {
    name: 'Write Code Tool',
    request: {
      jsonrpc: '2.0',
      id: 4,
      method: 'tools/call',
      params: {
        name: 'write_code',
        arguments: {
          path: 'inspector_test.txt',
          content: 'Hello from MCP Inspector test!'
        }
      }
    },
    validate: (response) => {
      return response.result &&
             Array.isArray(response.result.content) &&
             response.result.isError === false;
    }
  },
  {
    name: 'Read Code Tool',
    request: {
      jsonrpc: '2.0',
      id: 5,
      method: 'tools/call',
      params: {
        name: 'read_code',
        arguments: {
          path: 'inspector_test.txt'
        }
      }
    },
    validate: (response) => {
      return response.result &&
             Array.isArray(response.result.content) &&
             response.result.content[0].text === 'Hello from MCP Inspector test!';
    }
  },
  {
    name: 'Error Handling - Invalid Tool',
    request: {
      jsonrpc: '2.0',
      id: 6,
      method: 'tools/call',
      params: {
        name: 'nonexistent_tool',
        arguments: {}
      }
    },
    validate: (response) => {
      return response.error && response.error.code === -32000;
    }
  },
  {
    name: 'Error Handling - Invalid Method',
    request: {
      jsonrpc: '2.0',
      id: 7,
      method: 'invalid/method'
    },
    validate: (response) => {
      return response.error && response.error.code === -32601;
    }
  }
];

async function runTests() {
  console.log('🚀 Starting MCP server...\n');
  
  const server = spawn('./zig-out/bin/agrama_v2', ['mcp'], {
    stdio: ['pipe', 'pipe', 'pipe']
  });

  const rl = readline.createInterface({
    input: server.stdout
  });

  let responseIndex = 0;
  const responses = [];
  
  rl.on('line', (line) => {
    if (line.trim()) {
      try {
        const response = JSON.parse(line);
        responses.push(response);
      } catch (e) {
        console.error('Failed to parse JSON:', line);
      }
    }
  });

  server.stderr.on('data', (data) => {
    // Stderr output is allowed for debugging (memory leak detection, etc.)
    // but should not interfere with the protocol
  });

  // Run test cases
  let passedTests = 0;
  let failedTests = 0;

  for (const testCase of testCases) {
    console.log(`📋 ${testCase.name}...`);
    
    const requestJson = JSON.stringify(testCase.request) + '\n';
    server.stdin.write(requestJson);
    
    // Wait for response (except for initialized notification)
    if (testCase.request.id !== undefined) {
      await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
      
      const expectedResponseIndex = responses.findIndex(r => r.id === testCase.request.id);
      if (expectedResponseIndex >= 0) {
        const response = responses[expectedResponseIndex];
        
        if (testCase.validate(response)) {
          console.log(`   ✅ PASS`);
          passedTests++;
        } else {
          console.log(`   ❌ FAIL - Response validation failed`);
          console.log(`      Response: ${JSON.stringify(response, null, 2)}`);
          failedTests++;
        }
      } else {
        console.log(`   ❌ FAIL - No response received`);
        failedTests++;
      }
    } else {
      // Notification - no response expected
      console.log(`   ✅ PASS (notification sent)`);
      passedTests++;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }

  server.stdin.end();
  server.kill();

  console.log('\n' + '='.repeat(60));
  console.log('📊 MCP Inspector Test Results');
  console.log('='.repeat(60));
  console.log(`✅ Passed: ${passedTests}`);
  console.log(`❌ Failed: ${failedTests}`);
  console.log(`📈 Success Rate: ${Math.round(passedTests / (passedTests + failedTests) * 100)}%`);
  
  if (failedTests === 0) {
    console.log('\n🎉 All tests passed! MCP server is fully compliant.');
  } else {
    console.log('\n⚠️  Some tests failed. Please review the issues above.');
    process.exit(1);
  }
}

runTests().catch(console.error);