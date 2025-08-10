// Dependency Graph Visualization with FRE-powered analysis
import React, { useEffect, useRef, useState, useMemo } from 'react';
import * as d3 from 'd3';
import type { DependencyAnalysis, DependencyNode, DependencyEdge } from '../types';

interface DependencyGraphVizProps {
  dependencyAnalyses: DependencyAnalysis[];
  width?: number;
  height?: number;
}

interface GraphData {
  nodes: DependencyNode[];
  edges: DependencyEdge[];
  analysis: DependencyAnalysis;
}

export const DependencyGraphViz: React.FC<DependencyGraphVizProps> = ({
  dependencyAnalyses,
  width = 800,
  height = 600
}) => {
  const svgRef = useRef<SVGSVGElement>(null);
  const [selectedAnalysis, setSelectedAnalysis] = useState<string | null>(null);
  const [, setHoveredNode] = useState<string | null>(null);
  const [showImpactPaths, setShowImpactPaths] = useState(true);

  const currentAnalysis = useMemo(() => {
    if (!selectedAnalysis || dependencyAnalyses.length === 0) {
      return dependencyAnalyses[0] || null;
    }
    return dependencyAnalyses.find(a => a.id === selectedAnalysis) || dependencyAnalyses[0];
  }, [selectedAnalysis, dependencyAnalyses]);

  const graphData = useMemo<GraphData | null>(() => {
    if (!currentAnalysis) return null;
    
    return {
      nodes: currentAnalysis.nodes.map(node => ({
        ...node,
        x: node.x || Math.random() * width,
        y: node.y || Math.random() * height
      })),
      edges: currentAnalysis.edges,
      analysis: currentAnalysis
    };
  }, [currentAnalysis, width, height]);

  useEffect(() => {
    if (!graphData || !svgRef.current) return;

    const svg = d3.select(svgRef.current);
    svg.selectAll("*").remove();

    // Create container group
    const container = svg.append("g");

    // Add zoom behavior
    const zoom = d3.zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.1, 4])
      .on("zoom", (event) => {
        container.attr("transform", event.transform);
      });

    svg.call(zoom);

    // Color scales
    const nodeTypeColor = d3.scaleOrdinal<string>()
      .domain(['file', 'function', 'class', 'module'])
      .range(['#ff6b6b', '#4ecdc4', '#45b7d1', '#f9ca24']);

    const edgeTypeColor = d3.scaleOrdinal<string>()
      .domain(['imports', 'calls', 'extends', 'implements'])
      .range(['#2196F3', '#FF9800', '#4CAF50', '#9C27B0']);

    // Node size scale based on complexity
    const nodeSize = d3.scaleLinear()
      .domain(d3.extent(graphData.nodes, d => (d as DependencyNode).complexity) as [number, number])
      .range([8, 25]);

    // Edge width scale based on weight
    const edgeWidth = d3.scaleLinear()
      .domain(d3.extent(graphData.edges, d => d.weight) as [number, number])
      .range([1, 6]);

    // Create force simulation
    const simulation = d3.forceSimulation(graphData.nodes)
      .force("link", d3.forceLink<DependencyNode, DependencyEdge>(graphData.edges)
        .id(d => d.id)
        .distance(80)
        .strength(0.3))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius(d => nodeSize((d as DependencyNode).complexity) + 5));

    // Add markers for arrow heads
    const defs = container.append("defs");
    
    ['imports', 'calls', 'extends', 'implements'].forEach(type => {
      defs.append("marker")
        .attr("id", `arrow-${type}`)
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 15)
        .attr("refY", 0)
        .attr("markerWidth", 6)
        .attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path")
        .attr("d", "M0,-5L10,0L0,5")
        .attr("fill", edgeTypeColor(type))
        .style("opacity", 0.8);
    });

    // Create edges
    const edges = container.selectAll(".edge")
      .data(graphData.edges)
      .enter()
      .append("line")
      .attr("class", "edge")
      .style("stroke", d => edgeTypeColor(d.type))
      .style("stroke-width", d => edgeWidth(d.weight))
      .style("opacity", 0.6)
      .attr("marker-end", d => `url(#arrow-${d.type})`);

    // Create impact paths (if enabled)
    let impactPaths: d3.Selection<SVGPathElement, { path: string[]; weight: number; impactScore: number }, SVGGElement, unknown> | null = null;
    if (showImpactPaths && graphData.analysis.impactPaths.length > 0) {
      const pathGenerator = d3.line<DependencyNode>()
        .x(d => d.x!)
        .y(d => d.y!)
        .curve(d3.curveCatmullRom);

      impactPaths = container.selectAll(".impact-path")
        .data(graphData.analysis.impactPaths)
        .enter()
        .append("path")
        .attr("class", "impact-path")
        .style("fill", "none")
        .style("stroke", "#ff4757")
        .style("stroke-width", d => Math.max(2, d.impactScore * 8))
        .style("stroke-dasharray", "5,5")
        .style("opacity", 0.7)
        .attr("d", path => {
          const pathNodes = path.path.map(nodeId => 
            graphData.nodes.find(n => n.id === nodeId)!
          ).filter(Boolean);
          return pathGenerator(pathNodes);
        });
    }

    // Create nodes
    const nodes = container.selectAll(".node")
      .data(graphData.nodes)
      .enter()
      .append("g")
      .attr("class", "node")
      .style("cursor", "pointer")
      .call(d3.drag<SVGGElement, DependencyNode>()
        .on("start", (_, d) => {
          simulation.alphaTarget(0.3).restart();
          d.fx = d.x;
          d.fy = d.y;
        })
        .on("drag", (event, d) => {
          d.fx = event.x;
          d.fy = event.y;
        })
        .on("end", (_, d) => {
          simulation.alphaTarget(0);
          d.fx = null;
          d.fy = null;
        }));

    // Node circles
    nodes.append("circle")
      .attr("r", d => nodeSize(d.complexity))
      .style("fill", d => nodeTypeColor(d.type))
      .style("stroke", "#fff")
      .style("stroke-width", 2)
      .style("opacity", 0.8);

    // Node labels
    nodes.append("text")
      .attr("dy", ".35em")
      .attr("text-anchor", "middle")
      .style("font-size", "10px")
      .style("font-weight", "bold")
      .style("fill", "#333")
      .text(d => d.name.length > 8 ? d.name.substring(0, 8) + '...' : d.name);

    // Node interaction
    nodes
      .on("mouseenter", (_, d) => {
        setHoveredNode(d.id);
        
        // Highlight connected edges
        edges.style("opacity", edge => 
          (edge.source as DependencyNode).id === d.id || 
          (edge.target as DependencyNode).id === d.id ? 0.9 : 0.2
        );
        
        // Highlight connected nodes
        nodes.style("opacity", node => {
          if (node.id === d.id) return 1;
          const isConnected = graphData.edges.some(edge => 
            ((edge.source as DependencyNode).id === d.id && (edge.target as DependencyNode).id === node.id) ||
            ((edge.target as DependencyNode).id === d.id && (edge.source as DependencyNode).id === node.id)
          );
          return isConnected ? 0.8 : 0.3;
        });
      })
      .on("mouseleave", () => {
        setHoveredNode(null);
        edges.style("opacity", 0.6);
        nodes.style("opacity", 0.8);
      });

    // Update positions on simulation tick
    simulation.on("tick", () => {
      edges
        .attr("x1", d => (d.source as DependencyNode).x!)
        .attr("y1", d => (d.source as DependencyNode).y!)
        .attr("x2", d => (d.target as DependencyNode).x!)
        .attr("y2", d => (d.target as DependencyNode).y!);

      nodes.attr("transform", d => `translate(${d.x!},${d.y!})`);

      if (impactPaths) {
        impactPaths.attr("d", path => {
          const pathNodes = path.path.map((nodeId: string) => 
            graphData.nodes.find(n => n.id === nodeId)!
          ).filter(Boolean);
          return d3.line<DependencyNode>()
            .x(d => d.x!)
            .y(d => d.y!)
            .curve(d3.curveCatmullRom)(pathNodes);
        });
      }
    });

    // Cleanup
    return () => {
      simulation.stop();
    };
  }, [graphData, width, height, showImpactPaths]);

  const formatTime = (ms: number) => {
    if (ms < 1) return `${(ms * 1000).toFixed(0)}μs`;
    if (ms < 1000) return `${ms.toFixed(1)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const getComplexityColor = (complexity: string) => {
    if (complexity.includes('log^(2/3)')) return '#00ff00';
    if (complexity.includes('log n')) return '#80ff00';
    if (complexity.includes('n log n')) return '#ff8000';
    return '#ff4000';
  };

  return (
    <div className="dependency-graph-viz">
      <div className="graph-header">
        <h3>🕸️ Dependency Graph (FRE)</h3>
        
        {/* Analysis Selection */}
        {dependencyAnalyses.length > 1 && (
          <select
            value={selectedAnalysis || ''}
            onChange={(e) => setSelectedAnalysis(e.target.value || null)}
            className="analysis-selector"
          >
            <option value="">Latest Analysis</option>
            {dependencyAnalyses.map(analysis => (
              <option key={analysis.id} value={analysis.id}>
                {analysis.targetNode} - {new Date(analysis.id).toLocaleTimeString()}
              </option>
            ))}
          </select>
        )}

        {/* Controls */}
        <div className="graph-controls">
          <label className="control-label">
            <input
              type="checkbox"
              checked={showImpactPaths}
              onChange={(e) => setShowImpactPaths(e.target.checked)}
            />
            Show Impact Paths
          </label>
        </div>
      </div>

      {/* FRE Performance Stats */}
      {currentAnalysis && (
        <div className="fre-stats">
          <h4>🚀 FRE Performance</h4>
          <div className="stats-grid">
            <div className="stat">
              <label>Traversal Time:</label>
              <span>{formatTime(currentAnalysis.freStats.traversalTime)}</span>
            </div>
            <div className="stat">
              <label>Nodes Visited:</label>
              <span>{currentAnalysis.freStats.nodesVisited.toLocaleString()}</span>
            </div>
            <div className="stat">
              <label>Paths Found:</label>
              <span>{currentAnalysis.freStats.pathsFound.toLocaleString()}</span>
            </div>
            <div className="stat">
              <label>Complexity:</label>
              <span style={{ color: getComplexityColor(currentAnalysis.freStats.complexity) }}>
                {currentAnalysis.freStats.complexity}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Graph Visualization */}
      <div className="graph-container">
        <svg
          ref={svgRef}
          width={width}
          height={height}
          className="dependency-graph"
          style={{ border: '1px solid #ddd', borderRadius: '8px' }}
        />
      </div>

      {/* Legend */}
      <div className="graph-legend">
        <div className="legend-section">
          <h4>Node Types</h4>
          <div className="legend-items">
            <div className="legend-item">
              <div className="legend-color" style={{ backgroundColor: '#ff6b6b' }}></div>
              <span>File</span>
            </div>
            <div className="legend-item">
              <div className="legend-color" style={{ backgroundColor: '#4ecdc4' }}></div>
              <span>Function</span>
            </div>
            <div className="legend-item">
              <div className="legend-color" style={{ backgroundColor: '#45b7d1' }}></div>
              <span>Class</span>
            </div>
            <div className="legend-item">
              <div className="legend-color" style={{ backgroundColor: '#f9ca24' }}></div>
              <span>Module</span>
            </div>
          </div>
        </div>
        
        <div className="legend-section">
          <h4>Edge Types</h4>
          <div className="legend-items">
            <div className="legend-item">
              <div className="legend-line" style={{ backgroundColor: '#2196F3' }}></div>
              <span>Imports</span>
            </div>
            <div className="legend-item">
              <div className="legend-line" style={{ backgroundColor: '#FF9800' }}></div>
              <span>Calls</span>
            </div>
            <div className="legend-item">
              <div className="legend-line" style={{ backgroundColor: '#4CAF50' }}></div>
              <span>Extends</span>
            </div>
            <div className="legend-item">
              <div className="legend-line" style={{ backgroundColor: '#9C27B0' }}></div>
              <span>Implements</span>
            </div>
          </div>
        </div>
      </div>

      {/* Impact Paths Details */}
      {currentAnalysis && currentAnalysis.impactPaths.length > 0 && (
        <div className="impact-paths">
          <h4>💥 Impact Paths</h4>
          <div className="paths-list">
            {currentAnalysis.impactPaths.slice(0, 5).map((path, index) => (
              <div key={index} className="impact-path-item">
                <div className="path-header">
                  <span className="path-weight">Weight: {path.weight.toFixed(2)}</span>
                  <span className="path-impact">Impact: {(path.impactScore * 100).toFixed(1)}%</span>
                </div>
                <div className="path-nodes">
                  {path.path.join(' → ')}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};