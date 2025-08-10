// Agrama CodeGraph Observatory - Real-time AI-Human Collaboration Interface
import { useState } from 'react';
import { useWebSocket } from './hooks/useWebSocket';
import { ActivityFeed } from './components/ActivityFeed';
import { FileExplorer } from './components/FileExplorer';
import { CommandInput } from './components/CommandInput';
import { AgentStatus } from './components/AgentStatus';
import { SemanticSearchPanel } from './components/SemanticSearchPanel';
import { DependencyGraphViz } from './components/DependencyGraphViz';
import { CollaborationDashboard } from './components/CollaborationDashboard';
import { PerformanceMetrics } from './components/PerformanceMetrics';
import './App.css';

function App() {
  const [activeTab, setActiveTab] = useState<'activity' | 'search' | 'dependencies' | 'collaboration' | 'performance'>('activity');

  const {
    connected,
    connecting,
    error,
    agents,
    activities,
    fileChanges,
    commands,
    semanticSearchResults,
    dependencyAnalyses,
    collaborationUpdates,
    performanceUpdates,
    sendCommand,
    sendSemanticSearch,
    reconnect,
    totalEvents,
    lastEventTime
  } = useWebSocket();

  return (
    <div className="app">
      {/* Header */}
      <header className="app-header">
        <div className="header-left">
          <h1>🔬 Agrama CodeGraph Observatory</h1>
          <p className="subtitle">Revolutionary Multi-Agent AI Collaboration Platform</p>
          <div className="revolutionary-badges">
            <span className="badge breakthrough">🚀 BREAKTHROUGH ALGORITHMS</span>
            <span className="badge functional">🤖 MULTI-AGENT AI WORKING</span>
            <span className="badge realtime">⚡ REAL-TIME CRDT SYNC</span>
          </div>
        </div>
        <div className="header-right">
          <div className="system-status">
            <div className="status-group">
              <span className="status-label">Observatory:</span>
              {connecting && <span className="status connecting">🔄 Connecting...</span>}
              {connected && <span className="status connected">🟢 Online</span>}
              {error && (
                <div className="status error">
                  <span>❌ {error}</span>
                  <button onClick={reconnect} className="reconnect-btn">
                    Reconnect
                  </button>
                </div>
              )}
            </div>
            <div className="status-group">
              <span className="status-label">Agents:</span>
              <span className="status agents">{agents.size} active</span>
            </div>
            <div className="status-group">
              <span className="status-label">Events:</span>
              <span className="status events">{totalEvents} processed</span>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="app-main">
        {/* Left Panel - Agent Status & File Explorer */}
        <aside className="left-panel">
          <AgentStatus
            agents={agents}
            activities={activities}
            totalEvents={totalEvents}
            lastEventTime={lastEventTime}
            connected={connected}
          />
          <FileExplorer
            fileChanges={fileChanges}
            agents={agents}
          />
        </aside>

        {/* Center Panel - Tabbed Content */}
        <section className="center-panel">
          {/* Tab Navigation */}
          <div className="tab-navigation">
            <button 
              className={`tab-button ${activeTab === 'activity' ? 'active' : ''}`}
              onClick={() => setActiveTab('activity')}
            >
              📊 Activity Feed
            </button>
            <button 
              className={`tab-button ${activeTab === 'search' ? 'active' : ''}`}
              onClick={() => setActiveTab('search')}
            >
              🔍 Semantic Search
            </button>
            <button 
              className={`tab-button ${activeTab === 'dependencies' ? 'active' : ''}`}
              onClick={() => setActiveTab('dependencies')}
            >
              🕸️ Dependencies
            </button>
            <button 
              className={`tab-button ${activeTab === 'collaboration' ? 'active' : ''}`}
              onClick={() => setActiveTab('collaboration')}
            >
              👥 Collaboration
            </button>
            <button 
              className={`tab-button ${activeTab === 'performance' ? 'active' : ''}`}
              onClick={() => setActiveTab('performance')}
            >
              ⚡ Performance
            </button>
          </div>

          {/* Tab Content */}
          <div className="tab-content">
            {activeTab === 'activity' && (
              <ActivityFeed
                activities={activities}
                agents={agents}
                maxItems={100}
              />
            )}
            
            {activeTab === 'search' && (
              <SemanticSearchPanel
                searchResults={semanticSearchResults}
                onSearch={sendSemanticSearch}
                connected={connected}
              />
            )}
            
            {activeTab === 'dependencies' && (
              <DependencyGraphViz
                dependencyAnalyses={dependencyAnalyses}
                width={800}
                height={600}
              />
            )}
            
            {activeTab === 'collaboration' && (
              <CollaborationDashboard
                collaborationUpdates={collaborationUpdates}
                agents={agents}
              />
            )}
            
            {activeTab === 'performance' && (
              <PerformanceMetrics
                performanceUpdates={performanceUpdates}
              />
            )}
          </div>
        </section>

        {/* Right Panel - Command Interface */}
        <aside className="right-panel">
          <CommandInput
            onSendCommand={sendCommand}
            agents={agents}
            commands={commands}
            connected={connected}
          />
        </aside>
      </main>

      {/* Footer */}
      <footer className="app-footer">
        <div className="footer-info">
          <span>🚀 Agrama v2.0 - Revolutionary AI Collaboration Platform</span>
          <span>•</span>
          <span>BREAKTHROUGH: Multi-Agent AI Working in Production</span>
          <span>•</span>
          <span>HNSW O(log n) + FRE O(m log^(2/3) n) + CRDT Conflict-free</span>
          <span>•</span>
          <span>WebSocket: ws://localhost:8080</span>
        </div>
        <div className="footer-stats">
          <span>🤖 {agents.size} AI agents active</span>
          <span>•</span>
          <span>⚡ {activities.length} collaborative actions</span>
          <span>•</span>
          <span>🔍 {semanticSearchResults.length} semantic searches</span>
          <span>•</span>
          <span>🕸️ {dependencyAnalyses.length} graph analyses</span>
          <span>•</span>
          <span>👥 {collaborationUpdates.length} CRDT operations</span>
          <span>•</span>
          <span>📊 {performanceUpdates.length} performance samples</span>
        </div>
      </footer>
    </div>
  );
}

export default App;
