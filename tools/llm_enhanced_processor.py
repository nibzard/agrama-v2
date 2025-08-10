#!/usr/bin/env python3
"""
LLM-Enhanced Graph Builder with Tool Calling

Uses Claude's tool calling capabilities to analyze conversation data
and build semantic knowledge graphs from AI coding sessions.
"""

import json
import os
import anthropic
from typing import List, Dict, Any, Optional, Set
from dataclasses import dataclass, asdict
from pathlib import Path
from conversation_processor import ConversationProcessor, ConversationSession

# Load environment variables
from dotenv import load_dotenv
load_dotenv()


@dataclass
class CodeEntity:
    """A code entity extracted by LLM analysis"""
    name: str
    type: str  # function, class, file, module, concept, etc.
    description: str
    file_path: Optional[str] = None
    line_number: Optional[int] = None
    language: Optional[str] = None


@dataclass
class Relationship:
    """A relationship between code entities"""
    source: str
    target: str
    type: str  # calls, imports, extends, modifies, etc.
    confidence: float
    context: str


@dataclass
class GraphData:
    """Complete graph data structure"""
    entities: List[CodeEntity]
    relationships: List[Relationship]
    metadata: Dict[str, Any]


class LLMEnhancedProcessor:
    """Uses Claude to analyze conversations and build knowledge graphs"""
    
    def __init__(self, api_key: Optional[str] = None):
        self.client = anthropic.Anthropic(
            api_key=api_key or os.environ.get("ANTHROPIC_API_KEY")
        )
        self.conversation_processor = ConversationProcessor()
        
        # Define tools for Claude to use
        self.tools = [
            {
                "type": "custom",
                "name": "extract_code_entities",
                "description": "Extract code entities (functions, classes, files, concepts) from conversation text",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "entities": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "name": {"type": "string"},
                                    "type": {"type": "string"},
                                    "description": {"type": "string"},
                                    "file_path": {"type": "string"},
                                    "language": {"type": "string"}
                                },
                                "required": ["name", "type", "description"]
                            }
                        }
                    },
                    "required": ["entities"]
                }
            },
            {
                "type": "custom", 
                "name": "identify_relationships",
                "description": "Identify relationships between code entities",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "relationships": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "source": {"type": "string"},
                                    "target": {"type": "string"},
                                    "type": {"type": "string"},
                                    "confidence": {"type": "number"},
                                    "context": {"type": "string"}
                                },
                                "required": ["source", "target", "type", "confidence"]
                            }
                        }
                    },
                    "required": ["relationships"]
                }
            },
            {
                "type": "custom",
                "name": "analyze_conversation_context", 
                "description": "Analyze conversation context to extract development patterns and decisions",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "patterns": {
                            "type": "array",
                            "items": {"type": "string"}
                        },
                        "decisions": {
                            "type": "array", 
                            "items": {
                                "type": "object",
                                "properties": {
                                    "decision": {"type": "string"},
                                    "rationale": {"type": "string"},
                                    "impact": {"type": "string"}
                                }
                            }
                        }
                    }
                }
            }
        ]
    
    def analyze_session_with_llm(self, session: ConversationSession) -> GraphData:
        """Use Claude to analyze a conversation session and extract graph data"""
        
        # Prepare conversation context
        conversation_text = self._prepare_conversation_context(session)
        
        prompt = f"""
        Analyze this AI coding conversation and extract structured information for building a knowledge graph.
        
        Project: {session.project_name}
        Messages: {session.total_messages}
        Tool Uses: {session.tool_uses}
        
        Conversation Context:
        {conversation_text}
        
        Please:
        1. Extract all code entities (functions, classes, files, modules, concepts)
        2. Identify relationships between these entities  
        3. Analyze conversation patterns and development decisions
        
        Focus on semantic understanding rather than just syntactic parsing.
        Look for implicit relationships, dependencies, and architectural decisions.
        """
        
        try:
            response = self.client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=4000,
                temperature=0.3,
                messages=[{"role": "user", "content": prompt}],
                tools=self.tools
            )
            
            # Parse tool call results
            entities = []
            relationships = []
            patterns = []
            decisions = []
            
            for content_block in response.content:
                if hasattr(content_block, 'type') and content_block.type == 'tool_use':
                    if content_block.name == 'extract_code_entities':
                        for entity_data in content_block.input.get('entities', []):
                            entities.append(CodeEntity(**entity_data))
                    
                    elif content_block.name == 'identify_relationships':
                        for rel_data in content_block.input.get('relationships', []):
                            relationships.append(Relationship(**rel_data))
                    
                    elif content_block.name == 'analyze_conversation_context':
                        patterns = content_block.input.get('patterns', [])
                        decisions = content_block.input.get('decisions', [])
            
            # Build graph data
            metadata = {
                'session_id': session.session_id,
                'project_name': session.project_name,
                'analysis_timestamp': str(__import__('datetime').datetime.now()),
                'patterns': patterns,
                'decisions': decisions,
                'total_entities': len(entities),
                'total_relationships': len(relationships)
            }
            
            return GraphData(
                entities=entities,
                relationships=relationships,
                metadata=metadata
            )
            
        except Exception as e:
            print(f"Error analyzing session {session.session_id}: {e}")
            return GraphData(entities=[], relationships=[], metadata={'error': str(e)})
    
    def _prepare_conversation_context(self, session: ConversationSession, max_chars: int = 8000) -> str:
        """Prepare conversation context for LLM analysis"""
        context_parts = []
        char_count = 0
        
        for message in session.messages:
            if char_count > max_chars:
                break
                
            msg_text = f"\n[{message.message_type.upper()}] {message.timestamp}\n"
            msg_text += f"Content: {message.content[:500]}...\n" if len(message.content) > 500 else f"Content: {message.content}\n"
            
            if message.tool_uses:
                msg_text += f"Tools: {[tool['name'] for tool in message.tool_uses]}\n"
            
            if message.cwd:
                msg_text += f"Directory: {message.cwd}\n"
                
            context_parts.append(msg_text)
            char_count += len(msg_text)
        
        return "\n".join(context_parts)
    
    def process_conversations_to_graphs(self, conversation_dir: Path, output_dir: Path) -> List[GraphData]:
        """Process all conversations and generate graph data"""
        
        # First, parse conversations with existing processor
        sessions = self.conversation_processor.process_directory(conversation_dir, recursive=True)
        
        output_dir.mkdir(exist_ok=True)
        graph_data_list = []
        
        for session in sessions:
            print(f"🧠 Analyzing session {session.session_id} with LLM...")
            
            # Use LLM to analyze session
            graph_data = self.analyze_session_with_llm(session)
            graph_data_list.append(graph_data)
            
            # Save individual graph
            output_file = output_dir / f"{session.project_name}_{session.session_id}_graph.json"
            with open(output_file, 'w') as f:
                # Convert dataclasses to dicts for JSON serialization
                serializable_data = {
                    'entities': [asdict(e) for e in graph_data.entities],
                    'relationships': [asdict(r) for r in graph_data.relationships],
                    'metadata': graph_data.metadata
                }
                json.dump(serializable_data, f, indent=2)
            
            print(f"  → {len(graph_data.entities)} entities, {len(graph_data.relationships)} relationships")
            print(f"  → Saved to {output_file}")
        
        return graph_data_list
    
    def merge_graphs(self, graph_data_list: List[GraphData], output_path: Path) -> GraphData:
        """Merge multiple graph datasets into a unified knowledge graph"""
        
        all_entities = []
        all_relationships = []
        merged_metadata = {
            'total_sessions': len(graph_data_list),
            'projects': set(),
            'merge_timestamp': str(__import__('datetime').datetime.now())
        }
        
        # Collect all entities and relationships
        entity_names = set()
        for graph in graph_data_list:
            for entity in graph.entities:
                if entity.name not in entity_names:
                    all_entities.append(entity)
                    entity_names.add(entity.name)
            
            all_relationships.extend(graph.relationships)
            merged_metadata['projects'].add(graph.metadata.get('project_name', 'unknown'))
        
        # Convert set to list for JSON serialization
        merged_metadata['projects'] = list(merged_metadata['projects'])
        merged_metadata['total_entities'] = len(all_entities)
        merged_metadata['total_relationships'] = len(all_relationships)
        
        merged_graph = GraphData(
            entities=all_entities,
            relationships=all_relationships,
            metadata=merged_metadata
        )
        
        # Save merged graph
        with open(output_path, 'w') as f:
            serializable_data = {
                'entities': [asdict(e) for e in merged_graph.entities],
                'relationships': [asdict(r) for r in merged_graph.relationships],
                'metadata': merged_graph.metadata
            }
            json.dump(serializable_data, f, indent=2)
        
        print(f"🔗 Merged graph saved to {output_path}")
        print(f"   Total entities: {len(all_entities)}")
        print(f"   Total relationships: {len(all_relationships)}")
        
        return merged_graph


def main():
    """Main function to test LLM-enhanced processing"""
    
    processor = LLMEnhancedProcessor()
    
    conversation_dir = Path("/home/dev/agrama-v2/tmp")
    output_dir = Path("/home/dev/agrama-v2/llm_graphs")
    
    if conversation_dir.exists():
        print("🚀 Starting LLM-Enhanced Graph Generation")
        print("=" * 50)
        
        # Process conversations to graphs
        graph_data_list = processor.process_conversations_to_graphs(conversation_dir, output_dir)
        
        # Merge into unified graph
        merged_output = output_dir / "unified_knowledge_graph.json"
        processor.merge_graphs(graph_data_list, merged_output)
        
        print("\n✅ LLM-Enhanced Processing Complete!")
        print(f"Individual graphs: {output_dir}/")
        print(f"Unified graph: {merged_output}")
        
    else:
        print(f"❌ Conversation directory not found: {conversation_dir}")


if __name__ == "__main__":
    main()