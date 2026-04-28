import json
import time
from typing import Iterator
import httpx
from config import OLLAMA_HOST, OLLAMA_MODEL


def wait_for_model(retries: int = 40, delay: int = 15) -> None:
    """Block until the configured model appears in Ollama's model list."""
    for _ in range(retries):
        try:
            r = httpx.get(f"{OLLAMA_HOST}/api/tags", timeout=5.0)
            if r.status_code == 200:
                names = [m.get("name", "") for m in r.json().get("models", [])]
                if any(OLLAMA_MODEL in n for n in names):
                    return
        except Exception:
            pass
        time.sleep(delay)
    raise RuntimeError(f"Model '{OLLAMA_MODEL}' did not become available after waiting.")


SYSTEM_PROMPT = (
    "You are a helpful assistant that answers questions based strictly on the "
    "provided document excerpts. If the answer cannot be found in the excerpts, "
    "say so clearly. Do not fabricate information."
)


MAX_CONTEXT_CHARS = 1500  # keep prompt short for CPU inference


def build_context(chunks: list[dict]) -> str:
    parts = []
    total = 0
    for c in chunks:
        snippet = c['text'][:400]  # truncate each chunk
        entry = f"[File: {c['filename']}, Page {c['page']}]\n{snippet}"
        if total + len(entry) > MAX_CONTEXT_CHARS:
            break
        parts.append(entry)
        total += len(entry)
    return "\n\n---\n\n".join(parts)


def generate_answer(query: str, chunks: list[dict]) -> str:
    context = build_context(chunks)
    response = httpx.post(
        f"{OLLAMA_HOST}/api/chat",
        json={
            "model": OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"Document excerpts:\n{context}\n\nQuestion: {query}"},
            ],
            "stream": False,
            "options": {"num_predict": 256, "temperature": 0.1},
        },
        timeout=300.0,
    )
    response.raise_for_status()
    return response.json().get("message", {}).get("content", "").strip()


def stream_answer(query: str, chunks: list[dict]) -> Iterator[str]:
    context = build_context(chunks)
    with httpx.stream(
        "POST",
        f"{OLLAMA_HOST}/api/chat",
        json={
            "model": OLLAMA_MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"Document excerpts:\n{context}\n\nQuestion: {query}"},
            ],
            "stream": True,
            "options": {"num_predict": 256, "temperature": 0.1},
        },
        timeout=300.0,
    ) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if line:
                data = json.loads(line)
                token = data.get("message", {}).get("content", "")
                if token:
                    yield token
                if data.get("done"):
                    break
                    yield token
                if data.get("done"):
                    break
