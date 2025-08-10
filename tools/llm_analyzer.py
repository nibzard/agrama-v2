#!/usr/bin/env python3
"""
LLM-Enhanced Graph Analyzer

Uses Claude API to analyze conversation content and extract semantic 
entities and relationships for dense graph construction.

Features:
- Semantic entity extraction (files, functions, concepts, decisions)
- Relationship inference (dependencies, similarities, temporal evolution)
- Caching to avoid re-analysis
- Batch processing for efficiency
"""

import json
import os
import re
import time
import hashlib
from dataclasses import dataclass, field, asdict
from typing import List, Dict, Any, Optional, Set, Tuple
from pathlib import Path
import anthropic
from tqdm import tqdm


@dataclass 
class Entity:
    """Extracted entity from conversation analysis"""
    id: str
    name: str
    entity_type: str
    confidence: float
    content: Optional[str] = None
    context: Optional[str] = None
    attributes: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Relationship:
    """Relationship between two entities"""
    from_entity: str
    to_entity: str
    relationship_type: str
    confidence: float
    evidence: str = ""
    attributes: Dict[str, Any] = field(default_factory=dict)


@dataclass
class AnalysisResult:
    """Result of LLM analysis on a message or conversation"""
    session_id: str
    message_uuid: Optional[str] = None
    entities: List[Entity] = field(default_factory=list)
    relationships: List[Relationship] = field(default_factory=list)
    concepts: List[str] = field(default_factory=list)
    analysis_timestamp: str = ""
    model_version: str = ""


class LLMAnalyzer:
    """Claude-powered conversation analyzer"""
    
    def __init__(self, api_key: Optional[str] = None, cache_dir: str = "./cache"):
        self.client = anthropic.Anthropic(
            api_key=api_key or os.environ.get("ANTHROPIC_API_KEY")
        )
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(exist_ok=True)
        self.model = "claude-sonnet-4-20250514"
        self.rate_limit_delay = 1.0  # Seconds between API calls
        
        # Analysis statistics
        self.total_api_calls = 0
        self.cache_hits = 0
        self.analysis_errors = 0
    
    def _create_cache_key(self, content: str) -> str:
        """Create cache key for content"""
        return hashlib.sha256(content.encode()).hexdigest()[:16]
    
    def _load_from_cache(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Load analysis result from cache"""
        cache_file = self.cache_dir / f"{cache_key}.json"
        if cache_file.exists():
            try:
                with open(cache_file, 'r') as f:
                    self.cache_hits += 1
                    return json.load(f)
            except Exception:
                pass
        return None
    
    def _save_to_cache(self, cache_key: str, result: Dict[str, Any]):
        """Save analysis result to cache"""
        cache_file = self.cache_dir / f"{cache_key}.json"
        try:
            with open(cache_file, 'w') as f:
                json.dump(result, f, indent=2)
        except Exception as e:
            print(f"Warning: Failed to save cache: {e}")
    
    def create_analysis_prompt(self, message_content: str, context: str = "") -> str:
        """Create prompt for entity and relationship extraction"""
        return f"""
You are analyzing a message from an AI-assisted software development conversation. Extract entities and relationships to build a knowledge graph.

CONTEXT: {context}

MESSAGE CONTENT:
{message_content}

Extract the following as structured JSON:

1. ENTITIES (with confidence 0.0-1.0):
   - FILES: source files, configs (e.g. "src/main.zig", "build.zig")
   - FUNCTIONS: function/method names (e.g. "buildGraph", "parseJSON")  
   - CONCEPTS: algorithms, patterns, architectures (e.g. "FRE algorithm", "HNSW index")
   - TOOLS: commands, operations (e.g. "zig build", "git commit")
   - DECISIONS: architectural choices (e.g. "use Zig for performance", "implement CRDT")
   - ERRORS: problems encountered (e.g. "compilation error", "memory leak")
   - SOLUTIONS: fixes applied (e.g. "add error handling", "fix memory allocation")

2. RELATIONSHIPS (with confidence 0.0-1.0):
   - DEPENDS_ON: A requires B functionality
   - IMPLEMENTS: A realizes concept/decision B
   - CALLS: function A invokes function B
   - MODIFIES: tool/action A changes entity B
   - CREATES: A brings B into existence
   - TESTS: A validates B functionality
   - FIXES: A resolves problem B
   - SIMILAR_TO: A serves similar purpose as B
   - EVOLVES_FROM: A is modified version of B
   - CONTAINS: A includes B as component

3. KEY_CONCEPTS: Main technical concepts discussed

Format as JSON:
{{
  "entities": [
    {{"name": "entity_name", "type": "FILE|FUNCTION|CONCEPT|TOOL|DECISION|ERROR|SOLUTION", "confidence": 0.8, "context": "brief context"}}
  ],
  "relationships": [
    {{"from": "entity1", "to": "entity2", "type": "DEPENDS_ON|IMPLEMENTS|...", "confidence": 0.9, "evidence": "why this relationship exists"}}
  ],
  "concepts": ["concept1", "concept2"]
}}

Focus on technical entities and meaningful relationships. Ignore conversational fluff.
"""
    
    def analyze_message(self, message_content: str, context: str = "", session_id: str = "", 
                       message_uuid: str = "") -> AnalysisResult:
        """Analyze a single message with Claude"""
        
        # Skip empty or very short messages
        if not message_content or len(message_content.strip()) < 20:
            return AnalysisResult(session_id=session_id, message_uuid=message_uuid)
        
        # Check cache first
        cache_key = self._create_cache_key(message_content + context)
        cached_result = self._load_from_cache(cache_key)
        
        if cached_result:
            return AnalysisResult(
                session_id=session_id,
                message_uuid=message_uuid,
                entities=[Entity(**e) for e in cached_result.get('entities', [])],
                relationships=[Relationship(**r) for r in cached_result.get('relationships', [])],
                concepts=cached_result.get('concepts', []),
                analysis_timestamp=cached_result.get('analysis_timestamp', ''),
                model_version=cached_result.get('model_version', '')
            )
        
        try:
            # Rate limiting
            time.sleep(self.rate_limit_delay)
            
            prompt = self.create_analysis_prompt(message_content, context)
            
            response = self.client.messages.create(
                model=self.model,
                max_tokens=8192,
                temperature=0.1,  # Lower temperature for consistent extraction
                messages=[{"role": "user", "content": prompt}]
            )
            
            self.total_api_calls += 1
            
            # Parse JSON response
            content = response.content[0].text if response.content else ""
            
            # Extract JSON from response (may be wrapped in markdown)
            json_match = re.search(r'```json\s*(.*?)\s*```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                # Look for raw JSON
                json_match = re.search(r'\{.*\}', content, re.DOTALL)
                if json_match:
                    json_str = json_match.group(0)
                else:
                    print(f"Warning: No JSON found in response for message {message_uuid}")
                    return AnalysisResult(session_id=session_id, message_uuid=message_uuid)
            
            try:
                parsed = json.loads(json_str)
            except json.JSONDecodeError as e:
                print(f"Warning: JSON parse error for message {message_uuid}: {e}")
                return AnalysisResult(session_id=session_id, message_uuid=message_uuid)
            
            # Create entities with IDs
            entities = []
            for i, entity_data in enumerate(parsed.get('entities', [])):
                entity_id = f"{session_id}_{message_uuid}_{i}" if message_uuid else f"{session_id}_{i}"
                entities.append(Entity(
                    id=entity_id,
                    name=entity_data.get('name', ''),
                    entity_type=entity_data.get('type', ''),
                    confidence=entity_data.get('confidence', 0.0),
                    content=entity_data.get('context', ''),
                    context=context[:200] if context else None
                ))
            
            # Create relationships
            relationships = []
            for rel_data in parsed.get('relationships', []):
                relationships.append(Relationship(
                    from_entity=rel_data.get('from', ''),
                    to_entity=rel_data.get('to', ''),
                    relationship_type=rel_data.get('type', ''),
                    confidence=rel_data.get('confidence', 0.0),
                    evidence=rel_data.get('evidence', '')
                ))
            
            result = AnalysisResult(
                session_id=session_id,
                message_uuid=message_uuid,
                entities=entities,
                relationships=relationships,
                concepts=parsed.get('concepts', []),
                analysis_timestamp=str(time.time()),
                model_version=self.model
            )
            
            # Cache the result
            cache_data = {
                'entities': [asdict(e) for e in entities],
                'relationships': [asdict(r) for r in relationships],
                'concepts': result.concepts,
                'analysis_timestamp': result.analysis_timestamp,
                'model_version': result.model_version
            }
            self._save_to_cache(cache_key, cache_data)
            
            return result
            
        except Exception as e:
            self.analysis_errors += 1
            print(f"Error analyzing message {message_uuid}: {e}")
            return AnalysisResult(session_id=session_id, message_uuid=message_uuid)
    
    def analyze_conversation_batch(self, sessions: List[Any], max_messages: int = 50) -> List[AnalysisResult]:
        """Analyze multiple conversation sessions in batch"""
        all_results = []
        
        total_messages = sum(min(len(s.messages), max_messages) for s in sessions)
        
        with tqdm(total=total_messages, desc="Analyzing messages") as pbar:
            for session in sessions:
                session_results = []
                
                # Build session context
                context = f"Project: {session.project_name}, Session: {session.session_id}"
                
                # Analyze messages (limit to avoid excessive API calls)
                messages_to_analyze = session.messages[:max_messages]
                
                for message in messages_to_analyze:
                    if message.message_type in ['user', 'assistant'] and message.content:
                        result = self.analyze_message(
                            message_content=message.content,
                            context=context,
                            session_id=session.session_id,
                            message_uuid=message.uuid
                        )
                        session_results.append(result)
                    
                    pbar.update(1)
                
                all_results.extend(session_results)
        
        return all_results
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get analyzer statistics"""
        return {
            'total_api_calls': self.total_api_calls,
            'cache_hits': self.cache_hits,
            'analysis_errors': self.analysis_errors,
            'cache_hit_rate': self.cache_hits / max(self.total_api_calls + self.cache_hits, 1),
            'error_rate': self.analysis_errors / max(self.total_api_calls, 1)
        }
    
    def export_results(self, results: List[AnalysisResult], output_path: Path):
        """Export analysis results to JSON"""
        export_data = []
        
        for result in results:
            export_data.append({
                'session_id': result.session_id,
                'message_uuid': result.message_uuid,
                'entities': [asdict(e) for e in result.entities],
                'relationships': [asdict(r) for r in result.relationships],
                'concepts': result.concepts,
                'analysis_timestamp': result.analysis_timestamp,
                'model_version': result.model_version
            })
        
        with open(output_path, 'w') as f:
            json.dump(export_data, f, indent=2)


def test_single_message():
    """Test the analyzer on a single message"""
    
    # Test message content
    test_content = """
Let me implement the FRE algorithm in src/fre_true.zig. This will use the 
Bounded Multi-Source Shortest Path approach with O(m log^(2/3) n) complexity.

I'll create the TrueFrontierReductionEngine struct and implement the recursive 
BMSSP function as described in the research paper.
"""
    
    analyzer = LLMAnalyzer()
    result = analyzer.analyze_message(
        message_content=test_content,
        context="Implementing graph algorithms for Agrama project",
        session_id="test_session",
        message_uuid="test_message"
    )
    
    print("🔍 Analysis Results:")
    print(f"Entities found: {len(result.entities)}")
    for entity in result.entities:
        print(f"  - {entity.name} ({entity.entity_type}) confidence: {entity.confidence}")
    
    print(f"\nRelationships found: {len(result.relationships)}")  
    for rel in result.relationships:
        print(f"  - {rel.from_entity} --{rel.relationship_type}--> {rel.to_entity} ({rel.confidence})")
    
    print(f"\nConcepts: {result.concepts}")
    
    # Print statistics
    stats = analyzer.get_statistics()
    print(f"\nStatistics: {stats}")


if __name__ == "__main__":
    # Check if API key is available
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY environment variable not set")
        print("Please set it with: export ANTHROPIC_API_KEY='your-key-here'")
        exit(1)
    
    test_single_message()