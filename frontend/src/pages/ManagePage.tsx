import { useCallback, useEffect, useState } from "react";
import type { FormEvent } from "react";
import { useApi } from "../api/ApiContext";
import type { IndexedLecture, IngestLecture, MyCourse } from "../api/types";
import { useAuth } from "../auth/AuthContext";
import { ErrorMessage } from "../components/ErrorMessage";

export function ManagePage() {
  const { api, role } = useApi();
  const [courses, setCourses] = useState<MyCourse[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  const refresh = useCallback(() => api.myCourses().then(setCourses, setError), [api]);
  useEffect(() => {
    if (role === "professor") refresh();
  }, [role, refresh]);

  if (role === "student") return <p>Only professors can manage courses.</p>;

  return (
    <section>
      <h1>Manage courses</h1>
      <ErrorMessage error={error} />
      <NewCourseForm onCreated={refresh} />
      {courses?.map((course) => (
        <CourseCard key={course.id} course={course} onChange={refresh} />
      ))}
    </section>
  );
}

function NewCourseForm({ onCreated }: { onCreated: () => void }) {
  const { api } = useApi();
  const [code, setCode] = useState("");
  const [title, setTitle] = useState("");
  const [error, setError] = useState<unknown>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      await api.createCourse(code.trim(), title.trim());
      setCode("");
      setTitle("");
      setError(null);
      onCreated();
    } catch (e) {
      setError(e);
    }
  }

  return (
    <form onSubmit={submit} className="card row">
      <label>
        Code
        <input value={code} onChange={(e) => setCode(e.target.value)} required maxLength={32} />
      </label>
      <label>
        Title
        <input value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={200} />
      </label>
      <button type="submit">Create course</button>
      <ErrorMessage error={error} />
    </form>
  );
}

function CourseCard({ course, onChange }: { course: MyCourse; onChange: () => void }) {
  const { api } = useApi();
  const { requestYouTubeToken } = useAuth();
  const [lectures, setLectures] = useState<IndexedLecture[]>([]);
  const [video, setVideo] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<IngestLecture | null>(null);
  const [error, setError] = useState<unknown>(null);

  const loadLectures = useCallback(
    () => api.listLectures(course.id).then(setLectures, setError),
    [api, course.id],
  );
  useEffect(() => {
    loadLectures();
  }, [loadLectures]);

  async function register(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setResult(null);
    setError(null);
    try {
      // Opens Google's consent popup the first time; the token stays in memory.
      const youtubeToken = await requestYouTubeToken();
      setResult(await api.registerLecture(course.id, video.trim(), youtubeToken));
      setVideo("");
      loadLectures();
      onChange();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  async function remove(lectureId: number) {
    try {
      await api.deleteLecture(lectureId);
      loadLectures();
      onChange();
    } catch (e) {
      setError(e);
    }
  }

  return (
    <article className="card">
      <h2>
        {course.code} {course.title}
      </h2>
      <form onSubmit={register} className="row">
        <label>
          YouTube video URL or ID (from your channel, with YouTube auto-generated captions)
          <input value={video} onChange={(e) => setVideo(e.target.value)} required />
        </label>
        <button type="submit" disabled={busy}>
          {busy ? "Indexing…" : "Register lecture"}
        </button>
      </form>
      {result && (
        <p className="success" role="status">
          Indexed “{result.title}”: {result.segment_count} segments.
          {!result.embeddable &&
            " Embedding is turned off for this video in YouTube Studio, so search results open it on YouTube."}
        </p>
      )}
      <ErrorMessage error={error} />
      {lectures.length > 0 && (
        <ul className="lectures">
          {lectures.map((lecture) => (
            <li key={lecture.id}>
              <span>{lecture.title || lecture.video_id}</span>
              <button type="button" className="link" onClick={() => remove(lecture.id)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}
