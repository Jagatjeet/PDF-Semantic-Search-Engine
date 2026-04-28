from qdrant_client import QdrantClient
from qdrant_client.http.models import (
    Distance,
    VectorParams,
    PointStruct,
    Filter,
    FieldCondition,
    MatchValue,
)
from config import QDRANT_HOST, QDRANT_PORT, QDRANT_COLLECTION, EMBEDDING_DIM

_client: QdrantClient | None = None


def get_client() -> QdrantClient:
    global _client
    if _client is None:
        _client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
    return _client


def ensure_collection() -> None:
    client = get_client()
    existing = [c.name for c in client.get_collections().collections]
    if QDRANT_COLLECTION not in existing:
        client.create_collection(
            collection_name=QDRANT_COLLECTION,
            vectors_config=VectorParams(size=EMBEDDING_DIM, distance=Distance.COSINE),
        )


def upsert_chunks(
    chunks: list[dict],  # each: {id, vector, payload}
) -> None:
    client = get_client()
    points = [
        PointStruct(id=c["id"], vector=c["vector"], payload=c["payload"])
        for c in chunks
    ]
    client.upsert(collection_name=QDRANT_COLLECTION, points=points)


def search(
    query_vector: list[float],
    top_k: int = 5,
    filename_filter: str | None = None,
) -> list[dict]:
    client = get_client()
    query_filter = None
    if filename_filter:
        query_filter = Filter(
            must=[
                FieldCondition(
                    key="filename",
                    match=MatchValue(value=filename_filter),
                )
            ]
        )
    results = client.search(
        collection_name=QDRANT_COLLECTION,
        query_vector=query_vector,
        limit=top_k,
        query_filter=query_filter,
        with_payload=True,
    )
    return [
        {
            "score": r.score,
            "filename": r.payload.get("filename"),
            "page": r.payload.get("page"),
            "chunk_index": r.payload.get("chunk_index"),
            "text": r.payload.get("text"),
        }
        for r in results
    ]


def list_documents() -> list[str]:
    """Return distinct filenames stored in the collection."""
    client = get_client()
    ensure_collection()
    filenames: set[str] = set()
    offset = None
    while True:
        records, offset = client.scroll(
            collection_name=QDRANT_COLLECTION,
            limit=100,
            offset=offset,
            with_payload=True,
            with_vectors=False,
        )
        for r in records:
            if r.payload and "filename" in r.payload:
                filenames.add(r.payload["filename"])
        if offset is None:
            break
    return sorted(filenames)
