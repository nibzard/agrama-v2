# CRDT Observatory Integration

This document outlines the integration of CRDT collaborative features into the Agrama Observatory web interface.

## React Components for CRDT Visualization

### 1. Collaborative Code Editor Component

```typescript
// Enhanced collaborative code editor with real-time CRDT visualization
import React, { useState, useEffect, useRef } from 'react';
import { EditorState, EditorSelection } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';

interface AgentCursor {
    agent_id: string;
    agent_name: string;
    position: {
        line: number;
        column: number;
        offset: number;
    };
    updated_at: number;
}

interface CRDTOperation {
    operation_id: string;
    agent_id: string;
    operation_type: 'insert' | 'delete' | 'modify' | 'cursor_move';
    position: {
        line: number;
        column: number;
        offset: number;
    };
    content_preview: string;
    created_at: number;
}

interface ConflictEvent {
    conflict_id: string;
    operations_count: number;
    detected_at: number;
    resolved: boolean;
    resolution_strategy?: string;
}

const CollaborativeCodeEditor: React.FC<{
    documentPath: string;
    content: string;
    agentCursors: AgentCursor[];
    recentOperations: CRDTOperation[];
    conflicts: ConflictEvent[];
    onCursorUpdate?: (path: string, position: { line: number; column: number; offset: number }) => void;
}> = ({ 
    documentPath, 
    content, 
    agentCursors, 
    recentOperations, 
    conflicts,
    onCursorUpdate 
}) => {
    const editorRef = useRef<HTMLDivElement>(null);
    const editorViewRef = useRef<EditorView | null>(null);
    const [selectedAgent, setSelectedAgent] = useState<string>('');

    // Initialize CodeMirror editor
    useEffect(() => {
        if (!editorRef.current) return;

        const state = EditorState.create({
            doc: content,
            extensions: [
                javascript(),
                python(),
                EditorView.theme({
                    '.agent-cursor': {
                        position: 'absolute',
                        width: '2px',
                        height: '20px',
                        zIndex: 10,
                    },
                    '.agent-cursor-label': {
                        position: 'absolute',
                        top: '-25px',
                        left: '0',
                        background: '#333',
                        color: 'white',
                        padding: '2px 6px',
                        borderRadius: '3px',
                        fontSize: '12px',
                        whiteSpace: 'nowrap',
                    },
                    '.conflict-highlight': {
                        backgroundColor: 'rgba(255, 0, 0, 0.2)',
                    },
                    '.recent-operation-highlight': {
                        backgroundColor: 'rgba(0, 255, 0, 0.1)',
                        animation: 'fade-out 2s ease-out',
                    },
                }),
            ],
        });

        const view = new EditorView({
            state,
            parent: editorRef.current,
            dispatch: (transaction) => {
                view.update([transaction]);
                
                // Report cursor changes
                if (onCursorUpdate) {
                    const cursor = view.state.selection.main.head;
                    const line = view.state.doc.lineAt(cursor);
                    onCursorUpdate(documentPath, {
                        line: line.number,
                        column: cursor - line.from,
                        offset: cursor,
                    });
                }
            },
        });

        editorViewRef.current = view;

        return () => {
            view.destroy();
        };
    }, [documentPath]);

    // Update content when it changes
    useEffect(() => {
        if (editorViewRef.current && editorViewRef.current.state.doc.toString() !== content) {
            const view = editorViewRef.current;
            view.dispatch({
                changes: {
                    from: 0,
                    to: view.state.doc.length,
                    insert: content,
                },
            });
        }
    }, [content]);

    // Render agent cursors as overlays
    const renderAgentCursors = () => {
        if (!editorViewRef.current) return null;

        return agentCursors.map(cursor => {
            const view = editorViewRef.current!;
            const line = Math.min(cursor.position.line, view.state.doc.lines);
            const docLine = view.state.doc.line(line);
            const offset = Math.min(cursor.position.offset, docLine.to);
            const coords = view.coordsAtPos(offset);
            
            if (!coords) return null;

            const agentColor = getAgentColor(cursor.agent_id);
            const isSelected = selectedAgent === cursor.agent_id;

            return (
                <div
                    key={cursor.agent_id}
                    className={`agent-cursor ${isSelected ? 'selected' : ''}`}
                    style={{
                        left: coords.left,
                        top: coords.top,
                        borderLeft: `2px solid ${agentColor}`,
                        height: '20px',
                        opacity: isSelected ? 1 : 0.7,
                    }}
                    onClick={() => setSelectedAgent(
                        selectedAgent === cursor.agent_id ? '' : cursor.agent_id
                    )}
                >
                    <div 
                        className="agent-cursor-label"
                        style={{ backgroundColor: agentColor }}
                    >
                        {cursor.agent_name}
                    </div>
                </div>
            );
        });
    };

    return (
        <div className="collaborative-editor">
            <div className="editor-header">
                <h3>{documentPath}</h3>
                <div className="collaboration-indicators">
                    <span className="active-agents">
                        {agentCursors.length} agent{agentCursors.length !== 1 ? 's' : ''} active
                    </span>
                    {conflicts.length > 0 && (
                        <span className="conflicts-indicator">
                            {conflicts.length} conflict{conflicts.length !== 1 ? 's' : ''}
                        </span>
                    )}
                </div>
            </div>
            
            <div className="editor-container" style={{ position: 'relative' }}>
                <div ref={editorRef} />
                {renderAgentCursors()}
            </div>
            
            <div className="collaboration-footer">
                <RecentOperationsPanel operations={recentOperations} />
                <ConflictsPanel conflicts={conflicts} />
            </div>
        </div>
    );
};

// Helper function to assign consistent colors to agents
const getAgentColor = (agentId: string): string => {
    const colors = [
        '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', 
        '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F'
    ];
    const hash = agentId.split('').reduce((a, b) => {
        a = ((a << 5) - a) + b.charCodeAt(0);
        return a & a;
    }, 0);
    return colors[Math.abs(hash) % colors.length];
};
```

### 2. Real-Time Operations Panel

```typescript
const RecentOperationsPanel: React.FC<{ operations: CRDTOperation[] }> = ({ operations }) => {
    return (
        <div className="recent-operations-panel">
            <h4>Recent Collaborative Operations</h4>
            <div className="operations-list">
                {operations.map(operation => (
                    <div key={operation.operation_id} className="operation-item">
                        <div className="operation-header">
                            <span className={`operation-type ${operation.operation_type}`}>
                                {operation.operation_type.toUpperCase()}
                            </span>
                            <span className="agent-name">{operation.agent_id}</span>
                            <span className="operation-time">
                                {formatRelativeTime(operation.created_at)}
                            </span>
                        </div>
                        <div className="operation-details">
                            <span className="position">
                                Line {operation.position.line}, Col {operation.position.column}
                            </span>
                            <span className="content-preview">
                                "{operation.content_preview}"
                            </span>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
};

const formatRelativeTime = (timestamp: number): string => {
    const now = Date.now() / 1000;
    const diff = now - timestamp;
    
    if (diff < 60) return `${Math.floor(diff)}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    return `${Math.floor(diff / 3600)}h ago`;
};
```

### 3. Conflicts Resolution Panel

```typescript
const ConflictsPanel: React.FC<{ conflicts: ConflictEvent[] }> = ({ conflicts }) => {
    const [expandedConflict, setExpandedConflict] = useState<string>('');

    return (
        <div className="conflicts-panel">
            <h4>Conflicts {conflicts.length > 0 && `(${conflicts.length})`}</h4>
            {conflicts.length === 0 ? (
                <div className="no-conflicts">
                    <span className="checkmark">✓</span>
                    No conflicts detected
                </div>
            ) : (
                <div className="conflicts-list">
                    {conflicts.map(conflict => (
                        <div key={conflict.conflict_id} className="conflict-item">
                            <div 
                                className="conflict-header"
                                onClick={() => setExpandedConflict(
                                    expandedConflict === conflict.conflict_id ? '' : conflict.conflict_id
                                )}
                            >
                                <span className={`conflict-status ${conflict.resolved ? 'resolved' : 'unresolved'}`}>
                                    {conflict.resolved ? '✓ Resolved' : '⚠ Unresolved'}
                                </span>
                                <span className="conflict-operations">
                                    {conflict.operations_count} operations
                                </span>
                                <span className="conflict-time">
                                    {formatRelativeTime(conflict.detected_at)}
                                </span>
                                <span className="expand-arrow">
                                    {expandedConflict === conflict.conflict_id ? '▼' : '▶'}
                                </span>
                            </div>
                            
                            {expandedConflict === conflict.conflict_id && (
                                <div className="conflict-details">
                                    {conflict.resolution_strategy && (
                                        <div className="resolution-strategy">
                                            <strong>Resolution:</strong> {conflict.resolution_strategy}
                                        </div>
                                    )}
                                    <div className="conflict-actions">
                                        <button className="btn-resolve">Manual Review</button>
                                        <button className="btn-history">View History</button>
                                    </div>
                                </div>
                            )}
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
};
```

### 4. CRDT Statistics Dashboard

```typescript
interface CRDTStats {
    active_agents: number;
    active_documents: number;
    total_operations: number;
    total_conflicts: number;
    global_conflicts: number;
}

const CRDTStatsDashboard: React.FC<{ stats: CRDTStats }> = ({ stats }) => {
    return (
        <div className="crdt-stats-dashboard">
            <h3>Collaborative Editing Statistics</h3>
            <div className="stats-grid">
                <div className="stat-item">
                    <div className="stat-value">{stats.active_agents}</div>
                    <div className="stat-label">Active Agents</div>
                </div>
                <div className="stat-item">
                    <div className="stat-value">{stats.active_documents}</div>
                    <div className="stat-label">Documents</div>
                </div>
                <div className="stat-item">
                    <div className="stat-value">{stats.total_operations}</div>
                    <div className="stat-label">Total Operations</div>
                </div>
                <div className="stat-item">
                    <div className="stat-value">{stats.total_conflicts}</div>
                    <div className="stat-label">Conflicts Handled</div>
                </div>
            </div>
            
            <div className="stats-chart">
                <h4>Operation Rate (last 10 minutes)</h4>
                {/* Real-time chart showing CRDT operation frequency */}
                <OperationRateChart />
            </div>
        </div>
    );
};

const OperationRateChart: React.FC = () => {
    // Placeholder for operation rate visualization
    return (
        <div className="operation-rate-chart">
            <div style={{ height: '200px', backgroundColor: '#f5f5f5', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <span>Operation Rate Chart (D3.js implementation)</span>
            </div>
        </div>
    );
};
```

### 5. Main CRDT Observatory Component

```typescript
const CRDTObservatory: React.FC = () => {
    const [selectedDocument, setSelectedDocument] = useState<string>('');
    const [collaborativeData, setCollaborativeData] = useState<{
        documents: Map<string, {
            content: string;
            agentCursors: AgentCursor[];
            recentOperations: CRDTOperation[];
            conflicts: ConflictEvent[];
        }>;
        stats: CRDTStats;
    }>({
        documents: new Map(),
        stats: {
            active_agents: 0,
            active_documents: 0,
            total_operations: 0,
            total_conflicts: 0,
            global_conflicts: 0,
        },
    });

    // WebSocket connection for real-time CRDT events
    useEffect(() => {
        const ws = new WebSocket('ws://localhost:8080/observatory');
        
        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            
            switch (data.type) {
                case 'crdt_operation':
                    handleCRDTOperation(data);
                    break;
                case 'agent_cursor_update':
                    handleCursorUpdate(data);
                    break;
                case 'conflict_detected':
                    handleConflictDetected(data);
                    break;
                case 'conflict_resolved':
                    handleConflictResolved(data);
                    break;
                case 'crdt_agent_registered':
                    handleAgentRegistered(data);
                    break;
            }
        };

        // Request initial collaborative state
        ws.onopen = () => {
            ws.send(JSON.stringify({
                type: 'get_collaborative_context',
                params: { type: 'full' }
            }));
        };

        return () => ws.close();
    }, []);

    const handleCRDTOperation = (data: any) => {
        setCollaborativeData(prev => {
            const newData = { ...prev };
            const docData = newData.documents.get(data.document_path) || {
                content: '',
                agentCursors: [],
                recentOperations: [],
                conflicts: [],
            };

            // Add to recent operations
            docData.recentOperations = [
                {
                    operation_id: data.operation_id,
                    agent_id: data.agent_id,
                    operation_type: data.operation_type,
                    position: data.position,
                    content_preview: `${data.operation_type} operation`,
                    created_at: data.timestamp,
                },
                ...docData.recentOperations.slice(0, 9) // Keep last 10
            ];

            newData.documents.set(data.document_path, docData);
            return newData;
        });
    };

    const handleCursorUpdate = (data: any) => {
        setCollaborativeData(prev => {
            const newData = { ...prev };
            const docData = newData.documents.get(data.document_path) || {
                content: '',
                agentCursors: [],
                recentOperations: [],
                conflicts: [],
            };

            // Update or add agent cursor
            const existingIndex = docData.agentCursors.findIndex(c => c.agent_id === data.agent_id);
            const cursorData = {
                agent_id: data.agent_id,
                agent_name: data.agent_name || data.agent_id,
                position: data.position,
                updated_at: data.timestamp,
            };

            if (existingIndex >= 0) {
                docData.agentCursors[existingIndex] = cursorData;
            } else {
                docData.agentCursors.push(cursorData);
            }

            newData.documents.set(data.document_path, docData);
            return newData;
        });
    };

    const handleConflictDetected = (data: any) => {
        setCollaborativeData(prev => {
            const newData = { ...prev };
            const docData = newData.documents.get(data.document_path) || {
                content: '',
                agentCursors: [],
                recentOperations: [],
                conflicts: [],
            };

            docData.conflicts.push({
                conflict_id: data.conflict_id,
                operations_count: data.operations_count,
                detected_at: data.detected_at,
                resolved: false,
            });

            newData.documents.set(data.document_path, docData);
            return newData;
        });
    };

    const handleConflictResolved = (data: any) => {
        setCollaborativeData(prev => {
            const newData = { ...prev };
            for (const [path, docData] of newData.documents) {
                const conflictIndex = docData.conflicts.findIndex(c => c.conflict_id === data.conflict_id);
                if (conflictIndex >= 0) {
                    docData.conflicts[conflictIndex].resolved = true;
                    docData.conflicts[conflictIndex].resolution_strategy = data.resolution_strategy;
                    break;
                }
            }
            return newData;
        });
    };

    const handleAgentRegistered = (data: any) => {
        console.log('Agent registered for CRDT collaboration:', data.agent_name);
    };

    const handleCursorUpdate = (path: string, position: { line: number; column: number; offset: number }) => {
        // Send cursor update to server (if we had write access)
        console.log('Cursor update:', path, position);
    };

    const selectedDocumentData = collaborativeData.documents.get(selectedDocument);

    return (
        <div className="crdt-observatory">
            <div className="observatory-header">
                <h1>CRDT Collaborative Observatory</h1>
                <CRDTStatsDashboard stats={collaborativeData.stats} />
            </div>

            <div className="observatory-layout">
                <div className="documents-panel">
                    <h3>Active Documents</h3>
                    <div className="documents-list">
                        {Array.from(collaborativeData.documents.keys()).map(path => (
                            <div
                                key={path}
                                className={`document-item ${selectedDocument === path ? 'selected' : ''}`}
                                onClick={() => setSelectedDocument(path)}
                            >
                                <div className="document-name">{path}</div>
                                <div className="document-indicators">
                                    <span className="agents-count">
                                        {collaborativeData.documents.get(path)?.agentCursors.length || 0}
                                    </span>
                                    {(collaborativeData.documents.get(path)?.conflicts.length || 0) > 0 && (
                                        <span className="conflicts-indicator">⚠</span>
                                    )}
                                </div>
                            </div>
                        ))}
                    </div>
                </div>

                <div className="main-editor-panel">
                    {selectedDocumentData ? (
                        <CollaborativeCodeEditor
                            documentPath={selectedDocument}
                            content={selectedDocumentData.content}
                            agentCursors={selectedDocumentData.agentCursors}
                            recentOperations={selectedDocumentData.recentOperations}
                            conflicts={selectedDocumentData.conflicts}
                            onCursorUpdate={handleCursorUpdate}
                        />
                    ) : (
                        <div className="no-document-selected">
                            <h3>Select a document to view collaborative editing</h3>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
};

export default CRDTObservatory;
```

## CSS Styles for CRDT Components

```css
/* CRDT Observatory Styles */
.crdt-observatory {
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: #f8f9fa;
}

.observatory-header {
    background: white;
    padding: 20px;
    border-bottom: 1px solid #e9ecef;
}

.observatory-layout {
    flex: 1;
    display: flex;
    overflow: hidden;
}

.documents-panel {
    width: 300px;
    background: white;
    border-right: 1px solid #e9ecef;
    padding: 20px;
}

.document-item {
    padding: 12px;
    border-radius: 6px;
    cursor: pointer;
    margin-bottom: 8px;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.document-item:hover {
    background: #f8f9fa;
}

.document-item.selected {
    background: #e3f2fd;
    border: 1px solid #2196f3;
}

.document-indicators {
    display: flex;
    gap: 8px;
    align-items: center;
}

.agents-count {
    background: #4caf50;
    color: white;
    padding: 2px 6px;
    border-radius: 10px;
    font-size: 12px;
}

.conflicts-indicator {
    color: #ff9800;
    font-weight: bold;
}

.main-editor-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
}

.collaborative-editor {
    flex: 1;
    display: flex;
    flex-direction: column;
    background: white;
    margin: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.editor-header {
    padding: 16px;
    border-bottom: 1px solid #e9ecef;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.collaboration-indicators {
    display: flex;
    gap: 16px;
    font-size: 14px;
}

.active-agents {
    color: #4caf50;
}

.conflicts-indicator {
    color: #f44336;
    font-weight: bold;
}

.editor-container {
    flex: 1;
    position: relative;
}

.agent-cursor {
    pointer-events: none;
    transition: opacity 0.2s;
}

.agent-cursor.selected {
    pointer-events: auto;
}

.agent-cursor-label {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    pointer-events: auto;
    cursor: pointer;
}

.collaboration-footer {
    border-top: 1px solid #e9ecef;
    display: flex;
    height: 200px;
}

.recent-operations-panel,
.conflicts-panel {
    flex: 1;
    padding: 16px;
    overflow-y: auto;
}

.conflicts-panel {
    border-left: 1px solid #e9ecef;
}

.operation-item,
.conflict-item {
    border: 1px solid #e9ecef;
    border-radius: 6px;
    padding: 12px;
    margin-bottom: 8px;
}

.operation-header,
.conflict-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
}

.operation-type {
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: bold;
}

.operation-type.insert {
    background: #e8f5e8;
    color: #4caf50;
}

.operation-type.delete {
    background: #ffebee;
    color: #f44336;
}

.operation-type.modify {
    background: #fff3e0;
    color: #ff9800;
}

.conflict-status.resolved {
    color: #4caf50;
}

.conflict-status.unresolved {
    color: #f44336;
}

.crdt-stats-dashboard {
    margin-top: 20px;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 20px;
    margin-bottom: 20px;
}

.stat-item {
    text-align: center;
    padding: 16px;
    background: #f8f9fa;
    border-radius: 8px;
}

.stat-value {
    font-size: 28px;
    font-weight: bold;
    color: #2196f3;
}

.stat-label {
    font-size: 14px;
    color: #666;
    margin-top: 4px;
}

@keyframes fade-out {
    0% { background-color: rgba(0, 255, 0, 0.3); }
    100% { background-color: rgba(0, 255, 0, 0); }
}

.no-conflicts {
    display: flex;
    align-items: center;
    gap: 8px;
    color: #4caf50;
    font-style: italic;
}

.no-document-selected {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #666;
}
```

This Observatory integration provides:

1. **Real-time Collaborative Editor**: Shows live agent cursors and operations
2. **Conflict Visualization**: Real-time conflict detection and resolution status  
3. **Operation History**: Live feed of CRDT operations from all agents
4. **Statistics Dashboard**: Comprehensive metrics on collaborative activity
5. **Multi-Document Support**: Switch between different files being edited
6. **Agent Awareness**: Visual indicators of who's editing what and where

The interface will enable users to observe AI agents collaborating in real-time, see conflicts as they arise and get resolved, and understand the full collaborative development process.