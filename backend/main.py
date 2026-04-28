from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import json
import vector_store
import pdf_parser
import embeddings
import llm

app = FastAPI(title="PDF Semantic Search API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup():
    vector_store.ensure_collection()
    llm.wait_for_model()


# ---------------------------------------------------------------------------
# Upload endpoint
# ---------------------------------------------------------------------------

@app.post("/upload", summary="Upload one or more PDF files and index them")
async def upload_pdfs(files: list[UploadFile] = File(...)):
    results = []
    for file in files:
        if not file.filename.lower().endswith(".pdf"):
            raise HTTPException(status_code=400, detail=f"{file.filename} is not a PDF")
        pdf_bytes = await file.read()
        chunks = pdf_parser.extract_chunks(pdf_bytes, file.filename)
        if not chunks:
            results.append({"filename": file.filename, "chunks": 0, "status": "empty"})
            continue

        texts = [c["text"] for c in chunks]
        vectors = embeddings.get_embeddings(texts)

        points = [
            {
                "id": chunks[i]["id"],
                "vector": vectors[i],
                "payload": {
                    "filename": chunks[i]["filename"],
                    "page": chunks[i]["page"],
                    "chunk_index": chunks[i]["chunk_index"],
                    "text": chunks[i]["text"],
                },
            }
            for i in range(len(chunks))
        ]
        vector_store.upsert_chunks(points)
        results.append(
            {"filename": file.filename, "chunks": len(chunks), "status": "indexed"}
        )
    return {"results": results}


# ---------------------------------------------------------------------------
# Documents list endpoint
# ---------------------------------------------------------------------------

@app.get("/documents", summary="List all indexed PDF filenames")
def list_documents():
    return {"documents": vector_store.list_documents()}


# ---------------------------------------------------------------------------
# Search endpoint
# ---------------------------------------------------------------------------

class SearchRequest(BaseModel):
    query: str
    top_k: int = 1
    filename_filter: str | None = None
    generate_answer: bool = True


@app.post("/search", summary="Semantic search over indexed PDFs")
def search(request: SearchRequest):
    if not request.query.strip():
        raise HTTPException(status_code=400, detail="Query cannot be empty")

    query_vector = embeddings.get_query_embedding(request.query)
    chunks = vector_store.search(
        query_vector,
        top_k=request.top_k,
        filename_filter=request.filename_filter,
    )

    answer = None
    if request.generate_answer and chunks:
        answer = llm.generate_answer(request.query, chunks)

    return {"answer": answer, "chunks": chunks}


@app.post("/search/stream", summary="Semantic search with streaming AI answer")
def search_stream(request: SearchRequest):
    if not request.query.strip():
        raise HTTPException(status_code=400, detail="Query cannot be empty")

    query_vector = embeddings.get_query_embedding(request.query)
    chunks = vector_store.search(
        query_vector,
        top_k=request.top_k,
        filename_filter=request.filename_filter,
    )

    def event_stream():
        yield f"data: {json.dumps({'type': 'chunks', 'chunks': chunks})}\n\n"
        if request.generate_answer and chunks:
            for token in llm.stream_answer(request.query, chunks):
                yield f"data: {json.dumps({'type': 'token', 'text': token})}\n\n"
        yield f"data: {json.dumps({'type': 'done'})}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok"}
