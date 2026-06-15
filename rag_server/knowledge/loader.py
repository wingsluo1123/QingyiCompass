"""
知识库文件加载器

负责从 rawfile 目录读取风水经典 .txt 文件，返回结构化文档。
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import NamedTuple

from .. import config  #注意要使用相对导入

logger = logging.getLogger(__name__)


class RawDocument(NamedTuple):
    """加载后的原始文档"""
    file_name: str      # 文件名，如 "knowledge_bazhai.txt"
    title: str           # 经典名称，如 "八宅明镜"
    content: str         # 完整文本
    source_label: str    # 来源标签


def _resolve_knowledge_dir() -> Path:
    """解析知识库文件所在的目录，带 fallback。"""
    if config.RAW_FILE_DIR.exists():
        return config.RAW_FILE_DIR

    # Fallback: 从 rag_server 同级查找
    alt = Path(__file__).resolve().parent.parent.parent / "entry" / "src" / "main" / "resources" / "rawfile"
    if alt.exists():
        return alt

    raise FileNotFoundError(
        f"知识库目录不存在。已尝试: {config.RAW_FILE_DIR}, {alt}"
    )


def load_knowledge_files() -> list[RawDocument]:
    """
    加载所有配置的知识库文件。

    Returns:
        RawDocument 列表，每个对应一个经典文件。
    """
    raw_dir = _resolve_knowledge_dir()
    documents: list[RawDocument] = []

    for file_name in config.KNOWLEDGE_FILES:
        file_path = raw_dir / file_name
        if not file_path.exists():
            logger.warning("知识库文件不存在，跳过: %s", file_path)
            continue

        try:
            content = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            logger.warning("文件编码非 UTF-8，尝试 GBK: %s", file_path)
            content = file_path.read_text(encoding="gbk")

        title = config.FILE_TITLE_MAP.get(file_name, file_name.replace(".txt", ""))
        documents.append(RawDocument(
            file_name=file_name,
            title=title,
            content=content,
            source_label="内置经典",
        ))
        logger.info("已加载: %s → %s (%d 字符)", file_name, title, len(content))

    return documents
