// Shapes returned by the APIs; see services/README.md.

export interface Course {
  id: number;
  code: string;
  title: string;
  professor: string | null;
  lecture_count: number;
}

export interface MyCourse {
  id: number;
  code: string;
  title: string;
  created_at: string;
  lecture_count: number;
}

export interface IndexedLecture {
  id: number;
  video_id: string;
  title: string;
  indexed_at: string;
}

export interface IngestLecture {
  id: number;
  course_id: number;
  youtube_video_id: string;
  title: string;
  caption_language: string | null;
  status: "pending" | "indexed" | "failed";
  error: string | null;
  indexed_at: string | null;
  created_at: string;
  segment_count: number;
}

export interface SearchHit {
  lecture_id: number;
  lecture_title: string;
  video_id: string;
  start_seconds: number;
  timestamp: string;
  /** Caption text, HTML-escaped by the server, with matches wrapped in <mark>. */
  excerpt_html: string;
  url: string;
}

export interface SearchResponse {
  query: string;
  hits: SearchHit[];
}
