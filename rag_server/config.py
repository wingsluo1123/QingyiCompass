"""
Compass RAG Server — 全局配置

所有可调参数集中于此，避免散落在各模块中。
"""

from __future__ import annotations

import os
from pathlib import Path

# ============================================================
# 项目路径
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_FILE_DIR = PROJECT_ROOT / "entry" / "src" / "main" / "resources" / "rawfile"
CHROMA_PERSIST_DIR = Path(__file__).resolve().parent / "chroma_data"
LOCAL_ENV_FILE = Path(__file__).resolve().parent / ".env.local"


def _load_local_env() -> None:
    if not LOCAL_ENV_FILE.exists():
        return
    for raw_line in LOCAL_ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_local_env()

# ============================================================
# 知识库文件列表
# ============================================================

KNOWLEDGE_FILES: list[str] = [
    "knowledge_bazhai.txt",
    "knowledge_dili.txt",
]

# 文件名 → 经典名称映射
FILE_TITLE_MAP: dict[str, str] = {
    "knowledge_bazhai.txt": "八宅明镜",
    "knowledge_dili.txt": "地理五诀",
}


# ============================================================
# 文本分块
# ============================================================

# 每个 chunk 的目标字符数（中文约 2 字符 = 1 token 估算）
CHUNK_SIZE: int = 400
# 相邻 chunk 的重叠字符数（用于保留上下文连续性）
CHUNK_OVERLAP: int = 50

# ============================================================
# Embedding 模型
# ============================================================

# 中文语义匹配效果好、体积小（~400MB）、推理快
EMBEDDING_MODEL_NAME: str = os.getenv(
    "EMBEDDING_MODEL",
    "shibing624/text2vec-base-chinese",
)

# ============================================================
# 检索参数
# ============================================================

# 默认返回 Top-K
DEFAULT_TOP_K: int = 5
# BM25 参数
BM25_K1: float = 1.5
BM25_B: float = 0.75
# 混合检索中向量相似度的权重（0-1），越大向量检索越重要
HYBRID_VECTOR_WEIGHT: float = 0.6

# ============================================================
# 服务端
# ============================================================

SERVER_HOST: str = os.getenv("RAG_HOST", "0.0.0.0")
SERVER_PORT: int = int(os.getenv("RAG_PORT", "8765"))
RAG_AUTH_TOKEN: str = os.getenv("RAG_AUTH_TOKEN", "")

# Huawei Account Kit / app session
HUAWEI_CLIENT_ID: str = os.getenv("HUAWEI_CLIENT_ID", "")
HUAWEI_CLIENT_SECRET: str = os.getenv("HUAWEI_CLIENT_SECRET", "")
HUAWEI_REDIRECT_URI: str = os.getenv("HUAWEI_REDIRECT_URI", "")
HUAWEI_VERIFY_AUTH_CODE: bool = os.getenv("HUAWEI_VERIFY_AUTH_CODE", "false").lower() == "true"
APP_SESSION_SECRET: str = os.getenv("APP_SESSION_SECRET", RAG_AUTH_TOKEN or "compass-local-session-secret")
APP_SESSION_TTL_SECONDS: int = int(os.getenv("APP_SESSION_TTL_SECONDS", str(60 * 60 * 24 * 30)))
DEFAULT_ACCOUNT_LEVEL: int = int(os.getenv("DEFAULT_ACCOUNT_LEVEL", "1"))
LEVEL3_UNION_IDS: set[str] = {
    item.strip() for item in os.getenv("LEVEL3_UNION_IDS", "").split(",") if item.strip()
}
LEVEL3_OPEN_IDS: set[str] = {
    item.strip() for item in os.getenv("LEVEL3_OPEN_IDS", "").split(",") if item.strip()
}

# ============================================================
# 风水关键词列表（与端侧 KnowledgeService.extractKeywords 保持一致）
# ============================================================

FENGSHUI_KEYWORDS: list[str] = [
    "八宅明镜", "地理五诀", "八卦", "九星", "贪狼", "巨门", "禄存", "文曲",
    "廉贞", "武曲", "破军", "左辅", "右弼", "生气", "天医", "延年",
    "绝命", "五鬼", "六煞", "祸害", "坎宅", "离宅", "震宅", "巽宅",
    "坤宅", "艮宅", "乾宅", "兑宅", "龙脉", "穴位", "青龙", "白虎",
    "朱雀", "玄武", "明堂", "案山", "朝山", "天门", "地户", "二十四山",
    "正东", "正南", "正西", "正北", "东南", "东北", "西南", "西北",
    "属木", "属火", "属土", "属金", "属水", "五行", "东西四宅", "东四命",
    "西四命", "立向", "砂法", "水法", "穴法", "龙法", "向法",
    "安床", "开门", "安灶", "选宅", "阳宅", "阴宅", "坐向", "朝向",
]
