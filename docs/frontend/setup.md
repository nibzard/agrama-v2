---
title: Development Setup
description: Complete guide for setting up the Observatory development environment
---

# Development Setup

## Overview

This guide covers the complete setup process for developing the Agrama Observatory web interface. The Observatory provides real-time visualization of multi-agent AI collaboration through a modern React-based frontend integrated with the Agrama CodeGraph backend.

## Prerequisites

### System Requirements
- **Node.js**: Version 18.0.0 or higher
- **npm**: Version 8.0.0 or higher (comes with Node.js)
- **Git**: For version control
- **Modern browser**: Chrome 90+, Firefox 88+, Safari 14+, or Edge 90+

### Backend Requirements
- **Agrama MCP Server**: Must be running on `localhost:8080`
- **Zig**: Version 0.11.0 or higher for building the backend
- **WebSocket support**: Backend must have WebSocket server enabled

### Verification Commands
```bash
# Check Node.js version
node --version
# Should output: v18.x.x or higher

# Check npm version  
npm --version
# Should output: 8.x.x or higher

# Check Zig version (for backend)
zig version
# Should output: 0.11.x or higher

# Verify Agrama backend is buildable
cd /home/niko/agrama-v2
zig build
```

## Initial Setup

### 1. Project Structure
The Observatory frontend is located in the `web/` directory:

```
/home/niko/agrama-v2/
├── web/                     # Frontend application
│   ├── src/                 # Source code
│   │   ├── components/      # React components
│   │   ├── hooks/          # Custom React hooks
│   │   ├── types/          # TypeScript type definitions
│   │   ├── utils/          # Utility functions
│   │   ├── App.tsx         # Main application component
│   │   └── main.tsx        # Application entry point
│   ├── public/             # Static assets
│   ├── package.json        # Dependencies and scripts
│   ├── tsconfig.json       # TypeScript configuration
│   ├── vite.config.ts      # Vite build configuration
│   └── README.md           # Frontend-specific documentation
├── src/                    # Backend Zig source code
└── zig-out/               # Compiled binaries
```

### 2. Backend Setup
Before starting frontend development, ensure the Agrama backend is running:

```bash
# Navigate to project root
cd /home/niko/agrama-v2

# Build the Agrama system
zig build

# Start the MCP server (required for Observatory)
./zig-out/bin/agrama_v2 mcp

# Verify server is running
curl http://localhost:8080/health
# Should return: {"status": "healthy", "timestamp": "..."}
```

The MCP server must be running on `localhost:8080` for the Observatory to connect successfully.

### 3. Frontend Installation
```bash
# Navigate to web directory
cd /home/niko/agrama-v2/web

# Install dependencies
npm install

# Verify installation
npm list --depth=0
```

**Expected Dependencies**:
```json
{
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "d3": "^7.8.0",
    "typescript": "^5.1.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@types/d3": "^7.4.0",
    "@typescript-eslint/eslint-plugin": "^5.62.0",
    "@typescript-eslint/parser": "^5.62.0",
    "@vitejs/plugin-react": "^4.0.0",
    "eslint": "^8.45.0",
    "eslint-plugin-react-hooks": "^4.6.0",
    "eslint-plugin-react-refresh": "^0.4.0",
    "vite": "^4.4.0"
  }
}
```

## Development Environment

### 1. Environment Configuration
Create a `.env.local` file in the `web/` directory:

```bash
# Navigate to web directory
cd /home/niko/agrama-v2/web

# Create environment configuration
cat > .env.local << 'EOF'
# Agrama Observatory Configuration
VITE_MCP_SERVER_URL=ws://localhost:8080/ws
VITE_API_BASE_URL=http://localhost:8080/api
VITE_RECONNECT_INTERVAL=3000
VITE_MAX_ACTIVITIES=1000
VITE_MAX_SEARCH_RESULTS=100
VITE_DEBUG_MODE=true
EOF
```

**Environment Variables**:
- `VITE_MCP_SERVER_URL`: WebSocket endpoint for real-time communication
- `VITE_API_BASE_URL`: REST API endpoint for data queries
- `VITE_RECONNECT_INTERVAL`: WebSocket reconnection interval (ms)
- `VITE_MAX_ACTIVITIES`: Maximum activities in memory buffer
- `VITE_MAX_SEARCH_RESULTS`: Maximum search results to display
- `VITE_DEBUG_MODE`: Enable debug logging and development tools

### 2. TypeScript Configuration
Verify `tsconfig.json` is properly configured:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "node",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

### 3. Vite Configuration
The `vite.config.ts` should include:

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: true,
    open: true,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true
      },
      '/ws': {
        target: 'ws://localhost:8080',
        ws: true,
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom'],
          d3: ['d3']
        }
      }
    }
  },
  define: {
    'import.meta.env.VITE_BUILD_TIME': JSON.stringify(new Date().toISOString())
  }
});
```

## Starting Development

### 1. Start Backend Services
```bash
# Terminal 1: Start Agrama MCP server
cd /home/niko/agrama-v2
./zig-out/bin/agrama_v2 mcp

# Verify server startup
# You should see: "MCP server starting on port 8080"
```

### 2. Start Frontend Development Server
```bash
# Terminal 2: Start Observatory development server
cd /home/niko/agrama-v2/web
npm run dev

# Expected output:
#   VITE v4.4.0  ready in 1234 ms
#   ➜  Local:   http://localhost:3000/
#   ➜  Network: http://192.168.x.x:3000/
#   ➜  press h to show help
```

### 3. Verify Connection
1. Open browser to `http://localhost:3000`
2. Check Observatory header shows "Connected" status
3. Verify agent list displays active connections
4. Test command input functionality

**Connection Troubleshooting**:
```bash
# Check if MCP server is responding
curl http://localhost:8080/health

# Check WebSocket endpoint
wscat -c ws://localhost:8080/ws
# (Install wscat with: npm install -g wscat)

# Check network connectivity
netstat -an | grep 8080
# Should show LISTEN on port 8080
```

## Development Workflow

### 1. Code Structure Standards
```typescript
// Component file structure
import React, { useState, useEffect, useCallback, useMemo } from 'react';
import type { ComponentProps } from './types';
import { useWebSocket } from '../hooks/useWebSocket';
import './Component.css';

interface Props extends ComponentProps {
  // Props interface
}

export const ComponentName: React.FC<Props> = ({
  prop1,
  prop2
}) => {
  // Hooks at top
  const [state, setState] = useState();
  const { data } = useWebSocket();
  
  // Memoized calculations
  const processedData = useMemo(() => {
    return expensiveCalculation(data);
  }, [data]);
  
  // Event handlers
  const handleEvent = useCallback(() => {
    // Handler logic
  }, [dependencies]);
  
  // Effects last
  useEffect(() => {
    // Effect logic
  }, [dependencies]);
  
  return (
    <div className="component-name">
      {/* JSX content */}
    </div>
  );
};
```

### 2. Hot Reloading and Development
The development server supports:
- **Hot Module Replacement (HMR)**: Changes reflect immediately
- **TypeScript compilation**: Real-time type checking
- **ESLint integration**: Code quality validation
- **CSS Hot Reloading**: Instant style updates

### 3. Debugging Tools
```bash
# Enable React Developer Tools
npm install -g react-devtools

# Start React DevTools (separate process)
react-devtools

# Enable Redux DevTools (if using Redux)
# Browser extension: Redux DevTools
```

**Debug Configuration**:
```typescript
// Enable debug logging
if (import.meta.env.VITE_DEBUG_MODE) {
  console.log('Observatory Debug Mode Enabled');
  
  // Add global debug helpers
  (window as any).debugObservatory = {
    getState: () => ({ /* current state */ }),
    simulateEvent: (event: any) => { /* simulate event */ }
  };
}
```

## Testing Setup

### 1. Unit Testing
```bash
# Install testing dependencies
npm install --save-dev vitest @testing-library/react @testing-library/jest-dom

# Run tests
npm run test

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm run test:coverage
```

### 2. Testing Configuration
Add to `package.json`:

```json
{
  "scripts": {
    "test": "vitest",
    "test:watch": "vitest --watch",
    "test:coverage": "vitest --coverage"
  }
}
```

Create `vitest.config.ts`:

```typescript
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts']
  }
});
```

### 3. Component Testing Example
```typescript
// src/components/__tests__/AgentStatus.test.tsx
import { render, screen } from '@testing-library/react';
import { AgentStatus } from '../AgentStatus';

describe('AgentStatus Component', () => {
  const mockProps = {
    agents: new Map([
      ['agent-1', { id: 'agent-1', name: 'Test Agent', status: 'connected' }]
    ]),
    activities: [],
    totalEvents: 0,
    lastEventTime: null,
    connected: true
  };

  test('renders agent list correctly', () => {
    render(<AgentStatus {...mockProps} />);
    
    expect(screen.getByText('Active Agents (1)')).toBeInTheDocument();
    expect(screen.getByText('Test Agent')).toBeInTheDocument();
    expect(screen.getByText('Connected')).toBeInTheDocument();
  });
});
```

## Build and Deployment

### 1. Development Build
```bash
# Build for development
npm run build:dev

# Preview production build
npm run preview
```

### 2. Production Build
```bash
# Build optimized for production
npm run build

# Verify build output
ls -la dist/
# Should contain: index.html, assets/, etc.

# Test production build locally
npm run preview
```

### 3. Build Configuration
Production build optimizations:
- **Code splitting**: Separate chunks for vendor libraries
- **Tree shaking**: Remove unused code
- **Minification**: Compress JavaScript and CSS
- **Source maps**: Debug production issues

## Performance Optimization

### 1. Bundle Analysis
```bash
# Analyze bundle size
npm run analyze

# Install bundle analyzer
npm install --save-dev rollup-plugin-visualizer
```

### 2. Performance Monitoring
```typescript
// Performance monitoring in development
if (import.meta.env.DEV) {
  import('web-vitals').then(({ getCLS, getFID, getFCP, getLCP, getTTFB }) => {
    getCLS(console.log);
    getFID(console.log);
    getFCP(console.log);
    getLCP(console.log);
    getTTFB(console.log);
  });
}
```

### 3. Optimization Checklist
- ✅ React.memo() for expensive components
- ✅ useMemo() for complex calculations  
- ✅ useCallback() for event handlers
- ✅ Code splitting for large components
- ✅ Image optimization and lazy loading
- ✅ Bundle size analysis and optimization

## Troubleshooting

### Common Issues

#### WebSocket Connection Failures
```bash
# Check backend is running
ps aux | grep agrama_v2

# Verify port availability
netstat -an | grep 8080

# Test direct WebSocket connection
wscat -c ws://localhost:8080/ws
```

#### TypeScript Errors
```bash
# Clear TypeScript cache
rm -rf node_modules/.cache
npm install

# Update TypeScript definitions
npm update @types/react @types/react-dom
```

#### Build Failures
```bash
# Clear all caches
rm -rf node_modules dist .vite
npm install
npm run build
```

#### Performance Issues
- Enable React DevTools Profiler
- Monitor WebSocket message frequency
- Check memory usage in browser DevTools
- Verify efficient D3.js render patterns

### Debug Tools
```bash
# Enable verbose logging
VITE_DEBUG_MODE=true npm run dev

# Network debugging
# Use browser DevTools Network tab
# Monitor WebSocket messages in WS tab

# React debugging
# Use React Developer Tools extension
# Enable Concurrent Features debugging
```

## Next Steps

1. **Review [Component Documentation](./components.md)** for detailed component specifications
2. **Study [Visualization Guide](./visualization.md)** for D3.js implementation patterns
3. **Explore the [Architecture Documentation](./architecture.md)** for system design details
4. **Set up your IDE** with TypeScript and React extensions
5. **Join development workflow** with proper git practices

This development setup provides a robust foundation for building and maintaining the Agrama Observatory interface with optimal performance and developer experience.