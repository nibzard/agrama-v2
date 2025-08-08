# TODO - Development Task Tracker

## Style Guide

### Task Format
```markdown
- [ ] **[PRIORITY]** Category: Brief description
  - **Context**: Why this task is needed
  - **Acceptance Criteria**: What constitutes completion
  - **Dependencies**: Other tasks that must complete first
  - **Estimate**: Time/complexity estimate
  - **Assignee**: @username or team
  - **Labels**: #bug #feature #docs #refactor #test
```

### Priority Levels
- **[P0]** - Critical/Blocker - Must fix immediately
- **[P1]** - High - Should complete this sprint
- **[P2]** - Medium - Should complete this release
- **[P3]** - Low - Nice to have, backlog

### Categories
- **Core**: Database engine, core algorithms
- **MCP**: Model Context Protocol server and tools
- **Web**: Observatory web interface
- **API**: Public APIs and integrations
- **Docs**: Documentation and guides
- **Test**: Testing infrastructure and test cases
- **Deploy**: Deployment, CI/CD, infrastructure
- **Research**: Spike work, proof of concepts

### Status Tracking
- `- [ ]` - Not started
- `- [x]` - Completed
- `- [~]` - In progress
- `- [!]` - Blocked
- `- [?]` - Needs clarification

### Example Tasks

- [x] **[P1]** Core: Initialize Zig project structure
  - **Context**: Need basic project setup to start development
  - **Acceptance Criteria**: Builds successfully with `zig build`
  - **Assignee**: @core-team
  - **Labels**: #setup #core

- [~] **[P0]** Core: Implement temporal graph storage
  - **Context**: Foundation for all temporal operations
  - **Acceptance Criteria**: Can store/retrieve temporal nodes and edges
  - **Dependencies**: Project structure complete
  - **Estimate**: 2 weeks
  - **Assignee**: @backend-team  
  - **Labels**: #core #database

- [ ] **[P2]** MCP: Implement read_code tool
  - **Context**: Essential MCP tool for AI agents to read code
  - **Acceptance Criteria**: Tool returns code content with context
  - **Dependencies**: Temporal storage, file indexing
  - **Estimate**: 3 days
  - **Labels**: #mcp #feature

## This Week's Focus

### Single Goal
Make `agrama serve` work with basic file read/write through MCP

### Must Complete (In Order)

- [ ] **[P0]** Initialize Zig project structure
  - **Next Step**: Run `zig init-lib`
  - **Success**: `zig build` runs without errors

- [ ] **[P0]** Implement basic Database struct
  - **Next Step**: Create src/database.zig with 3 methods
  - **Success**: Can save/retrieve files with timestamps

- [ ] **[P0]** Add minimal MCP server
  - **Next Step**: Implement read_code and write_code tools only
  - **Success**: Claude can read/write files through MCP

- [ ] **[P0]** Test with real AI agent
  - **Next Step**: Configure Claude/Cursor to use server
  - **Success**: Agent successfully modifies a file

### Backlog

- [ ] **[P2]** Core: Implement matryoshka embeddings
  - **Context**: Variable-dimension semantic vectors per SPECS.md
  - **Acceptance Criteria**: Support 64D-3072D adaptive embeddings
  - **Dependencies**: Basic storage working
  - **Estimate**: 1 week
  - **Labels**: #core #embeddings

- [ ] **[P2]** Core: Implement HNSW vector index
  - **Context**: Ultra-fast semantic search capabilities  
  - **Acceptance Criteria**: O(log n) semantic search performance
  - **Dependencies**: Matryoshka embeddings
  - **Estimate**: 2 weeks
  - **Labels**: #core #search #performance

- [ ] **[P2]** Core: Implement Frontier Reduction Engine
  - **Context**: O(m log^(2/3) n) graph traversal algorithm
  - **Acceptance Criteria**: Faster graph queries than traditional methods
  - **Dependencies**: Basic graph operations
  - **Estimate**: 2 weeks
  - **Labels**: #core #algorithm #performance

- [ ] **[P3]** MCP: Implement MCP server framework
  - **Context**: Handle MCP protocol communication
  - **Acceptance Criteria**: Can register tools and handle requests
  - **Dependencies**: Core database functional
  - **Estimate**: 1 week
  - **Labels**: #mcp #server

- [ ] **[P3]** Web: Create Observatory React app
  - **Context**: Real-time web interface from MVP.md
  - **Acceptance Criteria**: Shows live agent activities
  - **Dependencies**: MCP server, WebSocket support
  - **Estimate**: 2 weeks
  - **Labels**: #web #ui

## Completed

- [x] **[P1]** Docs: Create functional specification
  - **Context**: Define system architecture and requirements
  - **Acceptance Criteria**: Complete SPECS.md covering all components
  - **Completed**: 2025-01-08
  - **Labels**: #docs

- [x] **[P1]** Docs: Create MVP specification  
  - **Context**: Define first deliverable product
  - **Acceptance Criteria**: Complete MVP.md with implementation plan
  - **Completed**: 2025-01-08
  - **Labels**: #docs #planning

## Blocked

- [!] **[P1]** Deploy: Set up CI/CD pipeline
  - **Context**: Automated testing and deployment
  - **Blocker**: Need to decide on hosting platform
  - **Labels**: #deploy #blocked

## Notes

### Development Conventions
- All tasks should link to relevant documentation (SPECS.md, MVP.md)
- Use `#labels` for easy filtering and categorization  
- Keep estimates realistic - better to over-estimate than under
- Update task status regularly during daily standups
- Move completed tasks to "Completed" section weekly

### Review Process
- All `[P0]` tasks require code review before completion
- `[P1]` tasks should have at least one reviewer
- Update TODO.md during sprint planning and retrospectives
- Archive completed tasks older than 30 days to keep file manageable

### Tools Integration
- Link to GitHub issues: `Closes #123`
- Reference commits: `Implemented in abc123f`
- Cross-reference: `Related to Core: Implement X`