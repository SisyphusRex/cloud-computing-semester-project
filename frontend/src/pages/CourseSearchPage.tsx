import { useEffect, useState } from "react";
import type { FormEvent } from "react";
import { Link, useParams, useSearchParams } from "react-router";
import { useApi } from "../api/ApiContext";
import type { Course, SearchResponse } from "../api/types";
import { ErrorMessage } from "../components/ErrorMessage";
import { Excerpt } from "../components/Excerpt";

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
      {results && results.hits.length === 0 && (
        <p className="muted">No matches for “{results.query}”.</p>
      )}
      <ol className="hits">
        {results?.hits.map((hit) => (
          <li key={`${hit.lecture_id}-${hit.start_seconds}`} className="card">
            <div className="hit-head">
              <a href={hit.url} target="_blank" rel="noopener noreferrer" className="timestamp">
                {hit.timestamp}
              </a>
              <span>{hit.lecture_title}</span>
            </div>
            <Excerpt html={hit.excerpt_html} />
          </li>
        ))}
      </ol>
    </section>
  );
}
