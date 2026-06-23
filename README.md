# Qingyi Compass

Qingyi Compass is a HarmonyOS compass application with traditional compass tools, Zi Wei chart views, an AI chat assistant, and an optional RAG knowledge-base backend.

The current codebase is the backend-enabled version. It supports Huawei Account Kit login, server-configured customer accounts, guest sessions, user-separated document uploads, and Markdown-rendered AI responses.

## Requirements

- HarmonyOS API 6.1.0 (API 23) or later
- DevEco Studio compatible with HarmonyOS API 23
- Python 3.10+ for the optional RAG backend

## Main Features

- Digital compass with custom Canvas rendering and sensor-driven direction updates
- Zi Wei chart pages and related calculation views
- AI chat with configurable chat-completion endpoint, model, and API key
- Markdown response rendering through the local `fluid-markdown` HAR module
- Dark mode support with persisted user preference
- Knowledge-base page for listing, viewing, and uploading user documents
- RAG retrieval over built-in knowledge and user-uploaded private documents
- Account page with Huawei login and a customer-account login channel

## Architecture

The app has two major parts:

- `entry/`: HarmonyOS application module
- `rag_server/`: optional Python FastAPI backend for RAG retrieval and document indexing

The RAG backend uses:

- FastAPI for HTTP APIs
- ChromaDB for local vector persistence
- `sentence-transformers` for embeddings
- `rank-bm25` for lexical retrieval
- SSE for streaming RAG retrieval events

The backend does not use MySQL. Uploaded document chunks and metadata are persisted under:

```text
rag_server/chroma_data/
```

## Project Layout

```text
AppScope/
entry/
  src/main/ets/
    common/
    component/
    controller/
    model/
    pages/
      Index.ets
      CompassPage.ets
      Chart.ets
      AiChatPage.ets
      KnowledgePage.ets
      KnowledgeDetailPage.ets
      LoginPage.ets
      About.ets
    service/
      ApiConfigService.ets
      AuthService.ets
      AiService.ets
      RAGService.ets
      KnowledgeService.ets
      ThemeService.ets
markdown/
rag_server/
  main.py
  config.py
  knowledge/
  retrieval/
  models/
```

## App Configuration

The AI settings are configured at runtime in the app:

- Chat API key
- Chat completion base URL
- Model name
- RAG backend URL
- RAG service token
- RAG enabled/disabled switch

Defaults are defined in:

```text
entry/src/main/ets/service/ApiConfigService.ets
```

The app requires network access:

```text
ohos.permission.INTERNET
```

## RAG Backend Setup

Install backend dependencies:

```powershell
pip install -r rag_server/requirements.txt
```

Create a local backend environment file:

```text
rag_server/.env.local
```

Example:

```env
RAG_AUTH_TOKEN=replace-with-a-strong-service-token
APP_SESSION_SECRET=replace-with-a-strong-session-secret
CUSTOMER_LOGIN_ENABLED=true
CUSTOMER_ACCOUNTS=client_a=replace-with-access-code,client_b=replace-with-access-code
GUEST_LOGIN_ENABLED=true
```

Do not commit `.env.local`. It is ignored by `.gitignore`.

Start the backend:

```powershell
python -m rag_server.main
```

Or run it with Uvicorn:

```powershell
uvicorn rag_server.main:app --host 0.0.0.0 --port 8765
```

If `.env.local` changes, restart the backend. Environment settings are loaded at process startup.

## Backend Authentication

The backend uses two layers of authentication.

Service-level authentication:

```http
Authorization: Bearer <RAG_AUTH_TOKEN>
```

App-user authentication:

```http
X-App-Session: <app_session_token>
```

`X-App-Session` can be issued by:

- Huawei login: `/v1/auth/huawei/login`
- Customer login: `/v1/auth/customer/login`
- Guest login: `/v1/auth/guest/login`

Customer accounts are configured by `CUSTOMER_ACCOUNTS`. Each customer receives a stable identity such as:

```text
customer:client_a
```

Uploaded private documents are tagged with that identity in ChromaDB metadata. This keeps normal users separated from each other, but it is not end-to-end encryption. A server administrator can still inspect uploaded content from backend storage or runtime memory.

## Backend API Summary

Public endpoints:

```text
GET /
GET /v1/rag/health
```

Authenticated endpoints:

```text
POST /v1/auth/huawei/login
POST /v1/auth/customer/login
POST /v1/auth/guest/login
GET  /v1/rag/documents
GET  /v1/rag/documents/{doc_id}/chunks
POST /v1/rag/upload
POST /v1/rag/upload/text
POST /v1/rag/search
POST /v1/rag/query
```

Document upload notes:

- `/v1/rag/upload` accepts raw file bytes and extracts text on the backend.
- `/v1/rag/upload/text` expects already extracted plain text in JSON.
- Backend extraction currently supports `.txt`, `.md`, `.markdown`, `.pdf`, and `.docx`.
- Binary files should not be sent through `/v1/rag/upload/text`.

## Storage and Privacy

Current storage model:

- ChromaDB local persistence under `rag_server/chroma_data/`
- User identity stored as document metadata, for example `owner_user_id=customer:client_a`
- App session tokens stored locally in HarmonyOS preferences
- No MySQL user table
- No end-to-end encryption

To reset the local vector store, stop the backend and delete:

```powershell
Remove-Item -Recurse -Force rag_server\chroma_data
```

The built-in knowledge index will be rebuilt when the backend starts again. User uploads in that local store will be removed.

## Security Notes

- Use strong, unique `RAG_AUTH_TOKEN`, `APP_SESSION_SECRET`, and customer access codes.
- Do not use weak customer access codes in production.
- Put the backend behind HTTPS and a reverse proxy or firewall before exposing it publicly.
- Consider blocking unknown paths at the reverse proxy layer to reduce scanner traffic.
- Do not commit signing keys, certificates, profiles, `.env.local`, API tokens, or private knowledge files.

## Building the HarmonyOS App

Open the repository in DevEco Studio, sync dependencies, and build the `entry` module.

The app depends on the local Markdown HAR module:

```text
entry/oh-package.json5
markdown/
```

The current app metadata is:

```text
bundleName: com.wingsluo.compass
versionName: 2.0.0
versionCode: 2000000
minAPIVersion: 23
```

## Current Limitations

- Per-document delete is not currently exposed as a backend API.
- Server-side document storage is visible to the backend operator.
- Unknown public scanner traffic may appear as many `401 Unauthorized` logs because the backend protects non-public paths with the service token middleware.
