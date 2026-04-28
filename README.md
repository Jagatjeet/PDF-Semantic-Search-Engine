# PDF Semantic Search Engine

A full-stack application for semantic search over PDF documents, powered by:

- **Qdrant** — vector database
- **Nomic embed-text-v1.5** — best-in-class PDF embedding model (runs locally via HuggingFace, no API key needed)
- **Mistral 7B** (via Ollama) — open-source LLM for answer generation
- **FastAPI** — backend API
- **React** — frontend with Upload and Search pages
- **Azure Container Apps** — cloud deployment target

---

## Project Structure

```
.
├── backend/           FastAPI app (PDF parsing, embeddings, search, LLM)
├── frontend/          React app (Upload UI + Search UI)
├── infra/             Azure Bicep IaC
├── docker-compose.yml Local development
└── deploy.sh          Azure deployment script
```

---

## Quick Start (local)

### 1. Configure the backend
```bash
cp backend/.env.example backend/.env
# Only OLLAMA_MODEL and QDRANT settings need adjusting — no API keys required
```

### 2. Start everything
```bash
docker compose up --build
```

This will start:
- **Qdrant** on http://localhost:6333
- **Ollama** on http://localhost:11434 (and pull `mistral` automatically)
- **Backend API** on http://localhost:8000
- **Frontend** on http://localhost:3000

> **Note:** On the first `docker compose up --build`, the `nomic-embed-text-v1.5` model weights (~270 MB) are downloaded from HuggingFace and baked into the backend image. Subsequent builds use the Docker layer cache.

### 3. Use the app
- Open http://localhost:3000 — **Upload** page to index PDFs
- Click **Search** in the nav — **Search** page to query them

---

## API Reference

| Endpoint | Method | Description |
|---|---|---|
| `/upload` | POST | Upload and index PDF files |
| `/documents` | GET | List all indexed filenames |
| `/search` | POST | Semantic search with optional AI answer |
| `/search/stream` | POST | Semantic search with streaming SSE answer |
| `/health` | GET | Health check |

### Search request body
```json
{
  "query": "What is the refund policy?",
  "top_k": 5,
  "filename_filter": null,
  "generate_answer": true
}
```

---

## Deploy to Azure

### Prerequisites
- Azure CLI installed and logged in
- Docker installed
- An Azure Container Registry (ACR) created
- A Docker Hub account (free) — needed to authenticate image pulls and avoid rate limits

### Steps

```bash
# Create a resource group and ACR if you don't have them
az group create -n pdf-search-rg -l eastus2
az acr create -g pdf-search-rg -n mypdfacr --sku Basic

# Deploy
export ACR_NAME=mypdfacr
export RESOURCE_GROUP=pdf-search-rg
export DOCKERHUB_USERNAME=myuser
export DOCKERHUB_PASSWORD=mytoken   # Docker Hub PAT with read-only scope
bash deploy.sh
```

The script will:
1. Import base images into your ACR (authenticated, avoids Docker Hub rate limits)
2. Build and push Docker images to your ACR via ACR Tasks
3. Deploy Qdrant, Ollama, Backend, and Frontend as Azure Container Apps
4. Print the public URLs for the frontend and backend

> **Note:** On the first deploy, Ollama pulls the Mistral 7B model (~4 GB) inside the container. The backend may take a few minutes to become healthy while it waits for Ollama to be ready.

### Outputs

After a successful deployment, the script prints:

| Output | Description |
|---|---|
| `frontendUrl` | Public URL for the React UI |
| `backendUrl` | Public URL for the FastAPI backend (direct access) |
| `ollamaUrl` | Public URL for the Ollama API |

---

## Architecture

```
Browser
  │
  ├── GET /           → React Upload Page
  └── GET /search     → React Search Page
        │
        │ /api/*  (proxied by nginx)
        ▼
    FastAPI Backend
      ├── PDF Parser (PyMuPDF)  → text chunks
      ├── Nomic embed-text-v1.5 → vectors (local, HuggingFace)
      ├── Qdrant                → vector store
      └── Ollama / Mistral      → AI answer generation
```
