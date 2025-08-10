// File explorer with agent activity indicators
import React, { useState, useMemo } from 'react';
import type { FileChange, AgentConnection } from '../types';

interface FileExplorerProps {
  fileChanges: FileChange[];
  agents: Map<string, AgentConnection>;
}

interface FileNode {
  path: string;
  name: string;
  type: 'file' | 'directory';
  children: Map<string, FileNode>;
  lastChange?: FileChange;
  changeCount: number;
}

interface FileItemProps {
  node: FileNode;
  depth: number;
  expanded: Set<string>;
  onToggle: (path: string) => void;
  getAgentName: (agentId: string) => string;
}

const FileItem: React.FC<FileItemProps> = ({ 
  node, 
  depth, 
  expanded, 
  onToggle,
  getAgentName 
}) => {
  const isExpanded = expanded.has(node.path);
  const hasChildren = node.children.size > 0;
  
  const getFileIcon = () => {
    if (node.type === 'directory') {
      return hasChildren ? (isExpanded ? '📂' : '📁') : '📁';
    }
    
    const ext = node.name.split('.').pop()?.toLowerCase();
    switch (ext) {
      case 'ts': case 'tsx': return '📘';
      case 'js': case 'jsx': return '📙';
      case 'zig': return '⚡';
      case 'json': return '📄';
      case 'md': return '📝';
      case 'css': return '🎨';
      case 'html': return '🌐';
      default: return '📄';
    }
  };
  
  const getActivityIndicator = () => {
    if (!node.lastChange) return null;
    
    const timeSinceChange = Date.now() - node.lastChange.timestamp.getTime();
    const isRecent = timeSinceChange < 60000; // 1 minute
    
    if (!isRecent) return null;
    
    const actionIcon = node.lastChange.action === 'write' ? '✏️' : 
                      node.lastChange.action === 'read' ? '👀' : '🔍';
    
    return (
      <span className="file-activity" title={`${node.lastChange.action} by ${getAgentName(node.lastChange.agentId)}`}>
        {actionIcon}
      </span>
    );
  };
  
  const getChangeCount = () => {
    if (node.changeCount === 0) return null;
    return (
      <span className="file-change-count" title={`${node.changeCount} changes`}>
        {node.changeCount}
      </span>
    );
  };
  
  return (
    <div className="file-item" style={{ paddingLeft: `${depth * 20}px` }}>
      <div 
        className={`file-row ${node.type}`}
        onClick={() => hasChildren && onToggle(node.path)}
        style={{ cursor: hasChildren ? 'pointer' : 'default' }}
      >
        <span className="file-icon">{getFileIcon()}</span>
        <span className="file-name">{node.name}</span>
        {getActivityIndicator()}
        {getChangeCount()}
      </div>
      
      {hasChildren && isExpanded && (
        <div className="file-children">
          {Array.from(node.children.values())
            .sort((a, b) => {
              // Directories first, then files
              if (a.type !== b.type) {
                return a.type === 'directory' ? -1 : 1;
              }
              return a.name.localeCompare(b.name);
            })
            .map(child => (
              <FileItem 
                key={child.path}
                node={child}
                depth={depth + 1}
                expanded={expanded}
                onToggle={onToggle}
                getAgentName={getAgentName}
              />
            ))}
        </div>
      )}
    </div>
  );
};

export const FileExplorer: React.FC<FileExplorerProps> = ({ fileChanges, agents }) => {
  const [expanded, setExpanded] = useState<Set<string>>(new Set(['/']));
  
  const fileTree = useMemo(() => {
    const root: FileNode = {
      path: '/',
      name: 'Project',
      type: 'directory',
      children: new Map(),
      changeCount: 0
    };
    
    // Build file tree from changes
    fileChanges.forEach(change => {
      const parts = change.path.split('/').filter(Boolean);
      let current = root;
      let currentPath = '';
      
      // Create directory structure
      for (let i = 0; i < parts.length - 1; i++) {
        const part = parts[i];
        currentPath += '/' + part;
        
        if (!current.children.has(part)) {
          current.children.set(part, {
            path: currentPath,
            name: part,
            type: 'directory',
            children: new Map(),
            changeCount: 0
          });
        }
        current = current.children.get(part)!;
      }
      
      // Create file node
      const fileName = parts[parts.length - 1];
      const filePath = change.path;
      
      if (!current.children.has(fileName)) {
        current.children.set(fileName, {
          path: filePath,
          name: fileName,
          type: 'file',
          children: new Map(),
          changeCount: 0
        });
      }
      
      const fileNode = current.children.get(fileName)!;
      
      // Update change information
      if (!fileNode.lastChange || change.timestamp > fileNode.lastChange.timestamp) {
        fileNode.lastChange = change;
      }
      fileNode.changeCount++;
      
      // Propagate change count up the tree
      const parent = current;
      const parentPath = currentPath.split('/').slice(0, -1).join('/') || '/';
      while (parent && parent !== root) {
        parent.changeCount++;
        const parentName = parentPath.split('/').pop();
        if (!parentName) break;
        parentPath = parentPath.split('/').slice(0, -1).join('/') || '/';
        // Find parent in tree - this is a simplification
        break;
      }
    });
    
    return root;
  }, [fileChanges]);
  
  const handleToggle = (path: string) => {
    setExpanded(prev => {
      const updated = new Set(prev);
      if (updated.has(path)) {
        updated.delete(path);
      } else {
        updated.add(path);
      }
      return updated;
    });
  };
  
  const getAgentName = (agentId: string) => {
    return agents.get(agentId)?.name || agentId;
  };
  
  const totalFiles = fileTree.children.size;
  const totalChanges = fileChanges.length;
  
  return (
    <div className="file-explorer">
      <div className="file-explorer-header">
        <h3>Project Files</h3>
        <div className="file-stats">
          <span>{totalFiles} files</span>
          <span>{totalChanges} changes</span>
        </div>
      </div>
      
      <div className="file-tree">
        {fileTree.children.size === 0 ? (
          <div className="file-empty">
            No file activity yet. Agents will populate this as they work.
          </div>
        ) : (
          <FileItem 
            node={fileTree}
            depth={-1}
            expanded={expanded}
            onToggle={handleToggle}
            getAgentName={getAgentName}
          />
        )}
      </div>
    </div>
  );
};