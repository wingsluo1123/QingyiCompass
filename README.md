# Qingyi Compass

Qingyi Compass is a HarmonyOS compass application focused on traditional compass and Zi Wei chart workflows.

## Important Branch Notice

This `main` branch is an older offline-oriented release branch.

The repository still contains source files for AI chat, RAG knowledge-base pages, Huawei login, and the Python RAG backend, but those cloud/backend features are not fully enabled in the current `main` app configuration.

Current branch status:

- App version: `1.2.0`
- Bundle name: `com.wingsluo.compass`
- Minimum API: HarmonyOS API 23
- Main enabled app tabs: Compass, Star Chart, My/About
- Network permission is commented out in `entry/src/main/module.json5`
- Huawei Account Kit `client_id` metadata is commented out in `entry/src/main/module.json5`
- `fluid-markdown` is commented out in `entry/oh-package.json5`
- Knowledge-base and AI tabs are commented out in `entry/src/main/ets/pages/Index.ets`
- Account and personal knowledge-base UI blocks are commented out in `entry/src/main/ets/pages/About.ets`

In short: this branch should be treated as the offline app baseline. Do not assume it has the full backend/customer-account/RAG behavior from newer backend-enabled work.

## Enabled Features In This Branch

- Compass page with custom Canvas rendering
- Sensor-driven direction display
- Zi Wei chart page
- My/About page with app information and contact entries
- Dark mode toggle with persisted preference
- HDS-style bottom tab navigation

## Disabled Or Partially Present Features

The following features have code in the repository, but are not fully active in this branch:

- AI chat page
- RAG knowledge-base page
- Remote document upload
- Huawei Account Kit login entry
- Customer-account login
- Guest login fallback
- Third-party Markdown rendering through `fluid-markdown`

Some of these files may compile only after their related permissions, dependencies, and page registrations are restored.

## Requirements

- HarmonyOS API 6.1.0 (API 23) or later
- DevEco Studio compatible with HarmonyOS API 23
- Python 3.10+ only if you intentionally run the optional RAG backend

## App Structure

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
      About.ets
      AppAboutPage.ets
      AiChatPage.ets              # present, not enabled in main tabs
      KnowledgePage.ets           # present, not enabled in main tabs
      KnowledgeDetailPage.ets     # present, not enabled in main pages
      LoginPage.ets               # present, not enabled from About page
    service/
      ThemeService.ets
      AiService.ets
      ApiConfigService.ets
      AuthService.ets
      RAGService.ets
      KnowledgeService.ets
markdown/
rag_server/
```

Enabled pages are registered in:

```text
entry/src/main/resources/base/profile/main_pages.json
```

Current enabled page list:

```text
pages/Index
pages/Chart
pages/CompassPage
pages/Horse
pages/AppAboutPage
```

## Optional RAG Backend

The Python backend still exists under:

```text
rag_server/
```

It uses:

- FastAPI
- ChromaDB
- `sentence-transformers`
- `rank-bm25`
- SSE streaming

It does not use MySQL. Local vector data is stored under:

```text
rag_server/chroma_data/
```

Backend dependencies are listed in:

```text
rag_server/requirements.txt
```

Start command:

```powershell
python -m rag_server.main
```

or:

```powershell
uvicorn rag_server.main:app --host 0.0.0.0 --port 8765
```

Backend environment values can be loaded from:

```text
rag_server/.env.local
```

Do not commit `.env.local`.

## Current Backend Limitations On `main`

This branch's backend is not the latest full customer-account backend.

The current `main` backend includes:

- RAG health/search/query endpoints
- ChromaDB persistence
- Huawei app-session endpoint
- User document upload endpoints
- Service-token protection through `RAG_AUTH_TOKEN`

The current `main` backend does not include the newer customer-account and guest-login endpoints unless those changes are merged from the backend-enabled branch.

## Re-enabling AI, RAG, And Login Features

To turn this branch back into a network/backend-enabled app, review and restore these areas carefully:

1. `entry/src/main/module.json5`
   - Restore `ohos.permission.INTERNET`
   - Restore Huawei Account Kit `client_id` metadata if Huawei login is needed

2. `entry/oh-package.json5`
   - Restore the local Markdown dependency:

   ```json5
   "fluid-markdown": "file:../markdown"
   ```

3. `entry/src/main/resources/base/profile/main_pages.json`
   - Register pages that should be routable again, such as AI, knowledge-base, detail, and login pages.

4. `entry/src/main/ets/pages/Index.ets`
   - Restore `KnowledgePage` import and tab
   - Restore `AiChatPage` import and tab if AI is enabled

5. `entry/src/main/ets/pages/About.ets`
   - Restore the account and personal knowledge-base card if login/account features are enabled.

6. Backend branch parity
   - If customer-account login or guest login is required, merge the backend-enabled implementation that adds `/v1/auth/customer/login` and `/v1/auth/guest/login`.

7. App review and filing implications
   - Re-enabling cloud AI, RAG, document upload, or account features changes the app from offline-only behavior to network-service behavior. Review app filing, privacy disclosure, and Huawei review requirements before release.

## Upload Format Notes

The backend raw upload path can extract text from:

- `.txt`
- `.md`
- `.markdown`
- `.pdf`
- `.docx`

The `/v1/rag/upload/text` endpoint expects already extracted plain text. Do not send binary files to `/v1/rag/upload/text`.

## Security Notes

- Do not commit signing material, local profiles, API tokens, RAG tokens, or `.env.local`.
- Do not commit private knowledge files or generated vector databases.
- `build-profile.json5` may contain local signing paths and encrypted signing fields. Keep it out of public repositories if it contains project-specific signing material.
- `rag_server/chroma_data/` can retain source text and should not be published.

## Known README Drift Fixed Here

The old README was out of date because it:

- Described API 20 / HarmonyOS 6.0 while the current config targets API 23 / HarmonyOS 6.1
- Claimed cloud AI was a normal enabled feature even though the offline branch has network permission commented out
- Did not explain that AI, RAG, account login, and knowledge-base pages are present but disabled
- Did not mention the optional Python RAG backend
- Did not mention ChromaDB storage
- Did not mention that this branch is an older offline baseline
