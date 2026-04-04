# Memory Reader - Unified Version
# 统一记忆读取脚本

import sqlite3
import os
import glob
from datetime import datetime

MEMORY_DIR = os.path.expanduser("~/.openclaw/workspace/memory")
SQLITE_PATH = os.path.expanduser("~/.openclaw/memory/main.sqlite")

def read_markdown_memories():
    """读取所有 Markdown 记忆文件"""
    memories = []
    md_files = glob.glob(f"{MEMORY_DIR}/*.md")
    
    for filepath in sorted(md_files, reverse=True):
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                memories.append({
                    'source': 'markdown',
                    'file': os.path.basename(filepath),
                    'content': content
                })
        except Exception as e:
            print(f"Error reading {filepath}: {e}")
    
    return memories

def read_sqlite_memories(limit=50):
    """读取 SQLite 中的飞书/telegram 记忆"""
    memories = []
    
    if not os.path.exists(SQLITE_PATH):
        return memories
    
    try:
        conn = sqlite3.connect(SQLITE_PATH)
        cursor = conn.cursor()
        
        # 查询 chunks 表（文本块）
        cursor.execute("""
            SELECT text, path FROM chunks 
            ORDER BY rowid DESC 
            LIMIT ?
        """, (limit,))
        
        for row in cursor.fetchall():
            memories.append({
                'source': 'sqlite',
                'file': row[1] if row[1] else 'main.sqlite',
                'content': row[0]
            })
        
        conn.close()
    except Exception as e:
        print(f"Error reading SQLite: {e}")
    
    return memories

def get_unified_memory():
    """获取统一记忆（Markdown + SQLite）"""
    md_memories = read_markdown_memories()
    sqlite_memories = read_sqlite_memories()
    
    return {
        'markdown': md_memories,
        'sqlite': sqlite_memories,
        'total_files': len(md_memories),
        'total_sqlite_records': len(sqlite_memories)
    }

if __name__ == "__main__":
    memory = get_unified_memory()
    print(f"Markdown 文件: {memory['total_files']}")
    print(f"SQLite 记录: {memory['total_sqlite_records']}")
    print(f"\n最新记忆来源:")
    if memory['sqlite']:
        print(f"  - SQLite: {memory['sqlite'][0]['file']}")
    if memory['markdown']:
        print(f"  - Markdown: {memory['markdown'][0]['file']}")
