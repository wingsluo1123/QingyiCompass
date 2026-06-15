"""
Embedding 模型封装

使用 sentence-transformers 加载中文语义模型，
提供单条/批量文本向量化能力。
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .. import config

logger = logging.getLogger(__name__)

if TYPE_CHECKING:
    from sentence_transformers import SentenceTransformer


class Embedder:
    """
    文本向量化器。

    Usage:
        emb = Embedder()
        vec = emb.encode("坎宅开门宜在何方")
        vecs = emb.encode_batch(["文本1", "文本2", "文本3"])
    """

    def __init__(self) -> None:
        self._model: SentenceTransformer | None = None

    @property
    def model_name(self) -> str:
        return config.EMBEDDING_MODEL_NAME

    @property
    def dim(self) -> int:
        """Embedding 向量维度。"""
        self._ensure_loaded()
        return self._model.get_sentence_embedding_dimension()  # type: ignore[union-attr]

    def encode(self, text: str) -> list[float]:
        """
        将单条文本编码为向量。

        Args:
            text: 输入文本。

        Returns:
            float 列表，长度为模型维度。
        """
        self._ensure_loaded()
        embedding = self._model.encode(text, normalize_embeddings=True)  # type: ignore[union-attr]
        return embedding.tolist()  # type: ignore[no-any-return]

    def encode_batch(self, texts: list[str]) -> list[list[float]]:
        """
        批量编码文本。

        Args:
            texts: 文本列表。

        Returns:
            向量列表。
        """
        self._ensure_loaded()
        embeddings = self._model.encode(texts, normalize_embeddings=True, show_progress_bar=False)  # type: ignore[union-attr]
        return embeddings.tolist()  # type: ignore[no-any-return]

    def _ensure_loaded(self) -> None:
        """懒加载模型（首次使用时下载）。"""
        if self._model is not None:
            return

        logger.info("正在加载 embedding 模型: %s ...", self.model_name)
        try:
            from sentence_transformers import SentenceTransformer
            self._model = SentenceTransformer(
                self.model_name,
                device="cpu",  # 默认 CPU，如需 GPU 改为 "cuda"
            )
            logger.info(
                "模型加载完成。维度: %d",
                self._model.get_sentence_embedding_dimension(),
            )
        except ImportError:
            raise ImportError(
                "请先安装 sentence-transformers: pip install sentence-transformers"
            )


# 全局单例
_embedder: Embedder | None = None


def get_embedder() -> Embedder:
    """获取 Embedder 全局单例。"""
    global _embedder
    if _embedder is None:
        _embedder = Embedder()
    return _embedder
