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
  /** False when the owner turned off embedding; search hits then link to youtube.com. */
  embeddable: boolean;
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
  /** youtube.com at this timestamp; used only when the video can't be embedded. */
  url: string;
  embeddable: boolean;
}

export interface SearchResponse {
  query: string;
  hits: SearchHit[];
}

export type UserRole = "student" | "professor";

/** GET /ingest/me: the signed-in user (ADR 0002). */
export interface Me {
  id: number;
  email: string;
  name: string | null;
  role: UserRole;
  is_admin: boolean;
}

/** A row on the admin page; "invited" means they haven't signed in yet. */
export interface AdminUser extends Me {
  is_active: boolean;
  status: "invited" | "active" | "disabled";
  created_at: string;
}

export interface InviteResult {
  created: AdminUser[];
  already_exists: string[];
}

export interface UserChanges {
  role?: UserRole;
  is_active?: boolean;
  is_admin?: boolean;
}
