"""
混合检索引擎

结合 BM25（关键词稀疏检索）和向量相似度（语义稠密检索），
使用 RRF (Reciprocal Rank Fusion) 融合排序，
与端侧 RAGService.ets 的接口约定保持一致。
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from math import log

from rank_bm25 import BM25Okapi

from .. import config
from ..knowledge import Chunk, VectorStore, get_vector_store
from .embedder import Embedder, get_embedder

logger = logging.getLogger(__name__)


@dataclass
class ScoredChunk:
    """带分数的 chunk。"""
    chunk: Chunk
    score: float


class HybridSearcher:
    """
    混合检索器：BM25 + Vector + RRF 融合。

    Usage:
        searcher = HybridSearcher()
        results = searcher.search("坎宅开门宜在何方", top_k=5)
    """

    def __init__(
        self,
        store: VectorStore | None = None,
        embedder: Embedder | None = None,
    ) -> None:
        self._store = store or get_vector_store()
        self._embedder = embedder or get_embedder()
        self._bm25: BM25Okapi | None = None
        self._bm25_chunks: list[Chunk] = []

    def rebuild_bm25(self) -> None:
        """从当前 vector store 重建 BM25 索引。"""
        chunks = self._store.get_all_chunks()
        if not chunks:
            logger.warning("没有 chunk，BM25 索引为空。")
            self._bm25 = None
            self._bm25_chunks = []
            return

        tokenized = [_tokenize_chinese(c.content) for c in chunks]
        self._bm25 = BM25Okapi(tokenized, k1=config.BM25_K1, b=config.BM25_B)
        self._bm25_chunks = chunks
        logger.info("BM25 索引已构建: %d 个文档", len(chunks))

    # ----------------------------------------------------------
    # Public API
    # ----------------------------------------------------------

    def search(
        self,
        query: str,
        top_k: int = config.DEFAULT_TOP_K,
        user_id: str = "",
        is_admin: bool = False,
    ) -> list[ScoredChunk]:
        """
        混合检索主入口。

        策略:
        1. BM25 关键词检索
        2. 向量语义检索
        3. RRF 融合排序

        Args:
            query: 用户查询。
            top_k: 返回数量。

        Returns:
            ScoredChunk 列表，按 RRF 分数降序排列。
        """
        if top_k <= 0:
            return []

        chunks = self._store.get_visible_chunks(user_id=user_id, is_admin=is_admin)
        if not chunks:
            return []
        visible_chunk_ids = {c.id for c in chunks}

        # 1. BM25 检索
        bm25_scores = self._bm25_search(query)
        bm25_scores = [(chunk_id, score) for chunk_id, score in bm25_scores if chunk_id in visible_chunk_ids]

        # 2. 向量检索
        vector_scores = self._vector_search(query, user_id=user_id, is_admin=is_admin)

        # 3. RRF 融合
        fused = self._rrf_fusion(bm25_scores, vector_scores, top_k)
        return fused

    # ----------------------------------------------------------
    # Retrieval methods
    # ----------------------------------------------------------

    def _bm25_search(self, query: str) -> list[tuple[int, float]]:
        """BM25 关键词检索。返回 [(chunk_id, normalized_score), ...]。"""
        if self._bm25 is None or not self._bm25_chunks:
            return []

        tokens = _tokenize_chinese(query)
        raw_scores = self._bm25.get_scores(tokens)

        # Normalize to [0, 1]
        max_score = max(raw_scores) if len(raw_scores) > 0 else 1.0
        if max_score == 0:
            return []

        results: list[tuple[int, float]] = []
        for i, score in enumerate(raw_scores):
            if score > 0:
                chunk_id = self._bm25_chunks[i].id
                norm_score = score / max_score
                results.append((chunk_id, norm_score))

        # Sort descending
        results.sort(key=lambda x: x[1], reverse=True)
        return results

    def _vector_search(self, query: str, user_id: str = "", is_admin: bool = False) -> list[tuple[int, float]]:
        """向量语义检索。返回 [(chunk_id, similarity), ...]。"""
        try:
            query_vec = self._embedder.encode(query)
        except Exception:
            logger.exception("Embedding 编码失败")
            return []

        raw_results = self._store.query(
            query_embedding=query_vec,
            n_results=config.DEFAULT_TOP_K * 2,  # 多取一些给 RRF 用
            user_id=user_id,
            is_admin=is_admin,
        )

        return [(chunk.id, score) for chunk, score in raw_results]

    # ----------------------------------------------------------
    # RRF Fusion
    # ----------------------------------------------------------

    def _rrf_fusion(
        self,
        bm25_results: list[tuple[int, float]],
        vector_results: list[tuple[int, float]],
        top_k: int,
    ) -> list[ScoredChunk]:
        """
        Reciprocal Rank Fusion。

        对两个排序列表的每个位置施加 1/(k+rank) 衰减，
        按 RRF 分数降序取 top_k。

        Args:
            bm25_results: BM25 结果 [(chunk_id, score), ...]。
            vector_results: 向量结果 [(chunk_id, score), ...]。
            top_k: 返回数量。

        Returns:
            ScoredChunk 列表。
        """
        rrf_k = 60  # RRF 常数

        # chunk_id → RRF 累计分数
        rrf_scores: dict[int, float] = {}

        for rank, (chunk_id, _) in enumerate(bm25_results):
            rrf_scores[chunk_id] = rrf_scores.get(chunk_id, 0.0) + 1.0 / (rrf_k + rank + 1)

        for rank, (chunk_id, _) in enumerate(vector_results):
            rrf_scores[chunk_id] = rrf_scores.get(chunk_id, 0.0) + 1.0 / (rrf_k + rank + 1)

        # 排序
        sorted_items = sorted(rrf_scores.items(), key=lambda x: x[1], reverse=True)
        top_items = sorted_items[:top_k]

        results: list[ScoredChunk] = []
        for chunk_id, rrf_score in top_items:
            chunk = self._store.get_chunk_by_id(chunk_id)
            if chunk:
                results.append(ScoredChunk(chunk=chunk, score=rrf_score))

        return results


# ----------------------------------------------------------
# Chinese tokenization
# ----------------------------------------------------------

def _tokenize_chinese(text: str) -> list[str]:
    """
    中文分词 + bigram 子词，与端侧 RAGService.segmentChinese() 保持一致。

    - 中文字符 → 用 jieba 分词 + bigram
    - 英文/数字 → 按空格/标点分割
    - 丢弃单字 token

    Args:
        text: 输入文本。

    Returns:
        token 列表。
    """
    tokens: list[str] = []

    try:
        import jieba
        jieba_words = jieba.lcut(text)
    except ImportError:
        # Fallback: 仅用 bigram
        jieba_words = [text]

    for word in jieba_words:
        word = word.strip()
        if not word:
            continue

        if re.search(r"[一-鿿]", word):
            # 中文部分
            if len(word) >= 2:
                tokens.append(word)
            # 额外生成 bigram 子词以增强召回
            for j in range(len(word) - 1):
                bigram = word[j:j + 2]
                if bigram not in tokens:
                    tokens.append(bigram)
        elif re.match(r"\w+", word):
            # 英文/数字
            tokens.append(word.lower())

    # 过滤单字
    return [t for t in tokens if len(t) >= 2]


# ----------------------------------------------------------
# Prompt builder
# ----------------------------------------------------------

def build_rag_prompt(
    query: str,
    context_chunks: list[Chunk],
    chat_history: list[dict[str, str]] | None = None,
) -> list[dict[str, str]]:
    """
    构建带上下文的 RAG prompt，与端侧 RAGService.buildRAGPrompt() 保持一致。

    Args:
        query: 用户查询。
        context_chunks: 检索到的知识 chunks。
        chat_history: 对话历史。

    Returns:
        完整的 messages 列表。
    """
    if not context_chunks:
        return chat_history or []

    context_str_parts: list[str] = []
    for i, chunk in enumerate(context_chunks):
        context_str_parts.append(
            f"【参考资料{i + 1}】来源：{chunk.title}\n{chunk.content}\n"
        )

    context_str = "\n".join(context_str_parts)

    system_prompt = (
        "你是一位深谙中国传统堪舆之术的风水顾问，精通八宅明镜、紫微斗数、地理五诀等经典。"
        "你的回答风格严谨，引经据典。\n\n"
        "以下是知识库中与用户问题相关的经典原文，请基于这些原文回答问题：\n\n"
        f"{context_str}\n"
        "【回答要求】\n"
        "1. 先引用相关的经典原文片段，再用白话解释\n"
        "2. 如果原文不足以完全回答，请如实说明\n"
        "3. 标注引用来源\n"
        "4. 态度严谨，不随意编造"
    )

    messages: list[dict[str, str]] = []
    messages.append({"role": "system", "content": system_prompt})

    if chat_history:
        messages.extend(chat_history)

    messages.append({"role": "user", "content": query})
    return messages


# 全局单例
_searcher: HybridSearcher | None = None


def get_searcher() -> HybridSearcher:
    """获取 HybridSearcher 全局单例。"""
    global _searcher
    if _searcher is None:
        _searcher = HybridSearcher()
    return _searcher
