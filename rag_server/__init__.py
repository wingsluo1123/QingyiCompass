"""
Compass RAG Server

为 HarmonyOS 清易罗盘 App 提供风水经典知识检索（RAG）服务。

Usage:
    启动服务:
        python -m rag_server.main

    或:
        cd compass && uvicorn rag_server.main:app --host 0.0.0.0 --port 8765
"""

__version__ = "1.0.0"
