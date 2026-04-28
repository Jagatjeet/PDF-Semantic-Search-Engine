import axios from "axios";

const API = process.env.REACT_APP_API_URL || "";

export async function uploadPdfs(files: File[]) {
  const form = new FormData();
  files.forEach((f) => form.append("files", f));
  const res = await axios.post(`${API}/upload`, form, {
    headers: { "Content-Type": "multipart/form-data" },
  });
  return res.data;
}

export async function listDocuments(): Promise<string[]> {
  const res = await axios.get(`${API}/documents`);
  return res.data.documents;
}

export async function search(
  query: string,
  topK: number,
  filenameFilter: string | null,
  generateAnswer: boolean
) {
  const res = await axios.post(`${API}/search`, {
    query,
    top_k: topK,
    filename_filter: filenameFilter || null,
    generate_answer: generateAnswer,
  });
  return res.data;
}

export async function* searchStream(
  query: string,
  topK: number,
  filenameFilter: string | null,
  generateAnswer: boolean
): AsyncGenerator<{ type: string; [key: string]: any }> {
  const res = await fetch(`${API}/search/stream`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query,
      top_k: topK,
      filename_filter: filenameFilter || null,
      generate_answer: generateAnswer,
    }),
  });
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  const reader = res.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop()!;
    for (const line of lines) {
      if (line.startsWith("data: ")) {
        yield JSON.parse(line.slice(6));
      }
    }
  }
}
