# Repository Security Audit

Audit date: 2026-06-15

## Never Commit

### Credentials and signing material

- Root `build-profile.json5`
- `AppScope/resources/rawfile/agconnect-services.json`
- `rag_server/.env.local`
- `*.p12`, `*.p7b`, `*.cer`, `*.csr`, `*.pem`, `*.key`

### Private feng shui material

- `entry/src/main/resources/rawfile/knowledge_*.txt`
- `entry/src/main/ets/common/CompassConstants.ets`
- `entry/src/main/ets/model/DirectionInfo.ets`
- Core compass/chart calculation and rendering files listed in `.gitignore`
- `rag_server/chroma_data/`, because vector databases can retain source knowledge

### Local-only artifacts

- `.codex-review/`
- Python bytecode and `__pycache__/`
- Personal notes, interview documents, and local SDK instructions

## Exposed Values Found in Previous History

- DeepSeek API keys
- Static RAG bearer token
- HarmonyOS signing key/store passwords
- Huawei AG Connect client secrets and API keys

History rewriting does not revoke credentials. Rotate all exposed values in their
respective consoles and generate new signing material if the private signing key
may have been downloaded from the repository.
