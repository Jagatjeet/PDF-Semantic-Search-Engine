from sentence_transformers import SentenceTransformer

_model: SentenceTransformer | None = None

HF_MODEL = "nomic-ai/nomic-embed-text-v1.5"

# nomic-embed-text-v1.5 uses task prefixes instead of separate task_type params
_DOC_PREFIX = "search_document: "
_QUERY_PREFIX = "search_query: "


def _get_model() -> SentenceTransformer:
    global _model
    if _model is None:
        _model = SentenceTransformer(HF_MODEL, trust_remote_code=True)
    return _model


def get_embeddings(texts: list[str]) -> list[list[float]]:
    """Embed a list of document strings using local nomic-embed-text-v1.5."""
    prefixed = [_DOC_PREFIX + t for t in texts]
    model = _get_model()
    vectors = model.encode(prefixed, normalize_embeddings=True)
    return vectors.tolist()


def get_query_embedding(query: str) -> list[float]:
    """Embed a single query string using local nomic-embed-text-v1.5."""
    model = _get_model()
    vector = model.encode([_QUERY_PREFIX + query], normalize_embeddings=True)
    return vector[0].tolist()
