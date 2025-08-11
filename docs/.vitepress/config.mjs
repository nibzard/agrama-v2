import { defineConfig } from 'vitepress'
import { withMermaid } from 'vitepress-plugin-mermaid'

export default withMermaid(
  defineConfig({
  title: 'Agrama Documentation',
  description: 'Temporal Knowledge Graph Database for AI Collaboration',
  base: '/',
  
  themeConfig: {
    nav: [
      { text: 'Architecture', link: '/architecture/' },
      { text: 'Performance', link: '/performance/' },
      { text: 'MCP Server', link: '/mcp/' },
      { text: 'Frontend', link: '/frontend/' },
      { text: 'API Reference', link: '/api/' },
      { text: 'Testing', link: '/testing/' }
    ],
    
    sidebar: {
      '/architecture/': [
        {
          text: 'Architecture',
          items: [
            { text: 'System Overview', link: '/architecture/' },
            { text: 'Architecture Overview', link: '/architecture/overview' },
            { text: 'Database Core', link: '/architecture/database' },
            { text: 'Algorithms', link: '/architecture/algorithms' },
            { text: 'Data Structures', link: '/architecture/data-structures' },
            { text: 'Memory Management', link: '/architecture/memory-pools' }
          ]
        }
      ],
      '/performance/': [
        {
          text: 'Performance',
          items: [
            { text: 'Benchmark Results', link: '/performance/' },
            { text: 'Optimization Guide', link: '/performance/optimizations' },
            { text: 'Performance Targets', link: '/performance/targets' },
            { text: 'Regression Testing', link: '/performance/regression' }
          ]
        }
      ],
      '/mcp/': [
        {
          text: 'MCP Server',
          items: [
            { text: 'Overview', link: '/mcp/' },
            { text: 'API Reference', link: '/mcp/api-reference' },
            { text: 'Integration Guide', link: '/mcp/integration' },
            { text: 'Development Guide', link: '/mcp/development' },
            { text: 'Tool Reference', link: '/mcp/tools' },
            { text: 'Agent Integration', link: '/mcp/agents' },
            { text: 'Protocol Compliance', link: '/mcp/protocol' }
          ]
        }
      ],
      '/frontend/': [
        {
          text: 'Observatory Interface',
          items: [
            { text: 'Overview', link: '/frontend/' },
            { text: 'Architecture', link: '/frontend/architecture' },
            { text: 'Components', link: '/frontend/components' },
            { text: 'Development Setup', link: '/frontend/setup' },
            { text: 'Visualization Guide', link: '/frontend/visualization' }
          ]
        }
      ],
      '/testing/': [
        {
          text: 'Testing Framework',
          items: [
            { text: 'Testing Framework', link: '/testing/' },
            { text: 'Testing Overview', link: '/testing/overview' },
            { text: 'Test Framework', link: '/testing/framework' },
            { text: 'Test Categories', link: '/testing/categories' },
            { text: 'Testing Guide', link: '/testing/guide' }
          ]
        }
      ],
      '/api/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Primitives API', link: '/api/' },
            { text: 'Database API', link: '/api/database' },
            { text: 'Search API', link: '/api/search' },
            { text: 'MCP Tools', link: '/api/mcp-tools' }
          ]
        }
      ]
    },
    
    socialLinks: [
      { icon: 'github', link: 'https://github.com/nibzard/agrama-v2' }
    ],
    
    footer: {
      message: 'Released under the ISC License.',
      copyright: 'Copyright © 2025 Agrama Project'
    }
  },
  
  markdown: {
    theme: 'github-dark',
    lineNumbers: true
  }
  })
)