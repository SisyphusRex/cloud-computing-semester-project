import type {
  Course,
  IndexedLecture,
  IngestLecture,
  MyCourse,
  SearchResponse,
} from "./types";

/** An error response from the APIs ({"error", "message", ...}) or a network failure. */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(status: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

interface ClientOptions {
  /** Prefix for every path; "" means same origin. */
  base: string;
  /** The current Google ID token (or dev token), read on every request. */
  getToken: () => string | null;
  /** Called on 401, i.e. the ID token expired or was rejected. */
  onUnauthorized?: () => void;
}

interface RequestOptions {
  method?: string;
  body?: unknown;
  youtubeToken?: string;
}

export function createApi({ base, getToken, onUnauthorized }: ClientOptions) {
  async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
    const headers = new Headers();
    const token = getToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
    if (options.body !== undefined) headers.set("Content-Type", "application/json");
    if (options.youtubeToken) headers.set("X-YouTube-Token", options.youtubeToken);

    let response: Response;
    try {
      response = await fetch(`${base}${path}`, {
        method: options.method ?? "GET",
        headers,
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
      });
    } catch {
      throw new ApiError(0, "network_error", "Could not reach the server.");
    }

    if (response.status === 204) return undefined as T;
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      if (response.status === 401) onUnauthorized?.();
      throw new ApiError(
        response.status,
        body?.error ?? "http_error",
        body?.message || response.statusText || `Request failed (${response.status})`,
        body?.details,
      );
    }
    return body as T;
  }

  return {
    // Search API: any signed-in user.
    listCourses: () => request<{ courses: Course[] }>("/search/courses").then((r) => r.courses),
    listLectures: (courseId: number) =>
      request<{ lectures: IndexedLecture[] }>(`/search/courses/${courseId}/lectures`).then(
        (r) => r.lectures,
      ),
    search: (courseId: number, q: string, limit = 20) =>
      request<SearchResponse>(
        `/search/courses/${courseId}/segments?${new URLSearchParams({ q, limit: String(limit) })}`,
      ),

    // Ingest API: professors only (403 for students).
    myCourses: () => request<{ courses: MyCourse[] }>("/ingest/courses").then((r) => r.courses),
    createCourse: (code: string, title: string) =>
      request<MyCourse>("/ingest/courses", { method: "POST", body: { code, title } }),
    registerLecture: (courseId: number, video: string, youtubeToken: string) =>
      request<IngestLecture>(`/ingest/courses/${courseId}/lectures`, {
        method: "POST",
        body: { video },
        youtubeToken,
      }),
    getLecture: (lectureId: number) => request<IngestLecture>(`/ingest/lectures/${lectureId}`),
    deleteLecture: (lectureId: number) =>
      request<void>(`/ingest/lectures/${lectureId}`, { method: "DELETE" }),
  };
}

export type Api = ReturnType<typeof createApi>;
