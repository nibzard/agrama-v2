#!/usr/bin/env python3
"""
Fixed LLM-Enhanced Graph Builder with Working Relationship Extraction

Key fixes:
1. Combined entities and relationships in a single tool call
2. Updated prompt to explicitly request both
3. Better error handling and debugging
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
    type: str
    description: str
    file_path: Optional[str] = None
    line_number: Optional[int] = None
    language: Optional[str] = None


@dataclass
class Relationship:
    """A relationship between code entities"""
    source: str
    target: str
    type: str
    confidence: float
    context: str


@dataclass
class GraphData:
    """Complete graph data structure"""
    entities: List[CodeEntity]
    relationships: List[Relationship]
    metadata: Dict[str, Any]


class FixedLLMProcessor:
    """Fixed version with working relationship extraction"""
    
    def __init__(self, api_key: Optional[str] = None):
        self.client = anthropic.Anthropic(
            api_key=api_key or os.environ.get("ANTHROPIC_API_KEY")
        )
        self.conversation_processor = ConversationProcessor()
        
        # FIXED: Single tool that extracts both entities AND relationships
        self.tools = [
            {
                "type": "custom",
                "name": "analyze_code_conversation",
                "description": "Analyze conversation and extract both code entities and their relationships",
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
                        },
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
                        },
                        "patterns": {
                            "type": "array",
                            "items": {"type": "string"}
                        }
                    },
                    "required": ["entities", "relationships"]
                }
            }
        ]
    
    def analyze_session_with_llm(self, session: ConversationSession) -> GraphData:
        """Use Claude to analyze a conversation session and extract graph data"""
        
        # Prepare conversation context (shorter for API limits)
        conversation_text = self._prepare_conversation_context(session, max_chars=6000)
        
        # FIXED: More explicit prompt requesting both entities AND relationships
        prompt = f"""
        Analyze this AI coding conversation and extract BOTH entities and relationships.

        Project: {session.project_name}
        Messages: {session.total_messages}
        Tool Uses: {session.tool_uses}

        IMPORTANT: You must extract:
        1. CODE ENTITIES: Functions, classes, files, tools, concepts, etc.
        2. RELATIONSHIPS: How these entities connect (imports, calls, modifies, extends, etc.)

        Look for:
        - File imports/dependencies
        - Function/method calls  
        - Component relationships
        - Tool usage patterns
        - Development workflows

        Conversation Context:
        {conversation_text}

        Use the analyze_code_conversation tool to provide BOTH entities and relationships.
        """
        
        try:
            response = self.client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=4000,
                temperature=0.2,
                messages=[{"role": "user", "content": prompt}],
                tools=self.tools
            )
            
            # FIXED: Debug the response and parse correctly
            entities = []
            relationships = []
            patterns = []
            
            print(f"    🔍 Response has {len(response.content)} content blocks")
            
            for i, content_block in enumerate(response.content):
                print(f"      Block {i}: {content_block.type if hasattr(content_block, 'type') else type(content_block)}")
                
                if hasattr(content_block, 'type') and content_block.type == 'tool_use':
                    print(f"        Tool: {content_block.name}")
                    
                    if content_block.name == 'analyze_code_conversation':
                        tool_input = content_block.input
                        
                        # Extract entities
                        raw_entities = tool_input.get('entities', [])
                        print(f"        Found {len(raw_entities)} entities")
                        for entity_data in raw_entities:
                            try:
                                entities.append(CodeEntity(**entity_data))
                            except Exception as e:
                                print(f"        ⚠️  Error parsing entity {entity_data.get('name', '?')}: {e}")
                        
                        # Extract relationships
                        raw_relationships = tool_input.get('relationships', [])
                        print(f"        Found {len(raw_relationships)} relationships")
                        for rel_data in raw_relationships:
                            try:
                                # Ensure context field exists
                                if 'context' not in rel_data:
                                    rel_data['context'] = "Extracted from conversation analysis"
                                relationships.append(Relationship(**rel_data))
                            except Exception as e:
                                print(f"        ⚠️  Error parsing relationship: {e}")
                        
                        # Extract patterns
                        patterns = tool_input.get('patterns', [])
                        print(f"        Found {len(patterns)} patterns")
            
            # Build metadata
            metadata = {
                'session_id': session.session_id,
                'project_name': session.project_name,
                'analysis_timestamp': str(__import__('datetime').datetime.now()),
                'patterns': patterns,
                'total_entities': len(entities),
                'total_relationships': len(relationships),
                'extraction_success': len(relationships) > 0
            }
            
            return GraphData(
                entities=entities,
                relationships=relationships,
                metadata=metadata
            )
            
        except Exception as e:
            print(f"    ❌ Error analyzing session {session.session_id}: {e}")
            return GraphData(
                entities=[], 
                relationships=[], 
                metadata={'error': str(e), 'session_id': session.session_id}
            )
    
    def _prepare_conversation_context(self, session: ConversationSession, max_chars: int = 6000) -> str:
        """Prepare conversation context for LLM analysis"""
        context_parts = []
        char_count = 0
        
        # Focus on messages with tool uses for richer context
        tool_messages = [msg for msg in session.messages if msg.tool_uses]
        regular_messages = [msg for msg in session.messages if not msg.tool_uses]
        
        # Prioritize tool messages, then fill with regular messages
        priority_messages = tool_messages[:10] + regular_messages[:20]
        
        for message in priority_messages:
            if char_count > max_chars:
                break
                
            msg_text = f"\n[{message.message_type.upper()}] {message.timestamp}\n"
            
            # Truncate long content but keep structure
            content = message.content
            if len(content) > 300:
                content = content[:300] + "..."
                
            msg_text += f"Content: {content}\n"
            
            if message.tool_uses:
                tools = [tool['name'] for tool in message.tool_uses]
                msg_text += f"Tools: {tools}\n"
            
            if message.cwd:
                msg_text += f"Directory: {message.cwd}\n"
                
            context_parts.append(msg_text)
            char_count += len(msg_text)
        
        return "\n".join(context_parts)
    
    def process_single_session(self, session: ConversationSession, output_dir: Path) -> GraphData:
        """Process a single session for testing"""
        print(f"🧠 Analyzing session {session.session_id[:8]}... with fixed processor")
        
        # Use LLM to analyze session
        graph_data = self.analyze_session_with_llm(session)
        
        # Save graph
        output_file = output_dir / f"fixed_{session.project_name}_{session.session_id}_graph.json"
        with open(output_file, 'w') as f:
            serializable_data = {
                'entities': [asdict(e) for e in graph_data.entities],
                'relationships': [asdict(r) for r in graph_data.relationships],
                'metadata': graph_data.metadata
            }
            json.dump(serializable_data, f, indent=2)
        
        print(f"  → {len(graph_data.entities)} entities, {len(graph_data.relationships)} relationships")
        print(f"  → Saved to {output_file}")
        
        return graph_data


def test_relationship_extraction():
    """Test the fixed relationship extraction"""
    processor = FixedLLMProcessor()
    
    # Load a single session for testing
    conversation_dir = Path("/home/dev/agrama-v2/tmp")
    sessions = processor.conversation_processor.process_directory(conversation_dir, recursive=True)
    
    if not sessions:
        print("❌ No sessions found")
        return
    
    # Test with a session that has tool uses (more likely to have relationships)
    test_session = max(sessions, key=lambda s: s.tool_uses)
    
    output_dir = Path("/home/dev/agrama-v2/fixed_graphs")
    output_dir.mkdir(exist_ok=True)
    
    print(f"🧪 TESTING FIXED RELATIONSHIP EXTRACTION")
    print("=" * 50)
    print(f"Test session: {test_session.session_id[:8]}...")
    print(f"Project: {test_session.project_name}")
    print(f"Messages: {test_session.total_messages}")
    print(f"Tool uses: {test_session.tool_uses}")
    print()
    
    # Process the session
    graph_data = processor.process_single_session(test_session, output_dir)
    
    # Show results
    print(f"\n🎯 EXTRACTION RESULTS:")
    print(f"  Entities: {len(graph_data.entities)}")
    print(f"  Relationships: {len(graph_data.relationships)}")
    print(f"  Success: {'✅' if len(graph_data.relationships) > 0 else '❌'}")
    
    if graph_data.relationships:
        print(f"\n📈 SAMPLE RELATIONSHIPS:")
        for rel in graph_data.relationships[:5]:
            print(f"  {rel.source} --[{rel.type}]--> {rel.target} (confidence: {rel.confidence})")
    
    return graph_data


if __name__ == "__main__":
    test_relationship_extraction()