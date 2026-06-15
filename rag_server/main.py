"""
Compass RAG Server — FastAPI 入口

为 HarmonyOS 罗盘 App 提供风水经典知识检索服务。
通过 SSE (Server-Sent Events) 流式返回检索结果，
与端侧 EventSourceUtil.ets 的 SSE 客户端直接对接。

启动方式:
    python -m rag_server.main
    或
    cd compass && uvicorn rag_server.main:app --host 0.0.0.0 --port 8765

API 端点:
    GET  /v1/rag/health         — 健康检查
    POST /v1/rag/search         — 非流式检索 (JSON)
    POST /v1/rag/query          — SSE 流式检索
"""

from __future__ import annotations

import json
import logging
import time
import hashlib
import hmac
import base64
import urllib.parse
import urllib.request
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse

from . import config
from .knowledge import get_vector_store
from .knowledge.ingest import extract_text_from_upload
from .models.schemas import (
    HealthResponse,
    KnowledgeChunk,
    KnowledgeUploadResponse,
    KnowledgeUploadTextRequest,
    RAGQueryRequest,
    RAGQueryResponse,
)
from .retrieval import get_embedder, get_searcher
from .retrieval.searcher import build_rag_prompt

# ============================================================
# Logging
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("rag_server")

PUBLIC_PATHS = {"/", "/v1/rag/health"}


@dataclass(frozen=True)
class AppUser:
    union_id: str
    open_id: str
    level: int

    @property
    def is_admin(self) -> bool:
        return self.level >= 3


class HuaweiLoginRequest(BaseModel):
    union_id: str = Field(min_length=1)
    open_id: str = Field(min_length=1)
    authorization_code: str = ""
    id_token: str = ""


class HuaweiLoginResponse(BaseModel):
    session_token: str
    union_id: str
    open_id: str
    level: int
    expires_in: int

# ============================================================
# Application lifecycle
# ============================================================


@asynccontextmanager
async def lifespan(app: FastAPI):
    """服务启动/关闭时的生命周期管理。"""
    logger.info("=" * 55)
    logger.info("Compass RAG Server 启动中...")
    logger.info("=" * 55)

    # 预加载知识库和模型
    store = get_vector_store()
    store.ensure_loaded()
    logger.info("知识库 chunks: %d", store.chunk_count)

    searcher = get_searcher()
    searcher.rebuild_bm25()
    logger.info("BM25 索引已就绪")

    embedder = get_embedder()
    logger.info("Embedding 模型: %s (维度: %d)", embedder.model_name, embedder.dim)

    logger.info("✅ 服务就绪 — http://%s:%d", config.SERVER_HOST, config.SERVER_PORT)
    yield
    logger.info("Compass RAG Server 已关闭。")


# ============================================================
# FastAPI app
# ============================================================

app = FastAPI(
    title="Compass RAG Server",
    description="风水经典知识检索服务 — 为清易罗盘 App 提供 RAG 能力",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — 允许 App 跨域访问（局域网场景）
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def require_rag_auth(request: Request, call_next):
    if request.method == "OPTIONS" or request.url.path in PUBLIC_PATHS:
        return await call_next(request)

    if not config.RAG_AUTH_TOKEN:
        return await call_next(request)

    expected = f"Bearer {config.RAG_AUTH_TOKEN}"
    actual = request.headers.get("Authorization", "")
    if actual != expected:
        return JSONResponse(status_code=401, content={"detail": "Unauthorized"})

    return await call_next(request)

# ============================================================
# Endpoints
# ============================================================


@app.get("/")
async def root():
    """Basic landing response for the public domain."""
    return {
        "service": "Compass RAG Server",
        "status": "ok",
        "health": "/v1/rag/health",
    }


@app.get("/v1/rag/health", response_model=HealthResponse)
async def health_check():
    """健康检查 — App 启动时可调用此接口确认服务可用。"""
    store = get_vector_store()
    return HealthResponse(
        status="ok",
        model=get_embedder().model_name,
        chunk_count=store.chunk_count,
    )


def _normalize_doc_name(title: str) -> str:
    idx = title.find(" (")
    return title[:idx] if idx >= 0 else title


def _document_id(source: str, name: str, owner_user_id: str = "") -> str:
    raw = f"{source}|{name}|{owner_user_id}".encode("utf-8")
    return hashlib.sha1(raw).hexdigest()


def _chunk_response(chunk) -> KnowledgeChunk:
    return KnowledgeChunk(
        id=chunk.id,
        title=chunk.title,
        content=chunk.content,
        source=chunk.source,
        category=chunk.category,
        keywords=chunk.keywords,
    )


def _resolve_account_level(union_id: str, open_id: str) -> int:
    if union_id in config.LEVEL3_UNION_IDS or open_id in config.LEVEL3_OPEN_IDS:
        return 3
    return config.DEFAULT_ACCOUNT_LEVEL


def _sign_app_session(union_id: str, open_id: str, level: int) -> str:
    expires_at = int(time.time()) + config.APP_SESSION_TTL_SECONDS
    payload = json.dumps(
        {"provider": "huawei", "union_id": union_id, "open_id": open_id, "level": level, "exp": expires_at},
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    encoded_payload = base64.urlsafe_b64encode(payload).decode("ascii").rstrip("=")
    signature = hmac.new(
        config.APP_SESSION_SECRET.encode("utf-8"),
        encoded_payload.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return f"{encoded_payload}.{signature}"


def _verify_app_session_token(token: str) -> AppUser:
    try:
        encoded_payload, signature = token.split(".", 1)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Invalid app session") from exc

    expected_signature = hmac.new(
        config.APP_SESSION_SECRET.encode("utf-8"),
        encoded_payload.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(signature, expected_signature):
        raise HTTPException(status_code=401, detail="Invalid app session")

    padded_payload = encoded_payload + ("=" * (-len(encoded_payload) % 4))
    try:
        payload = json.loads(base64.urlsafe_b64decode(padded_payload).decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid app session") from exc

    if int(payload.get("exp", 0)) < int(time.time()):
        raise HTTPException(status_code=401, detail="App session expired")

    union_id = str(payload.get("union_id", ""))
    open_id = str(payload.get("open_id", ""))
    if not union_id or not open_id:
        raise HTTPException(status_code=401, detail="Invalid app session")

    return AppUser(
        union_id=union_id,
        open_id=open_id,
        level=int(payload.get("level", config.DEFAULT_ACCOUNT_LEVEL)),
    )


def _get_optional_app_user(request: Request) -> AppUser | None:
    token = request.headers.get("X-App-Session", "").strip()
    if not token:
        return None
    return _verify_app_session_token(token)


def _require_app_user(request: Request) -> AppUser:
    user = _get_optional_app_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Login required")
    return user


def _verify_huawei_authorization_code(authorization_code: str) -> None:
    if not config.HUAWEI_VERIFY_AUTH_CODE:
        return
    if not authorization_code:
        raise HTTPException(status_code=400, detail="authorization_code is required")
    if not config.HUAWEI_CLIENT_ID or not config.HUAWEI_CLIENT_SECRET:
        raise HTTPException(status_code=503, detail="Huawei OAuth config is incomplete")

    body: dict[str, str] = {
        "grant_type": "authorization_code",
        "code": authorization_code,
        "client_id": config.HUAWEI_CLIENT_ID,
        "client_secret": config.HUAWEI_CLIENT_SECRET,
    }
    if config.HUAWEI_REDIRECT_URI:
        body["redirect_uri"] = config.HUAWEI_REDIRECT_URI

    data = urllib.parse.urlencode(body).encode("utf-8")
    request = urllib.request.Request(
        "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            if response.status < 200 or response.status >= 300:
                raise HTTPException(status_code=401, detail="Huawei authorization failed")
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning("Huawei authorization code verification failed: %s", exc)
        raise HTTPException(status_code=401, detail="Huawei authorization failed") from exc


@app.post("/v1/auth/huawei/login", response_model=HuaweiLoginResponse)
async def login_with_huawei(request: HuaweiLoginRequest):
    """Create an app session from Huawei Account Kit identity."""
    _verify_huawei_authorization_code(request.authorization_code)
    level = _resolve_account_level(request.union_id, request.open_id)
    session_token = _sign_app_session(request.union_id, request.open_id, level)
    return HuaweiLoginResponse(
        session_token=session_token,
        union_id=request.union_id,
        open_id=request.open_id,
        level=level,
        expires_in=config.APP_SESSION_TTL_SECONDS,
    )


@app.get("/v1/rag/documents")
async def list_documents(request: Request):
    """Return document summaries only; chunk content is loaded on demand."""
    user = _get_optional_app_user(request)
    store = get_vector_store()
    docs: dict[str, dict[str, object]] = {}
    for c in store.get_visible_chunks(
        user_id=user.union_id if user else "",
        is_admin=user.is_admin if user else False,
    ):
        name = _normalize_doc_name(c.title)
        doc_id = _document_id(c.source, name, c.owner_user_id)
        if doc_id not in docs:
            docs[doc_id] = {
                "id": doc_id,
                "name": name,
                "source": c.source,
                "category": c.category,
                "visibility": c.visibility,
                "chunk_count": 0,
            }
        docs[doc_id]["chunk_count"] = int(docs[doc_id]["chunk_count"]) + 1
    return {"documents": list(docs.values()), "total": len(docs)}


@app.get("/v1/rag/documents/{doc_id}/chunks")
async def get_document_chunks(doc_id: str, request: Request):
    """Return full chunk content for one document."""
    user = _get_optional_app_user(request)
    store = get_vector_store()
    chunks: list[KnowledgeChunk] = []
    for c in store.get_visible_chunks(
        user_id=user.union_id if user else "",
        is_admin=user.is_admin if user else False,
    ):
        name = _normalize_doc_name(c.title)
        if _document_id(c.source, name, c.owner_user_id) == doc_id:
            chunks.append(_chunk_response(c))
    if not chunks:
        raise HTTPException(status_code=404, detail="文档不存在")
    return {"chunks": chunks, "total": len(chunks)}


@app.post("/v1/rag/upload", response_model=KnowledgeUploadResponse)
async def upload_document(request: Request, file_name: str = "upload.txt"):
    """Upload raw document bytes, extract text, embed it, and refresh indexes."""
    user = _require_app_user(request)
    data = await request.body()
    try:
        text = extract_text_from_upload(file_name, data)
        title = Path(file_name).stem or file_name
        chunks = get_vector_store().add_text_document(
            text=text,
            title=title,
            owner_user_id=user.union_id,
            visibility="private",
        )
        get_searcher().rebuild_bm25()
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Upload indexing failed")
        raise HTTPException(status_code=500, detail=f"文档向量化失败: {exc}") from exc

    return KnowledgeUploadResponse(
        file_name=file_name,
        title=title,
        chunk_count=len(chunks),
        total_chunk_count=get_vector_store().chunk_count,
    )


@app.post("/v1/rag/upload/text", response_model=KnowledgeUploadResponse)
async def upload_text_document(request: Request, upload: KnowledgeUploadTextRequest):
    """Upload already-extracted plain text from a client."""
    user = _require_app_user(request)
    file_name = upload.file_name or "upload.txt"
    title = upload.title.strip() or Path(file_name).stem or file_name
    try:
        chunks = get_vector_store().add_text_document(
            text=upload.content,
            title=title,
            owner_user_id=user.union_id,
            visibility="private",
        )
        get_searcher().rebuild_bm25()
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logger.exception("Text upload indexing failed")
        raise HTTPException(status_code=500, detail=f"文档向量化失败: {exc}") from exc

    return KnowledgeUploadResponse(
        file_name=file_name,
        title=title,
        chunk_count=len(chunks),
        total_chunk_count=get_vector_store().chunk_count,
    )


@app.post("/v1/rag/search", response_model=RAGQueryResponse)
async def search(request: Request, query_request: RAGQueryRequest):
    """
    非流式检索 — 一次性返回 JSON 结果。

    适用于不需要流式输出的场景（如快速预览、批量查询）。
    """
    start = time.perf_counter()
    user = _get_optional_app_user(request)

    searcher = get_searcher()
    scored = searcher.search(
        query=query_request.query,
        top_k=query_request.top_k,
        user_id=user.union_id if user else "",
        is_admin=user.is_admin if user else False,
    )

    chunks: list[KnowledgeChunk] = []
    for sc in scored:
        chunks.append(KnowledgeChunk(
            id=sc.chunk.id,
            title=sc.chunk.title,
            content=sc.chunk.content,
            source=sc.chunk.source,
            category=sc.chunk.category,
            keywords=sc.chunk.keywords,
        ))

    elapsed = time.perf_counter() - start
    logger.info("Search complete: '%s' -> %d hits (%.3fs)", query_request.query[:50], len(chunks), elapsed)

    return RAGQueryResponse(
        chunks=chunks,
        query=query_request.query,
        total_hits=len(chunks),
    )


@app.post("/v1/rag/query")
async def query_stream(request: Request, query_request: RAGQueryRequest):
    """
    SSE 流式检索 — 逐 chunk 推送结果。

    SSE 事件格式 (与端侧 EventSourceUtil.ets 解析对齐):
        event: chunk
        data: {"id": 0, "title": "...", "content": "...", ...}

        event: rag_prompt
        data: {"messages": [...]}

        event: done
        data: {"total": N}

    端侧通过 EventSource 接收，onMessage 回调逐条处理。
    """

    async def event_generator():
        start = time.perf_counter()
        user = _get_optional_app_user(request)

        # 1. 发送开始事件
        yield {
            "event": "status",
            "data": json.dumps({"status": "searching", "query": query_request.query}, ensure_ascii=False),
        }

        # 2. 检索
        try:
            searcher = get_searcher()
            scored = searcher.search(
                query=query_request.query,
                top_k=query_request.top_k,
                user_id=user.union_id if user else "",
                is_admin=user.is_admin if user else False,
            )
        except Exception as e:
            logger.exception("检索失败")
            yield {
                "event": "error",
                "data": json.dumps({"error": str(e)}, ensure_ascii=False),
            }
            return

        # 3. 逐 chunk 推送
        for i, sc in enumerate(scored):
            chunk_data = json.dumps({
                "id": sc.chunk.id,
                "title": sc.chunk.title,
                "content": sc.chunk.content,
                "source": sc.chunk.source,
                "category": sc.chunk.category,
                "keywords": sc.chunk.keywords,
                "score": round(sc.score, 4),
            }, ensure_ascii=False)

            yield {"event": "chunk", "data": chunk_data}

            # 模拟流式效果：每个 chunk 之间微延迟
            # （如果 App 端需要渐进渲染效果可保留，否则可移除）
            # await asyncio.sleep(0.05)

        # 4. 构建 RAG prompt（如果请求中有 chat_history）
        if query_request.stream and scored:
            chat_history_dicts = [
                {"role": m.role, "content": m.content}
                for m in (query_request.chat_history or [])
            ]
            rag_messages = build_rag_prompt(
                query=query_request.query,
                context_chunks=[sc.chunk for sc in scored],
                chat_history=chat_history_dicts if chat_history_dicts else None,
            )
            yield {
                "event": "rag_prompt",
                "data": json.dumps({"messages": rag_messages}, ensure_ascii=False),
            }

        # 5. 完成事件
        elapsed = time.perf_counter() - start
        yield {
            "event": "done",
            "data": json.dumps({
                "total": len(scored),
                "elapsed_ms": round(elapsed * 1000, 1),
            }, ensure_ascii=False),
        }

    return EventSourceResponse(event_generator())


# ============================================================
# Run
# ============================================================

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "rag_server.main:app",
        host=config.SERVER_HOST,
        port=config.SERVER_PORT,
        reload=False,
        log_level="info",
    )
