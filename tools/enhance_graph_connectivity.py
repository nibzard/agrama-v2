#!/usr/bin/env python3
"""
Enhance synthetic graph connectivity by adding more edges.
Ensures all graphs have good connectivity for pathfinding benchmarks.
"""

import json
import random
import sys
from pathlib import Path

def enhance_graph_connectivity(graph_file, target_connectivity=0.15):
    """
    Enhance graph connectivity by adding more edges.
    
    Args:
        graph_file: Path to JSON graph file
        target_connectivity: Target edge density (edges / (nodes * (nodes-1)))
    """
    print(f"🔧 Enhancing connectivity for {graph_file}")
    
    # Load graph
    with open(graph_file, 'r') as f:
        graph = json.load(f)
    
    entities = graph['entities']
    relationships = graph.get('relationships', [])
    
    n_entities = len(entities)
    current_edges = len(relationships)
    max_edges = n_entities * (n_entities - 1)  # directed graph
    target_edges = int(max_edges * target_connectivity)
    
    print(f"   📊 Current: {current_edges} edges")
    print(f"   🎯 Target: {target_edges} edges")
    
    if current_edges >= target_edges:
        print(f"   ✅ Already well connected")
        return
    
    # Track existing edges to avoid duplicates
    existing_edges = set()
    for rel in relationships:
        existing_edges.add((rel['source'], rel['target']))
    
    # Add more edges
    relationship_types = [
        'depends_on', 'implements', 'calls', 'inherits_from', 'uses',
        'contains', 'references', 'extends', 'imports', 'configures'
    ]
    
    edges_to_add = target_edges - current_edges
    added_edges = 0
    
    # Try to add edges with some preference for logical connections
    for _ in range(edges_to_add * 10):  # More attempts than needed
        if added_edges >= edges_to_add:
            break
            
        source_entity = random.choice(entities)
        target_entity = random.choice(entities)
        
        # Don't create self loops
        if source_entity['name'] == target_entity['name']:
            continue
            
        # Don't create duplicate edges
        edge_key = (source_entity['name'], target_entity['name'])
        if edge_key in existing_edges:
            continue
            
        # Create new relationship
        new_rel = {
            'source': source_entity['name'],
            'target': target_entity['name'],
            'type': random.choice(relationship_types),
            'confidence': round(random.uniform(0.6, 0.9), 2)
        }
        
        relationships.append(new_rel)
        existing_edges.add(edge_key)
        added_edges += 1
    
    # Update graph
    graph['relationships'] = relationships
    
    print(f"   ✅ Added {added_edges} edges")
    print(f"   📈 Final connectivity: {len(relationships)} edges ({len(relationships)/max_edges*100:.1f}%)")
    
    # Write back to file
    with open(graph_file, 'w') as f:
        json.dump(graph, f, indent=2)

def main():
    graphs_dir = Path("tools/synthetic_graphs")
    
    if not graphs_dir.exists():
        print("❌ Synthetic graphs directory not found")
        sys.exit(1)
    
    graph_files = list(graphs_dir.glob("*.json"))
    
    if not graph_files:
        print("❌ No graph files found")
        sys.exit(1)
    
    print("🚀 Enhancing Graph Connectivity")
    print("==============================")
    
    for graph_file in graph_files:
        try:
            enhance_graph_connectivity(graph_file)
            print()
        except Exception as e:
            print(f"   ❌ Error processing {graph_file}: {e}")
    
    print("✅ Graph connectivity enhancement complete!")

if __name__ == "__main__":
    main()