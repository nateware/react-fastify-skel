const API_BASE = import.meta.env.VITE_API_URL || "";

export function apiUrl(path: string): string {
  return API_BASE ? `${API_BASE}${path}` : path;
}

export async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(apiUrl(path), {
    credentials: "include",
    ...options,
  });

  if (!response.ok) {
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}
