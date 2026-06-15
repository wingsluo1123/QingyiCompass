"""ChromaDB vector store wrapper."""

from __future__ import annotations

import logging
import uuid

import chromadb
from chromadb.config import Settings as ChromaSettings

from .. import config
from .chunker import Chunk
from .loader import load_knowledge_files

logger = logging.getLogger(__name__)


class VectorStore:
    """Persistent ChromaDB store for knowledge chunks."""

    COLLECTION_NAME = "compass_knowledge"

    def __init__(self) -> None:
        self._client = chromadb.PersistentClient(
            path=str(config.CHROMA_PERSIST_DIR),
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        self._collection = self._client.get_or_create_collection(
            name=self.COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"},
        )
        self._chunks: list[Chunk] = []

    @property
    def chunk_count(self) -> int:
        return self._collection.count()

    def get_all_chunks(self) -> list[Chunk]:
        return list(self._chunks)

    def get_visible_chunks(self, user_id: str = "", is_admin: bool = False) -> list[Chunk]:
        return [
            c for c in self._chunks
            if self.can_access_chunk(c, user_id=user_id, is_admin=is_admin)
        ]

    def get_chunk_by_id(self, chunk_id: int) -> Chunk | None:
        for c in self._chunks:
            if c.id == chunk_id:
                return c
        return None

    @staticmethod
    def can_access_chunk(chunk: Chunk, user_id: str = "", is_admin: bool = False) -> bool:
        if is_admin:
            return True
        if chunk.visibility == "public":
            return True
        return bool(user_id) and chunk.owner_user_id == user_id

    def ensure_loaded(self, force_rebuild: bool = False) -> None:
        if force_rebuild:
            self._rebuild()
            return

        if self.chunk_count == 0:
            logger.info("Vector store is empty, building index...")
            self._rebuild()
        else:
            logger.info("Vector store exists (%d chunks), loading metadata...", self.chunk_count)
            self._load_chunks_from_db()

    def add_text_document(
        self,
        text: str,
        title: str,
        source: str = "user_upload",
        category: str = "custom_knowledge",
        owner_user_id: str = "",
        visibility: str = "private",
    ) -> list[Chunk]:
        """Chunk, embed, and append one user document to ChromaDB."""
        from .chunker import chunk_text

        clean_text = text.strip()
        if not clean_text:
            raise ValueError("document content is empty")

        start_id = max((c.id for c in self._chunks), default=-1) + 1
        chunks = chunk_text(
            text=clean_text,
            title=title.strip() or "untitled_document",
            source=source,
            category=category,
            start_id=start_id,
        )
        if not chunks:
            raise ValueError("document produced no valid chunks")

        chunks = [
            c._replace(owner_user_id=owner_user_id, visibility=visibility)
            for c in chunks
        ]

        self._add_chunks(chunks)
        self._chunks.extend(chunks)
        logger.info("User document indexed: %s -> %d chunks", title, len(chunks))
        return chunks

    def query(
        self,
        query_embedding: list[float],
        n_results: int = 5,
        user_id: str = "",
        is_admin: bool = False,
    ) -> list[tuple[Chunk, float]]:
        if self.chunk_count == 0:
            return []

        result = self._collection.query(
            query_embeddings=[query_embedding],
            n_results=min(max(n_results * 10, n_results), self.chunk_count),
            include=["documents", "metadatas", "distances"],
        )

        chunks_with_scores: list[tuple[Chunk, float]] = []
        if not result["ids"] or not result["ids"][0]:
            return chunks_with_scores

        for i, _doc_id in enumerate(result["ids"][0]):
            chunk_id = int(result["metadatas"][0][i]["chunk_id"])  # type: ignore[index]
            distance = result["distances"][0][i]  # type: ignore[index]
            similarity = 1.0 - distance

            chunk = self.get_chunk_by_id(chunk_id)
            if chunk and self.can_access_chunk(chunk, user_id=user_id, is_admin=is_admin):
                chunks_with_scores.append((chunk, similarity))
            if len(chunks_with_scores) >= n_results:
                break

        return chunks_with_scores

    def _rebuild(self) -> None:
        try:
            self._client.delete_collection(name=self.COLLECTION_NAME)
        except Exception:
            logger.debug("Collection did not exist before rebuild")

        self._collection = self._client.get_or_create_collection(
            name=self.COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"},
        )
        self._chunks = []

        documents = load_knowledge_files()
        if not documents:
            logger.warning("No knowledge files found")
            return

        from .chunker import chunk_text

        all_chunks: list[Chunk] = []
        for doc in documents:
            chunks = chunk_text(
                text=doc.content,
                title=doc.title,
                source=doc.source_label,
                start_id=len(all_chunks),
            )
            all_chunks.extend(chunks)

        if not all_chunks:
            logger.warning("Knowledge files produced no chunks")
            return

        self._add_chunks(all_chunks)
        self._chunks = all_chunks
        logger.info("Index built: %d files -> %d chunks", len(documents), len(all_chunks))

    def _add_chunks(self, chunks: list[Chunk]) -> None:
        from ..retrieval.embedder import get_embedder

        embedder = get_embedder()
        batch_size = 50
        for start in range(0, len(chunks), batch_size):
            batch = chunks[start:start + batch_size]
            ids = [str(uuid.uuid4())[:8] for _ in batch]
            docs_text = [c.content for c in batch]
            metadatas = [
                {
                    "chunk_id": c.id,
                    "title": c.title,
                    "source": c.source,
                    "category": c.category,
                    "keywords": c.keywords,
                    "owner_user_id": c.owner_user_id,
                    "visibility": c.visibility,
                }
                for c in batch
            ]
            embeddings = embedder.encode_batch(docs_text)
            self._collection.add(
                ids=ids,
                documents=docs_text,
                metadatas=metadatas,  # type: ignore[arg-type]
                embeddings=embeddings,
            )

    def _load_chunks_from_db(self) -> None:
        result = self._collection.get(include=["documents", "metadatas"])
        documents = result.get("documents") or []
        metadatas = result.get("metadatas") or []
        if not metadatas:
            self._chunks = []
            return

        chunks_by_id: dict[int, Chunk] = {}
        for i, meta in enumerate(metadatas):  # type: ignore[assignment]
            chunk_id = meta.get("chunk_id")  # type: ignore[union-attr]
            if chunk_id is None:
                continue
            chunk_id = int(chunk_id)
            if chunk_id in chunks_by_id:
                continue

            content = documents[i] if i < len(documents) else ""
            source = str(meta.get("source", "builtin"))
            owner_user_id = str(meta.get("owner_user_id", ""))
            visibility = str(meta.get("visibility", ""))
            if not visibility:
                if source == "user_upload" or "用户" in source:
                    visibility = "private"
                    if not owner_user_id and config.LEVEL3_UNION_IDS:
                        owner_user_id = sorted(config.LEVEL3_UNION_IDS)[0]
                else:
                    visibility = "public"
            chunks_by_id[chunk_id] = Chunk(
                id=chunk_id,
                title=str(meta.get("title", "")),
                content=str(content),
                source=source,
                category=str(meta.get("category", "knowledge")),
                keywords=str(meta.get("keywords", "")),
                owner_user_id=owner_user_id,
                visibility=visibility,
            )

        self._chunks = [chunks_by_id[k] for k in sorted(chunks_by_id)]
        logger.info("Loaded %d chunks from ChromaDB", len(self._chunks))


_store: VectorStore | None = None


def get_vector_store() -> VectorStore:
    global _store
    if _store is None:
        _store = VectorStore()
    return _store
