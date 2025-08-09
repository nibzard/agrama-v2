// Human command interface for directing AI agents
import React, { useState, useMemo } from 'react';
import type { AgentConnection, HumanCommand } from '../types';

interface CommandInputProps {
  onSendCommand: (command: string, targetAgents?: string[]) => void;
  agents: Map<string, AgentConnection>;
  commands: HumanCommand[];
  connected: boolean;
}

interface CommandSuggestion {
  text: string;
  description: string;
  category: string;
}

const COMMAND_TEMPLATES: CommandSuggestion[] = [
  // Code Analysis Commands
  { text: "Analyze the main function and explain what it does", description: "Get code analysis", category: "Analysis" },
  { text: "Find all TODO comments in the codebase", description: "Search for tasks", category: "Search" },
  { text: "Show dependencies for the database module", description: "Dependency analysis", category: "Analysis" },
  { text: "Explain the error handling pattern used here", description: "Pattern explanation", category: "Analysis" },
  
  // Code Generation Commands  
  { text: "Add error handling to this function", description: "Improve code quality", category: "Generation" },
  { text: "Write unit tests for the user authentication", description: "Generate tests", category: "Generation" },
  { text: "Create a README for this module", description: "Generate documentation", category: "Generation" },
  { text: "Refactor this code to use async/await", description: "Code refactoring", category: "Generation" },
  
  // Project Commands
  { text: "What files have been changed in the last hour?", description: "Recent activity", category: "Project" },
  { text: "Show me the overall architecture of this project", description: "Architecture overview", category: "Project" },
  { text: "Find potential performance bottlenecks", description: "Performance analysis", category: "Project" },
  { text: "Check for code duplication", description: "Quality check", category: "Project" },
  
  // Collaboration Commands
  { text: "Summarize what all agents have accomplished today", description: "Activity summary", category: "Collaboration" },
  { text: "Show me the decision history for this feature", description: "Decision tracking", category: "Collaboration" },
  { text: "Review the last 10 changes for potential issues", description: "Change review", category: "Collaboration" },
];

export const CommandInput: React.FC<CommandInputProps> = ({
  onSendCommand,
  agents,
  commands,
  connected
}) => {
  const [input, setInput] = useState('');
  const [selectedAgents, setSelectedAgents] = useState<Set<string>>(new Set());
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [suggestionFilter, setSuggestionFilter] = useState('');
  
  const activeAgents = useMemo(() => {
    return Array.from(agents.values()).filter(agent => agent.status === 'connected' || agent.status === 'active');
  }, [agents]);
  
  const filteredSuggestions = useMemo(() => {
    if (!suggestionFilter.trim()) return COMMAND_TEMPLATES;
    
    const filter = suggestionFilter.toLowerCase();
    return COMMAND_TEMPLATES.filter(suggestion =>
      suggestion.text.toLowerCase().includes(filter) ||
      suggestion.description.toLowerCase().includes(filter) ||
      suggestion.category.toLowerCase().includes(filter)
    );
  }, [suggestionFilter]);
  
  const recentCommands = useMemo(() => {
    return commands.slice(0, 5);
  }, [commands]);
  
  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!input.trim()) return;
    if (!connected) {
      alert('Not connected to server');
      return;
    }
    
    const targetAgents = selectedAgents.size > 0 ? Array.from(selectedAgents) : undefined;
    onSendCommand(input.trim(), targetAgents);
    
    setInput('');
    setShowSuggestions(false);
  };
  
  const handleAgentToggle = (agentId: string) => {
    setSelectedAgents(prev => {
      const updated = new Set(prev);
      if (updated.has(agentId)) {
        updated.delete(agentId);
      } else {
        updated.add(agentId);
      }
      return updated;
    });
  };
  
  const handleSelectAllAgents = () => {
    if (selectedAgents.size === activeAgents.length) {
      setSelectedAgents(new Set());
    } else {
      setSelectedAgents(new Set(activeAgents.map(agent => agent.id)));
    }
  };
  
  const handleSuggestionClick = (suggestion: CommandSuggestion) => {
    setInput(suggestion.text);
    setShowSuggestions(false);
    setSuggestionFilter('');
  };
  
  const handleCommandClick = (command: HumanCommand) => {
    setInput(command.command);
  };
  
  const getCommandStatusIcon = (status: HumanCommand['status']) => {
    switch (status) {
      case 'completed': return '✅';
      case 'acknowledged': return '👀';
      case 'error': return '❌';
      case 'sent': return '📤';
      default: return '⏳';
    }
  };
  
  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', { 
      hour12: false, 
      hour: '2-digit', 
      minute: '2-digit' 
    });
  };
  
  return (
    <div className="command-input">
      <div className="command-header">
        <h3>Human Commands</h3>
        <div className="connection-status">
          {connected ? (
            <span className="connected">🟢 Connected</span>
          ) : (
            <span className="disconnected">🔴 Disconnected</span>
          )}
        </div>
      </div>
      
      {/* Agent Selection */}
      {activeAgents.length > 0 && (
        <div className="agent-selection">
          <div className="agent-selection-header">
            <span>Target Agents:</span>
            <button 
              type="button" 
              onClick={handleSelectAllAgents}
              className="select-all-btn"
            >
              {selectedAgents.size === activeAgents.length ? 'Deselect All' : 'Select All'}
            </button>
          </div>
          <div className="agent-list">
            {activeAgents.map(agent => (
              <label key={agent.id} className="agent-checkbox">
                <input
                  type="checkbox"
                  checked={selectedAgents.has(agent.id)}
                  onChange={() => handleAgentToggle(agent.id)}
                />
                <span className="agent-name">{agent.name}</span>
                <span className={`agent-status ${agent.status}`}>
                  {agent.status === 'active' ? '🔄' : '🟢'}
                </span>
              </label>
            ))}
          </div>
        </div>
      )}
      
      {/* Command Input */}
      <form onSubmit={handleSubmit} className="command-form">
        <div className="input-container">
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onFocus={() => setShowSuggestions(true)}
            placeholder={activeAgents.length === 0 
              ? "Waiting for agents to connect..." 
              : "Enter command for AI agents (e.g., 'Analyze the main function', 'Add error handling')..."
            }
            disabled={!connected || activeAgents.length === 0}
            rows={3}
            className="command-textarea"
          />
          <button 
            type="submit" 
            disabled={!input.trim() || !connected || activeAgents.length === 0}
            className="send-button"
          >
            Send
          </button>
        </div>
        
        <div className="input-actions">
          <button 
            type="button" 
            onClick={() => setShowSuggestions(!showSuggestions)}
            className="suggestions-toggle"
          >
            {showSuggestions ? 'Hide' : 'Show'} Suggestions
          </button>
          
          <div className="target-info">
            {selectedAgents.size === 0 ? 'All agents' : `${selectedAgents.size} agents`}
          </div>
        </div>
      </form>
      
      {/* Suggestions */}
      {showSuggestions && (
        <div className="suggestions-panel">
          <div className="suggestions-header">
            <h4>Command Suggestions</h4>
            <input
              type="text"
              value={suggestionFilter}
              onChange={(e) => setSuggestionFilter(e.target.value)}
              placeholder="Filter suggestions..."
              className="suggestion-filter"
            />
          </div>
          
          <div className="suggestions-list">
            {filteredSuggestions.map((suggestion, index) => (
              <div 
                key={index}
                onClick={() => handleSuggestionClick(suggestion)}
                className="suggestion-item"
              >
                <div className="suggestion-text">{suggestion.text}</div>
                <div className="suggestion-meta">
                  <span className="suggestion-category">{suggestion.category}</span>
                  <span className="suggestion-description">{suggestion.description}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      
      {/* Recent Commands */}
      {recentCommands.length > 0 && (
        <div className="recent-commands">
          <h4>Recent Commands</h4>
          <div className="command-history">
            {recentCommands.map(command => (
              <div 
                key={command.id}
                onClick={() => handleCommandClick(command)}
                className={`command-item ${command.status}`}
              >
                <div className="command-text">{command.command}</div>
                <div className="command-meta">
                  <span className="command-status">
                    {getCommandStatusIcon(command.status)}
                  </span>
                  <span className="command-time">
                    {formatTime(command.timestamp)}
                  </span>
                  {command.targetAgents && (
                    <span className="command-targets">
                      → {command.targetAgents.length} agents
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};