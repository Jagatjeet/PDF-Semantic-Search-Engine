import fitz  # PyMuPDF
import hashlib


CHUNK_SIZE = 500   # characters per chunk
CHUNK_OVERLAP = 100


def extract_chunks(pdf_bytes: bytes, filename: str) -> list[dict]:
    """
    Extract text chunks from a PDF.
    Returns list of dicts with keys: id, filename, page, chunk_index, text
    """
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        text = page.get_text("text")
        # Slide a window over the page text
        start = 0
        while start < len(text):
            end = start + CHUNK_SIZE
            chunk_text = text[start:end].strip()
            if chunk_text:
                uid = hashlib.sha256(
                    f"{filename}:{page_num}:{chunk_index}".encode()
                ).hexdigest()[:16]
                # Qdrant point IDs must be unsigned 64-bit ints or UUIDs; use int from hex
                point_id = int(uid, 16) % (2**63)
                chunks.append(
                    {
                        "id": point_id,
                        "filename": filename,
                        "page": page_num,
                        "chunk_index": chunk_index,
                        "text": chunk_text,
                    }
                )
                chunk_index += 1
            start += CHUNK_SIZE - CHUNK_OVERLAP

    doc.close()
    return chunks
