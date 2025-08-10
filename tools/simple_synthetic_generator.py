#!/usr/bin/env python3
"""
Simple Synthetic Graph Generator

Creates larger synthetic graphs by expanding real patterns directly,
then uses Claude to add authentic relationships.
"""

import json
import os
import anthropic
import random
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()


def create_synthetic_graph_direct(target_size: int, density_level: str) -> dict:
    """Create synthetic graph using direct pattern expansion + Claude for relationships"""
    
    print(f"🔧 Creating synthetic {density_level} graph with {target_size} entities...")
    
    # Entity type patterns from real graphs
    entity_templates = {
        'project': ['nexus-platform', 'quantum-db', 'react-dashboard', 'ml-pipeline', 'api-service'],
        'component': ['user-service', 'auth-module', 'data-processor', 'web-client', 'cache-layer', 'message-queue'],
        'file': ['config.yml', 'README.md', 'package.json', 'Dockerfile', 'schema.sql', 'main.py', 'index.tsx'],
        'tool': ['CodeAssistant', 'TestRunner', 'DeployBot', 'BuildTool', 'Debugger', 'Profiler'],
        'concept': ['microservices', 'event-sourcing', 'CQRS', 'containerization', 'CI/CD', 'observability'],
        'service': ['database', 'load-balancer', 'monitoring', 'logging', 'metrics', 'tracing'],
        'agent': ['frontend-engineer', 'backend-engineer', 'devops-specialist', 'qa-engineer', 'data-scientist']
    }
    
    # Languages and tech stacks
    languages = ['Python', 'TypeScript', 'Go', 'Rust', 'Java', 'C++', 'JavaScript', 'Scala', 'Kotlin']
    frameworks = ['React', 'Django', 'FastAPI', 'Express', 'Spring', 'Gin', 'Axum', 'Next.js']
    
    entities = []
    
    # Generate diverse entities
    for i in range(target_size):
        entity_type = random.choices(
            list(entity_templates.keys()),
            weights=[3, 5, 4, 3, 2, 3, 2],  # Weight based on real distributions
            k=1
        )[0]
        
        base_name = random.choice(entity_templates[entity_type])
        name = f"{base_name}-{i % 20}" if i >= 20 else base_name
        
        language = random.choice(languages) if entity_type in ['component', 'file', 'tool'] else None
        
        file_path = None
        if entity_type in ['file', 'component']:
            file_path = f"/src/{entity_type}s/{name.replace('-', '_')}"
        
        entities.append({
            "name": name,
            "type": entity_type,
            "description": f"Generated {entity_type} for synthetic benchmarking ({random.choice(frameworks)} based)",
            "file_path": file_path,
            "language": language
        })
    
    print(f"   Generated {len(entities)} entities")
    
    # Generate relationships based on density
    relationships = []
    target_relationships = {
        'sparse': target_size * 2,
        'medium': target_size * 6,
        'dense': target_size * 15
    }[density_level]
    
    relationship_types = [
        'contains', 'modifies', 'implements', 'uses', 'depends_on', 
        'calls', 'extends', 'configures', 'deploys', 'monitors',
        'analyzes', 'references', 'includes', 'creates'
    ]
    
    for _ in range(target_relationships):
        source = random.choice(entities)
        target = random.choice(entities)
        
        if source['name'] != target['name']:  # No self-relationships
            relationships.append({
                "source": source['name'],
                "target": target['name'], 
                "type": random.choice(relationship_types),
                "confidence": round(random.uniform(0.7, 1.0), 2),
                "context": f"Synthetic relationship between {source['type']} and {target['type']}"
            })
    
    print(f"   Generated {len(relationships)} relationships")
    
    return {
        'entities': entities,
        'relationships': relationships,
        'metadata': {
            'generation_method': 'pattern_expansion',
            'target_size': target_size,
            'density_level': density_level,
            'actual_entities': len(entities),
            'actual_relationships': len(relationships),
            'actual_avg_degree': (len(relationships) * 2) / len(entities),
            'synthetic': True
        }
    }


def enhance_with_claude_relationships(graph: dict, api_key: str) -> dict:
    """Use Claude to make relationships more realistic"""
    
    print("🤖 Enhancing relationships with Claude...")
    
    client = anthropic.Anthropic(api_key=api_key)
    
    # Sample some entities for Claude to analyze
    sample_entities = graph['entities'][:20]  # First 20 entities
    entity_list = "\n".join([f"- {e['name']} ({e['type']}): {e['description']}" for e in sample_entities])
    
    prompt = f"""
    Given these software entities from a large-scale system:
    
    {entity_list}
    
    Generate 30 realistic relationships between these entities that would occur in a real software project.
    Focus on authentic patterns like:
    - Components depend on services
    - Files are contained in projects  
    - Tools modify files
    - Agents analyze components
    
    Return as JSON array with format:
    [
      {{"source": "entity1", "target": "entity2", "type": "depends_on", "confidence": 0.9, "context": "explanation"}},
      ...
    ]
    """
    
    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=3000,
            temperature=0.3,
            messages=[{"role": "user", "content": prompt}]
        )
        
        # Extract JSON from response
        response_text = response.content[0].text
        json_start = response_text.find('[')
        json_end = response_text.rfind(']') + 1
        
        if json_start >= 0 and json_end > json_start:
            enhanced_relationships = json.loads(response_text[json_start:json_end])
            
            # Replace first N relationships with Claude's enhanced ones
            graph['relationships'][:len(enhanced_relationships)] = enhanced_relationships
            print(f"   Enhanced {len(enhanced_relationships)} relationships with Claude")
        
    except Exception as e:
        print(f"   Warning: Could not enhance with Claude: {e}")
    
    return graph


def main():
    """Generate multiple synthetic graphs"""
    print("🚀 Simple Synthetic Graph Generation")
    print("=" * 40)
    
    output_dir = Path("synthetic_graphs")
    output_dir.mkdir(exist_ok=True)
    
    # Generate graphs at different scales
    configs = [
        {'size': 50, 'density': 'sparse', 'name': 'test_50_sparse'},
        {'size': 100, 'density': 'sparse', 'name': 'benchmark_100_sparse'},
        {'size': 100, 'density': 'medium', 'name': 'benchmark_100_medium'},
        {'size': 200, 'density': 'sparse', 'name': 'benchmark_200_sparse'},
        {'size': 200, 'density': 'medium', 'name': 'benchmark_200_medium'},
        {'size': 500, 'density': 'sparse', 'name': 'benchmark_500_sparse'},
        {'size': 500, 'density': 'medium', 'name': 'benchmark_500_medium'},
        {'size': 1000, 'density': 'sparse', 'name': 'benchmark_1000_sparse'},
        {'size': 1000, 'density': 'medium', 'name': 'benchmark_1000_medium'},
    ]
    
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    
    for config in configs:
        print(f"\n📊 Generating {config['name']}...")
        
        # Create base synthetic graph
        graph = create_synthetic_graph_direct(config['size'], config['density'])
        
        # Enhance with Claude (if API key available)
        if api_key and len(graph['entities']) <= 200:  # Only enhance smaller graphs to save API costs
            print(f"   🔧 Enhancing with Claude API...")
            graph = enhance_with_claude_relationships(graph, api_key)
        elif len(graph['entities']) > 200:
            print(f"   ⚡ Skipping Claude enhancement for large graph (cost optimization)")
        
        # Save graph
        output_file = output_dir / f"{config['name']}.json"
        with open(output_file, 'w') as f:
            json.dump(graph, f, indent=2)
        
        metadata = graph['metadata']
        print(f"   ✅ Saved {metadata['actual_entities']} entities, {metadata['actual_relationships']} relationships")
        print(f"   📊 Average degree: {metadata['actual_avg_degree']:.1f}")
        print(f"   💾 File: {output_file}")
    
    print(f"\n🎯 Generated {len(configs)} synthetic graphs for FRE benchmarking!")
    print("   Ready to test algorithmic performance at scale")


if __name__ == "__main__":
    main()