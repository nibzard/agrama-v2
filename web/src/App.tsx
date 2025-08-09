// Agrama CodeGraph Observatory - Real-time AI-Human Collaboration Interface
import { useWebSocket } from './hooks/useWebSocket';
import { ActivityFeed } from './components/ActivityFeed';
import { FileExplorer } from './components/FileExplorer';
import { CommandInput } from './components/CommandInput';
import { AgentStatus } from './components/AgentStatus';
import './App.css';

function App() {
  const {
    connected,
    connecting,
    error,
    agents,
    activities,
    fileChanges,
    commands,
    sendCommand,
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
          <p className="subtitle">Real-time AI-Human Collaboration Interface</p>
        </div>
        <div className="header-right">
          <div className="connection-status">
            {connecting && <span className="status connecting">🔄 Connecting...</span>}
            {connected && <span className="status connected">🟢 Connected</span>}
            {error && (
              <div className="status error">
                <span>❌ {error}</span>
                <button onClick={reconnect} className="reconnect-btn">
                  Reconnect
                </button>
              </div>
            )}
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

        {/* Center Panel - Activity Feed */}
        <section className="center-panel">
          <ActivityFeed
            activities={activities}
            agents={agents}
            maxItems={100}
          />
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
          <span>Agrama v2.0 - Temporal Knowledge Graph Database</span>
          <span>•</span>
          <span>Observatory Interface - Phase 3</span>
          <span>•</span>
          <span>WebSocket: ws://localhost:8080</span>
        </div>
        <div className="footer-stats">
          <span>{agents.size} agents</span>
          <span>•</span>
          <span>{activities.length} activities</span>
          <span>•</span>
          <span>{fileChanges.length} file changes</span>
          <span>•</span>
          <span>{commands.length} commands</span>
        </div>
      </footer>
    </div>
  );
}

export default App;
