import React, { useState, useCallback } from "react";
import { useDropzone } from "react-dropzone";
import { uploadPdfs } from "../api";

interface UploadResult {
  filename: string;
  chunks: number;
  status: "indexed" | "empty" | "pending";
}

export default function UploadPage() {
  const [files, setFiles] = useState<File[]>([]);
  const [results, setResults] = useState<UploadResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onDrop = useCallback((accepted: File[]) => {
    setFiles((prev) => {
      const names = new Set(prev.map((f) => f.name));
      return [...prev, ...accepted.filter((f) => !names.has(f.name))];
    });
    setResults([]);
    setError(null);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { "application/pdf": [".pdf"] },
    multiple: true,
  });

  const handleUpload = async () => {
    if (files.length === 0) return;
    setLoading(true);
    setError(null);
    try {
      const data = await uploadPdfs(files);
      setResults(data.results);
      setFiles([]);
    } catch (e: any) {
      setError(e?.response?.data?.detail || "Upload failed. Is the backend running?");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="page">
      <h1>Upload PDFs</h1>

      <div {...getRootProps()} className={`dropzone${isDragActive ? " active" : ""}`}>
        <input {...getInputProps()} />
        <svg width="48" height="48" fill="none" stroke="#a0aec0" strokeWidth="1.5" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" d="M12 16v-8m0 0-3 3m3-3 3 3M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1" />
        </svg>
        <p>{isDragActive ? "Drop PDFs here…" : "Drag & drop PDF files here, or click to select"}</p>
      </div>

      {files.length > 0 && (
        <ul className="file-list" style={{ marginTop: "1rem" }}>
          {files.map((f) => (
            <li key={f.name}>
              <span>{f.name}</span>
              <span className="badge pending">ready</span>
            </li>
          ))}
        </ul>
      )}

      {error && <div className="error" style={{ marginTop: "1rem" }}>{error}</div>}

      <button
        className="btn"
        onClick={handleUpload}
        disabled={loading || files.length === 0}
        style={{ display: "block" }}
      >
        {loading ? "Indexing…" : `Index ${files.length} PDF${files.length !== 1 ? "s" : ""}`}
      </button>

      {results.length > 0 && (
        <>
          <h2 style={{ marginTop: "2rem", marginBottom: "0.8rem", fontSize: "1rem" }}>
            Results
          </h2>
          <ul className="file-list">
            {results.map((r) => (
              <li key={r.filename}>
                <span>{r.filename}</span>
                <span>
                  {r.status === "indexed" && (
                    <span className="badge indexed">{r.chunks} chunks indexed</span>
                  )}
                  {r.status === "empty" && (
                    <span className="badge empty">empty / no text extracted</span>
                  )}
                </span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
