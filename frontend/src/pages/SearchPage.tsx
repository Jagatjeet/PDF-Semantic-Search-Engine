import React, { useState, useEffect } from "react";
import { searchStream, listDocuments } from "../api";

interface Chunk {
  score: number;
  filename: string;
  page: number;
  chunk_index: number;
  text: string;
}

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const [topK, setTopK] = useState(1);
  const [filenameFilter, setFilenameFilter] = useState("");
  const [generateAnswer, setGenerateAnswer] = useState(true);
  const [documents, setDocuments] = useState<string[]>([]);
  const [chunks, setChunks] = useState<Chunk[]>([]);
  const [answer, setAnswer] = useState<string>("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listDocuments()
      .then(setDocuments)
      .catch(() => {});
  }, []);

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setError(null);
    setChunks([]);
    setAnswer("");
    try {
      for await (const event of searchStream(query, topK, filenameFilter || null, generateAnswer)) {
        if (event.type === "chunks") {
          setChunks(event.chunks);
        } else if (event.type === "token") {
          setAnswer((prev) => prev + event.text);
        } else if (event.type === "done") {
          break;
        }
      }
    } catch (e: any) {
      setError(e?.message || "Search failed. Is the backend running?");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="page">
      <h1>Search PDFs</h1>

      <form onSubmit={handleSearch}>
        <div className="search-bar">
          <input
            type="text"
            placeholder="Ask a question about your documents…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <button className="btn" type="submit" disabled={loading || !query.trim()}>
            {loading ? "Searching…" : "Search"}
          </button>
        </div>

        <div className="filter-row">
          <label style={{ fontSize: "0.9rem" }}>
            <strong>Filter by file:</strong>
          </label>
          <select
            value={filenameFilter}
            onChange={(e) => setFilenameFilter(e.target.value)}
          >
            <option value="">All documents</option>
            {documents.map((d) => (
              <option key={d} value={d}>{d}</option>
            ))}
          </select>

          <label style={{ fontSize: "0.9rem" }}>
            <strong>Top K:</strong>
          </label>
          <select
            value={topK}
            onChange={(e) => setTopK(Number(e.target.value))}
          >
            {[1, 3, 5, 8].map((n) => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>

          <label style={{ fontSize: "0.9rem", display: "flex", alignItems: "center", gap: "0.4rem" }}>
            <input
              type="checkbox"
              checked={generateAnswer}
              onChange={(e) => setGenerateAnswer(e.target.checked)}
            />
            Generate AI answer
          </label>
        </div>
      </form>

      {error && <div className="error">{error}</div>}
      {loading && !answer && <div className="spinner">Searching…</div>}

      {(answer || chunks.length > 0) && (
        <>
          {generateAnswer && (
            <div className="answer-box">
              <h3>AI Answer</h3>
              <p>{answer}{loading && <span className="cursor">▌</span>}</p>
            </div>
          )}

          {chunks.length === 0 ? (
            <p style={{ color: "#718096" }}>No matching chunks found.</p>
          ) : (
            <div className="chunk-list">
              {chunks.map((c, i) => (
                <div className="chunk-card" key={i}>
                  <div className="chunk-meta">
                    <strong>{c.filename}</strong> · Page {c.page}
                    <span className="score-badge">
                      score {(c.score * 100).toFixed(1)}%
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
