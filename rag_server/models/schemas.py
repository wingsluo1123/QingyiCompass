"""
API 数据模型 — 与端侧接口保持一致
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class Message(BaseModel):
    """对话消息 — 与 AiService.ets 的 Message 接口对齐"""
    role: str = Field(..., description="角色: system / user / assistant")
    content: str = Field(..., description="消息内容")


class KnowledgeChunk(BaseModel):
    """知识块 — 与 KnowledgeService.ets 的 KnowledgeChunk 接口对齐"""
    id: int = Field(..., description="Chunk 唯一 ID")
    title: str = Field(..., description="来源标题，如'八宅明镜 (第3段)'")
    content: str = Field(..., description="文本内容")
    source: str = Field(default="内置经典", description="来源标签")
    category: str = Field(default="风水经典", description="分类标签")
    keywords: str = Field(default="", description="匹配到的关键词，空格分隔")


class RAGQueryRequest(BaseModel):
    """RAG 查询请求"""
    query: str = Field(..., min_length=1, description="用户查询文本")
    top_k: int = Field(default=5, ge=1, le=20, description="返回 Top-K 结果")
    chat_history: list[Message] = Field(
        default_factory=list,
        description="对话历史（可选，用于上下文增强）",
    )
    stream: bool = Field(default=True, description="是否使用 SSE 流式返回")


class RAGQueryResponse(BaseModel):
    """RAG 查询响应（非流式）"""
    chunks: list[KnowledgeChunk] = Field(default_factory=list)
    query: str = Field(..., description="原始查询")
    total_hits: int = Field(default=0, description="命中的 chunk 总数")


class KnowledgeUploadTextRequest(BaseModel):
    """Upload plain text content for indexing."""
    title: str = Field(default="", description="文档标题")
    file_name: str = Field(default="upload.txt", description="原始文件名")
    content: str = Field(..., min_length=1, description="文档文本内容")


class KnowledgeUploadResponse(BaseModel):
    """Upload and indexing result."""
    file_name: str = ""
    title: str = ""
    chunk_count: int = 0
    total_chunk_count: int = 0


class HealthResponse(BaseModel):
    """健康检查响应"""
    status: str = "ok"
    model: str = ""
    chunk_count: int = 0
    version: str = "1.0.0"
