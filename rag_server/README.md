# Compass RAG Server

为 **清易罗盘** HarmonyOS App 提供风水经典知识检索（RAG）服务。

## 架构概览

```
rag_server/
├── main.py                  # FastAPI 入口，SSE 流式端点
├── config.py                # 全局配置（路径、模型、检索参数）
├── requirements.txt         # Python 依赖
├── README.md
├── models/
│   └── schemas.py           # Pydantic 数据模型（与端侧接口对齐）
├── knowledge/
│   ├── loader.py            # 知识库 .txt 文件加载器
│   ├── chunker.py           # 文本分块器（段落合并 + 重叠）
│   └── store.py             # ChromaDB 向量存储
└── retrieval/
    ├── embedder.py           # sentence-transformers 向量化
    └── searcher.py           # BM25 + 向量 + RRF 混合检索
```

## 快速开始

### 1. 安装依赖

```bash
cd compass/rag_server
pip install -r requirements.txt
```

### 2. 启动服务

```bash
# 方式一：模块启动
python -m rag_server.main

# 方式二：uvicorn 直接启动
uvicorn rag_server.main:app --host 0.0.0.0 --port 8765
```

首次启动时会自动：
- 加载 `entry/src/main/resources/rawfile/` 下的知识库文件
- 下载 embedding 模型（`shibing624/text2vec-base-chinese`，约 400MB）
- 构建 ChromaDB 向量索引 + BM25 稀疏索引

### 3. 验证

```bash
curl http://localhost:8765/v1/rag/health
# {"status":"ok","model":"shibing624/text2vec-base-chinese","chunk_count":42,"version":"1.0.0"}

curl -X POST http://localhost:8765/v1/rag/search \
  -H "Content-Type: application/json" \
  -d '{"query": "坎宅开门宜在何方", "top_k": 3}'
```

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/v1/rag/health` | 健康检查 |
| `POST` | `/v1/rag/search` | 非流式检索，返回 JSON |
| `POST` | `/v1/rag/query` | SSE 流式检索，逐 chunk 推送 |

### SSE 事件格式

与端侧 [EventSourceUtil.ets](../entry/src/main/ets/service/EventSourceUtil.ets) 的 SSE 解析对齐：

```
event: status
data: {"status": "searching", "query": "..."}

event: chunk
data: {"id": 0, "title": "八宅明镜 (第5段)", "content": "...", "score": 0.085}

event: rag_prompt
data: {"messages": [{"role": "system", "content": "..."}, ...]}

event: done
data: {"total": 5, "elapsed_ms": 123.4}
```

## 端侧对接

App 端通过 `EventSourceUtil.ets` 的 SSE 客户端连接：

```typescript
// 示例：在 AiChatPage 等页面中连接 RAG 服务
const ragUrl = 'http://192.168.1.100:8765/v1/rag/query';
const eventSource = new EventSource(ragUrl, {
  method: http.RequestMethod.POST,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: userQuery, top_k: 5, stream: true })
});

eventSource.onMessage = (event: EventSourceEvent) => {
  if (event.type === 'chunk') {
    const chunk = JSON.parse(event.data);
    // 处理检索结果...
  } else if (event.type === 'rag_prompt') {
    const { messages } = JSON.parse(event.data);
    // 发送给 LLM...
  }
};
```

## 配置

所有可调参数在 [config.py](config.py) 中集中管理：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `EMBEDDING_MODEL_NAME` | `shibing624/text2vec-base-chinese` | Embedding 模型 |
| `CHUNK_SIZE` | 400 | 文本分块大小（字符） |
| `CHUNK_OVERLAP` | 50 | 相邻 chunk 重叠字符数 |
| `DEFAULT_TOP_K` | 5 | 默认返回 Top-K |
| `HYBRID_VECTOR_WEIGHT` | 0.6 | 混合检索向量权重 |
| `SERVER_PORT` | 8765 | 服务端口 |

支持环境变量覆盖：`EMBEDDING_MODEL`、`RAG_HOST`、`RAG_PORT`。

## 混合检索策略

```
用户查询
    │
    ├──→ BM25 关键词检索 ──→ [chunk, score] 列表
    │    (jieba 分词 + bigram + 关键词加权)
    │
    ├──→ 向量语义检索 ──→ [chunk, similarity] 列表
    │    (sentence-transformers + ChromaDB cosine)
    │
    └──→ RRF 融合排序 ──→ 最终 Top-K 结果
         (Reciprocal Rank Fusion, k=60)
```

## 技术栈

- **Web 框架**: FastAPI + uvicorn
- **向量数据库**: ChromaDB（持久化到本地）
- **Embedding**: sentence-transformers (`text2vec-base-chinese`)
- **稀疏检索**: rank-bm25 (BM25Okapi)
- **中文分词**: jieba
- **流式传输**: sse-starlette
