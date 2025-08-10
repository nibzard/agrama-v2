#!/usr/bin/env python3
"""
JSONL Conversation Processor for LLM-Enhanced Graph Builder

Parses Claude Code conversation files and extracts structured data
for semantic analysis and graph construction.

Input: JSONL files from Claude Code sessions
Output: Structured conversation data for LLM analysis
"""

import json
import os
import re
from dataclasses import dataclass, field
from typing import List, Dict, Any, Optional, Set
from pathlib import Path


@dataclass
class ConversationMessage:
    """Single message in a conversation"""
    uuid: str
    timestamp: str
    message_type: str  # 'user' or 'assistant'
    content: str
    tool_uses: List[Dict[str, Any]] = field(default_factory=list)
    tool_results: List[Dict[str, Any]] = field(default_factory=list)
    session_id: str = ""
    parent_uuid: Optional[str] = None
    cwd: str = ""
    git_branch: str = ""


@dataclass
class ConversationSession:
    """Complete conversation session"""
    session_id: str
    project_name: str
    messages: List[ConversationMessage]
    file_path: str
    total_messages: int = 0
    user_messages: int = 0
    assistant_messages: int = 0
    tool_uses: int = 0


class ConversationProcessor:
    """Processes JSONL conversation files from Claude Code"""
    
    def __init__(self):
        self.sessions: List[ConversationSession] = []
        self.file_patterns = set()
        self.tool_patterns = set()
        
    def parse_jsonl_file(self, file_path: Path) -> Optional[ConversationSession]:
        """Parse a single JSONL conversation file"""
        try:
            messages = []
            session_id = None
            project_name = self._extract_project_name(file_path)
            
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f):
                    line = line.strip()
                    if not line:
                        continue
                        
                    try:
                        data = json.loads(line)
                        message = self._parse_message(data)
                        if message:
                            messages.append(message)
                            if not session_id:
                                session_id = message.session_id
                                
                    except json.JSONDecodeError as e:
                        print(f"Warning: JSON decode error in {file_path}:{line_num}: {e}")
                        continue
            
            if not messages:
                return None
                
            session = ConversationSession(
                session_id=session_id or str(file_path.stem),
                project_name=project_name,
                messages=messages,
                file_path=str(file_path),
                total_messages=len(messages)
            )
            
            # Calculate statistics
            session.user_messages = sum(1 for m in messages if m.message_type == 'user')
            session.assistant_messages = sum(1 for m in messages if m.message_type == 'assistant')
            session.tool_uses = sum(len(m.tool_uses) for m in messages)
            
            return session
            
        except Exception as e:
            print(f"Error processing {file_path}: {e}")
            return None
    
    def _parse_message(self, data: Dict[str, Any]) -> Optional[ConversationMessage]:
        """Parse individual message from JSONL data"""
        try:
            # Skip system messages and metadata
            if data.get('type') not in ['user', 'assistant']:
                return None
                
            # Extract basic message info
            message_type = data.get('type', '')
            uuid = data.get('uuid', '')
            timestamp = data.get('timestamp', '')
            session_id = data.get('sessionId', '')
            parent_uuid = data.get('parentUuid')
            cwd = data.get('cwd', '')
            git_branch = data.get('gitBranch', '')
            
            # Extract message content
            content = ""
            tool_uses = []
            tool_results = []
            
            if 'message' in data:
                msg = data['message']
                
                if 'content' in msg:
                    if isinstance(msg['content'], str):
                        content = msg['content']
                    elif isinstance(msg['content'], list):
                        # Handle complex content with tool uses
                        for item in msg['content']:
                            if isinstance(item, dict):
                                if item.get('type') == 'text':
                                    content += item.get('text', '')
                                elif item.get('type') == 'tool_use':
                                    tool_uses.append({
                                        'name': item.get('name', ''),
                                        'input': item.get('input', {}),
                                        'id': item.get('id', '')
                                    })
                                elif item.get('type') == 'tool_result':
                                    tool_results.append({
                                        'content': item.get('content', ''),
                                        'tool_use_id': item.get('tool_use_id', ''),
                                        'is_error': item.get('is_error', False)
                                    })
            
            # Handle tool results in separate messages
            if 'toolUseResult' in data:
                tool_results.append({
                    'content': data['toolUseResult'].get('stdout', '') + data['toolUseResult'].get('stderr', ''),
                    'is_error': data['toolUseResult'].get('stderr', '') != '',
                    'interrupted': data['toolUseResult'].get('interrupted', False)
                })
            
            return ConversationMessage(
                uuid=uuid,
                timestamp=timestamp,
                message_type=message_type,
                content=content.strip(),
                tool_uses=tool_uses,
                tool_results=tool_results,
                session_id=session_id,
                parent_uuid=parent_uuid,
                cwd=cwd,
                git_branch=git_branch
            )
            
        except Exception as e:
            print(f"Error parsing message: {e}")
            return None
    
    def _extract_project_name(self, file_path: Path) -> str:
        """Extract project name from file path"""
        parts = file_path.parts
        if 'agrama' in parts:
            return 'agrama'
        elif 'agentprobe' in parts:
            return 'agentprobe'
        else:
            return 'unknown'
    
    def process_directory(self, directory: Path, recursive: bool = True) -> List[ConversationSession]:
        """Process all JSONL files in a directory"""
        sessions = []
        
        if recursive:
            pattern = "**/*.jsonl"
        else:
            pattern = "*.jsonl"
            
        for jsonl_file in directory.glob(pattern):
            print(f"Processing {jsonl_file}...")
            session = self.parse_jsonl_file(jsonl_file)
            if session:
                sessions.append(session)
                print(f"  → {session.total_messages} messages, {session.tool_uses} tool uses")
            
        self.sessions.extend(sessions)
        return sessions
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get processing statistics"""
        if not self.sessions:
            return {}
            
        stats = {
            'total_sessions': len(self.sessions),
            'total_messages': sum(s.total_messages for s in self.sessions),
            'total_user_messages': sum(s.user_messages for s in self.sessions),
            'total_assistant_messages': sum(s.assistant_messages for s in self.sessions),
            'total_tool_uses': sum(s.tool_uses for s in self.sessions),
            'projects': {},
            'tools_used': set(),
            'file_patterns': set()
        }
        
        # Per-project stats
        for session in self.sessions:
            if session.project_name not in stats['projects']:
                stats['projects'][session.project_name] = {
                    'sessions': 0,
                    'messages': 0,
                    'tool_uses': 0
                }
            
            stats['projects'][session.project_name]['sessions'] += 1
            stats['projects'][session.project_name]['messages'] += session.total_messages
            stats['projects'][session.project_name]['tool_uses'] += session.tool_uses
            
            # Extract tool patterns
            for message in session.messages:
                for tool_use in message.tool_uses:
                    stats['tools_used'].add(tool_use['name'])
                    
                # Extract file patterns from content
                file_matches = re.findall(r'\b\w+\.\w+\b', message.content)
                stats['file_patterns'].update(file_matches[:10])  # Limit to avoid noise
        
        # Convert sets to sorted lists for JSON serialization
        stats['tools_used'] = sorted(list(stats['tools_used']))
        stats['file_patterns'] = sorted(list(stats['file_patterns']))
        
        return stats
    
    def export_session_summaries(self, output_path: Path):
        """Export session summaries for LLM analysis"""
        summaries = []
        
        for session in self.sessions:
            summary = {
                'session_id': session.session_id,
                'project_name': session.project_name,
                'total_messages': session.total_messages,
                'user_messages': session.user_messages,
                'assistant_messages': session.assistant_messages,
                'tool_uses': session.tool_uses,
                'file_path': session.file_path,
                'message_previews': []
            }
            
            # Add message previews for LLM context
            for msg in session.messages[:10]:  # First 10 messages
                preview = {
                    'type': msg.message_type,
                    'timestamp': msg.timestamp,
                    'content_preview': msg.content[:200] + ('...' if len(msg.content) > 200 else ''),
                    'tool_uses': [tool['name'] for tool in msg.tool_uses],
                    'cwd': msg.cwd
                }
                summary['message_previews'].append(preview)
                
            summaries.append(summary)
        
        with open(output_path, 'w') as f:
            json.dump(summaries, f, indent=2)


def main():
    """Test the conversation processor"""
    processor = ConversationProcessor()
    
    # Process conversations
    base_dir = Path("/home/dev/agrama-v2/tmp")
    if base_dir.exists():
        sessions = processor.process_directory(base_dir, recursive=True)
        
        print(f"\n🔍 Processing Results:")
        print(f"{'='*50}")
        
        stats = processor.get_statistics()
        print(f"Total Sessions: {stats['total_sessions']}")
        print(f"Total Messages: {stats['total_messages']}")
        print(f"Tool Uses: {stats['total_tool_uses']}")
        print(f"Projects: {list(stats['projects'].keys())}")
        print(f"Tools Used: {stats['tools_used'][:10]}")
        
        # Export summaries
        output_path = Path("/home/dev/agrama-v2/tools/session_summaries.json")
        processor.export_session_summaries(output_path)
        print(f"\nExported summaries to: {output_path}")
        
    else:
        print(f"Directory not found: {base_dir}")


if __name__ == "__main__":
    main()