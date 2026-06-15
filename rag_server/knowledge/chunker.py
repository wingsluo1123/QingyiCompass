"""
文本分块器

以段落为最小单位，按目标大小合并段落形成 chunk，
支持重叠以保留跨 chunk 上下文。
"""

from __future__ import annotations

import logging
import re
from typing import NamedTuple

from .. import config

logger = logging.getLogger(__name__)


class Chunk(NamedTuple):
    """一个文本分块"""
    id: int
    title: str         # 经典名称 + 段落编号
    content: str
    source: str
    category: str
    keywords: str
    owner_user_id: str = ""
    visibility: str = "public"


def _extract_keywords(text: str) -> str:
    """
    从文本中提取风水关键词，与端侧 KnowledgeService.extractKeywords() 保持一致。

    Args:
        text: 待提取的文本。

    Returns:
        空格分隔的关键词字符串。
    """
    matched: list[str] = []
    for kw in config.FENGSHUI_KEYWORDS:
        if kw in text:
            matched.append(kw)
    return " ".join(matched)


def _split_paragraphs(text: str) -> list[str]:
    """
    按双换行分割段落，保留章节标题。

    Args:
        text: 原始文本。

    Returns:
        段落列表（已去空行）。
    """
    paragraphs = re.split(r"\n{2,}", text)
    result: list[str] = []
    for p in paragraphs:
        p = p.strip()
        if p:
            result.append(p)
    return result


def chunk_text(
    text: str,
    title: str,
    source: str = "内置经典",
    category: str = "风水经典",
    start_id: int = 0,
) -> list[Chunk]:
    """
    将文本切分为有重叠的 chunk。

    策略：
    1. 按双换行拆分为段落
    2. 贪心合并段落直到接近 chunk_size
    3. 相邻 chunk 之间保留 overlap 字符的上下文

    Args:
        text: 原始文本。
        title: 来源经典名称。
        source: 来源标签。
        category: 分类标签。
        start_id: 起始 chunk ID。

    Returns:
        Chunk 列表。
    """
    paragraphs = _split_paragraphs(text)
    if not paragraphs:
        return []

    chunks: list[Chunk] = []
    current_text = ""
    chunk_id = start_id

    for para in paragraphs:
        # 如果当前累积 + 新段落超限，先保存当前 chunk
        if len(current_text) + len(para) > config.CHUNK_SIZE and current_text:
            trimmed = current_text.strip()
            if trimmed:
                keywords = _extract_keywords(trimmed)
                chunks.append(Chunk(
                    id=chunk_id,
                    title=f"{title} (第{chunk_id + 1}段)",
                    content=trimmed,
                    source=source,
                    category=category,
                    keywords=keywords,
                ))
                chunk_id += 1

                # 重叠处理：保留当前段落作为下一个 chunk 的上下文起点
                if len(trimmed) > config.CHUNK_OVERLAP:
                    current_text = trimmed[-config.CHUNK_OVERLAP:] + "\n\n" + para
                else:
                    current_text = para
            else:
                current_text = para
        else:
            current_text += ("\n\n" + para) if current_text else para

    # 处理最后一段
    trimmed = current_text.strip()
    if trimmed:
        keywords = _extract_keywords(trimmed)
        chunks.append(Chunk(
            id=chunk_id,
            title=f"{title} (第{chunk_id + 1}段)",
            content=trimmed,
            source=source,
            category=category,
            keywords=keywords,
        ))
        chunk_id += 1

    logger.debug("分块完成: %s → %d chunks", title, len(chunks))
    return chunks
