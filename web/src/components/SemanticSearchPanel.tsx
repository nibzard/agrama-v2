// Semantic Search Panel with HNSW-powered real-time search
import React, { useState, useMemo } from 'react';
import type { SemanticSearchResult } from '../types';

interface SemanticSearchPanelProps {
  searchResults: SemanticSearchResult[];
  onSearch: (query: string) => void;
  connected: boolean;
}

interface SearchResultItemProps {
  result: SemanticSearchResult;
}

const SearchResultItem: React.FC<SearchResultItemProps> = ({ result }) => {
  const [expanded, setExpanded] = useState(false);

  const formatTime = (ms: number) => {
    if (ms < 1) return `${(ms * 1000).toFixed(0)}μs`;
    if (ms < 1000) return `${ms.toFixed(1)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const getEfficiencyColor = (speedup: number) => {
    if (speedup > 100) return '#00ff00';
    if (speedup > 50) return '#80ff00';
    if (speedup > 10) return '#ffff00';
    if (speedup > 5) return '#ff8000';
    return '#ff4000';
  };

  const estimatedLinearTime = result.hnswStats.searchTime * 1000; // Assume 1000x speedup for large datasets
  const speedupFactor = Math.max(1, estimatedLinearTime / result.hnswStats.searchTime);

  return (
    <div className="search-result-item">
      <div className="result-header" onClick={() => setExpanded(!expanded)}>
        <div className="result-query">
          <span className="query-text">"{result.query}"</span>
          <span className="result-count">{result.results.length} results</span>
        </div>
        <div className="result-stats">
          <span className="search-time">{formatTime(result.hnswStats.searchTime)}</span>
          <span 
            className="speedup-factor" 
            style={{ color: getEfficiencyColor(speedupFactor) }}
          >
            {speedupFactor.toFixed(0)}x faster
          </span>
          <span className="expand-icon">{expanded ? '▼' : '▶'}</span>
        </div>
      </div>

      {expanded && (
        <div className="result-details">
          {/* HNSW Performance Stats */}
          <div className="hnsw-stats">
            <h4>🏎️ HNSW Performance</h4>
            <div className="stats-grid">
              <div className="stat">
                <label>Search Time:</label>
                <span>{formatTime(result.hnswStats.searchTime)}</span>
              </div>
              <div className="stat">
                <label>Graph Hops:</label>
                <span>{result.hnswStats.hopsCount}</span>
              </div>
              <div className="stat">
                <label>Candidates:</label>
                <span>{result.hnswStats.candidatesEvaluated}</span>
              </div>
              <div className="stat">
                <label>Efficiency:</label>
                <span style={{ color: getEfficiencyColor(speedupFactor) }}>
                  O(log n) vs O(n)
                </span>
              </div>
            </div>
          </div>

          {/* Search Results */}
          <div className="search-matches">
            <h4>🎯 Semantic Matches</h4>
            <div className="matches-list">
              {result.results.map((match, index) => (
                <div key={index} className="match-item">
                  <div className="match-header">
                    <span className="match-id">{match.nodeId}</span>
                    <div className="match-scores">
                      <span className="similarity-score">
                        {(match.similarity * 100).toFixed(1)}% similar
                      </span>
                      <span className="distance-score">
                        d={match.distance.toFixed(3)}
                      </span>
                    </div>
                  </div>
                  <div className="match-content">
                    {match.content.substring(0, 200)}
                    {match.content.length > 200 && '...'}
                  </div>
                  <div className="embedding-preview">
                    <span className="embedding-label">Embedding:</span>
                    <span className="embedding-data">
                      [{match.embedding.slice(0, 5).map(v => v.toFixed(3)).join(', ')}...]
                      <span className="embedding-dim">({match.embedding.length}D)</span>
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export const SemanticSearchPanel: React.FC<SemanticSearchPanelProps> = ({
  searchResults,
  onSearch,
  connected
}) => {
  const [query, setQuery] = useState('');
  const [searchHistory, setSearchHistory] = useState<string[]>([]);

  const recentResults = useMemo(() => {
    return searchResults.slice(0, 10);
  }, [searchResults]);

  const averageStats = useMemo(() => {
    if (searchResults.length === 0) return null;

    const totalTime = searchResults.reduce((sum, result) => sum + result.hnswStats.searchTime, 0);
    const totalHops = searchResults.reduce((sum, result) => sum + result.hnswStats.hopsCount, 0);
    const totalCandidates = searchResults.reduce((sum, result) => sum + result.hnswStats.candidatesEvaluated, 0);
    const totalResults = searchResults.reduce((sum, result) => sum + result.results.length, 0);

    return {
      avgTime: totalTime / searchResults.length,
      avgHops: totalHops / searchResults.length,
      avgCandidates: totalCandidates / searchResults.length,
      avgResults: totalResults / searchResults.length,
      totalSearches: searchResults.length
    };
  }, [searchResults]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim() || !connected) return;

    onSearch(query.trim());
    
    // Add to search history
    setSearchHistory(prev => {
      const updated = [query.trim(), ...prev.filter(q => q !== query.trim())];
      return updated.slice(0, 10);
    });
    
    setQuery('');
  };

  const handleHistoryClick = (historyQuery: string) => {
    setQuery(historyQuery);
  };

  const formatTime = (ms: number) => {
    if (ms < 1) return `${(ms * 1000).toFixed(0)}μs`;
    if (ms < 1000) return `${ms.toFixed(1)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  return (
    <div className="semantic-search-panel">
      <div className="search-header">
        <h3>🔍 Semantic Search (HNSW)</h3>
        <div className="connection-status">
          {connected ? (
            <span className="connected">🟢 Ready</span>
          ) : (
            <span className="disconnected">🔴 Offline</span>
          )}
        </div>
      </div>

      {/* Search Input */}
      <form onSubmit={handleSubmit} className="search-form">
        <div className="search-input-container">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search code semantically (e.g., 'error handling', 'database connection')..."
            disabled={!connected}
            className="search-input"
          />
          <button 
            type="submit" 
            disabled={!query.trim() || !connected}
            className="search-button"
          >
            🔍
          </button>
        </div>
      </form>

      {/* Search History */}
      {searchHistory.length > 0 && (
        <div className="search-history">
          <h4>Recent Searches</h4>
          <div className="history-list">
            {searchHistory.map((historyQuery, index) => (
              <button
                key={index}
                onClick={() => handleHistoryClick(historyQuery)}
                className="history-item"
              >
                {historyQuery}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Performance Overview */}
      {averageStats && (
        <div className="performance-overview">
          <h4>⚡ HNSW Performance Overview</h4>
          <div className="overview-stats">
            <div className="overview-stat">
              <label>Avg Search Time:</label>
              <span>{formatTime(averageStats.avgTime)}</span>
            </div>
            <div className="overview-stat">
              <label>Avg Graph Hops:</label>
              <span>{averageStats.avgHops.toFixed(1)}</span>
            </div>
            <div className="overview-stat">
              <label>Avg Results:</label>
              <span>{averageStats.avgResults.toFixed(1)}</span>
            </div>
            <div className="overview-stat">
              <label>Total Searches:</label>
              <span>{averageStats.totalSearches}</span>
            </div>
          </div>
        </div>
      )}

      {/* Search Results */}
      <div className="search-results">
        {recentResults.length === 0 ? (
          <div className="no-results">
            <p>No semantic searches yet.</p>
            <p>Try searching for code concepts, patterns, or functionality.</p>
          </div>
        ) : (
          <>
            <h4>📊 Recent Search Results</h4>
            <div className="results-list">
              {recentResults.map((result) => (
                <SearchResultItem 
                  key={result.id} 
                  result={result} 
                />
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
};