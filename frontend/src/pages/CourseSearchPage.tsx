import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { Link, useParams, useSearchParams } from "react-router";
import { useApi } from "../api/ApiContext";
import type { Course, SearchHit, SearchResponse } from "../api/types";
import { ErrorMessage } from "../components/ErrorMessage";
import { Excerpt } from "../components/Excerpt";
import { VideoPlayer } from "../components/VideoPlayer";

interface SearchOutcome {
  key: string;
  response?: SearchResponse;
  error?: unknown;
}

export function CourseSearchPage() {
  const { api } = useApi();
  const courseId = Number(useParams().courseId);
  const [params, setParams] = useSearchParams();
  const query = params.get("q") ?? "";
  // The clip playing in the embedded player, also in the URL: ?q=…&v=<video id>&t=<seconds>.
  const videoId = params.get("v");
  const start = Math.max(0, Math.floor(Number(params.get("t")) || 0));

  const [course, setCourse] = useState<Course | null>(null);
  const [courseError, setCourseError] = useState<unknown>(null);
  const [draft, setDraft] = useState(query);
  // Each outcome remembers which search it answers; until the current one's
  // arrives, we're searching.
  const [outcome, setOutcome] = useState<SearchOutcome | null>(null);
  const searchKey = `${courseId}\n${query}`;

  useEffect(() => {
    api
      .listCourses()
      .then((courses) => setCourse(courses.find((c) => c.id === courseId) ?? null), setCourseError);
  }, [api, courseId]);

  // The query lives in the URL, so results can be bookmarked and shared.
  useEffect(() => {
    if (!query) return;
    let cancelled = false;
    api.search(courseId, query).then(
      (response) => !cancelled && setOutcome({ key: searchKey, response }),
      (error) => !cancelled && setOutcome({ key: searchKey, error }),
    );
    return () => {
      cancelled = true;
    };
  }, [api, courseId, query, searchKey]);

  const current = outcome?.key === searchKey ? outcome : null;
  const searching = query !== "" && current === null;
  const results = current?.response ?? null;
  const playingTitle = results?.hits.find((hit) => hit.video_id === videoId)?.lecture_title;

  function clipSearch(hit: SearchHit) {
    return `?${new URLSearchParams({ q: query, v: hit.video_id, t: String(hit.start_seconds) })}`;
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    if (draft.trim()) setParams({ q: draft.trim() });
  }

  return (
    <section>
      <p>
        <Link to="/">← All courses</Link>
      </p>
      <h1>{course ? `${course.code} ${course.title}` : "Course"}</h1>
      <form onSubmit={submit} className="search" role="search">
        <input
          aria-label="Search this course's lectures"
          placeholder='e.g. lambda calculus, "exact phrase", -exclude'
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" disabled={searching}>
          Search
        </button>
      </form>
      <ErrorMessage error={courseError ?? current?.error} />
      {videoId && (
        <VideoPlayer
          key={`${videoId}-${start}`}
          videoId={videoId}
          start={start}
          title={playingTitle ?? "Lecture video"}
        />
      )}
      {results && results.hits.length === 0 && (
        <p className="muted">No matches for “{results.query}”.</p>
      )}
      <ol className="hits">
        {results?.hits.map((hit) => {
          const playing = hit.video_id === videoId && hit.start_seconds === start;
          return (
            <li
              key={`${hit.lecture_id}-${hit.start_seconds}`}
              className="card"
              aria-current={playing || undefined}
            >
              <div className="hit-head">
                {hit.embeddable ? (
                  <Link to={{ search: clipSearch(hit) }} className="timestamp">
                    {hit.timestamp}
                  </Link>
                ) : (
                  // The professor turned off embedding for this video.
                  <a href={hit.url} target="_blank" rel="noopener noreferrer" className="timestamp">
                    {hit.timestamp} <span className="muted">↗ YouTube</span>
                  </a>
                )}
                <span>{hit.lecture_title}</span>
              </div>
              <Excerpt html={hit.excerpt_html} />
            </li>
          );
        })}
      </ol>
    </section>
  );
}
