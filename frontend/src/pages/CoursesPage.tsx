import { useEffect, useState } from "react";
import { Link } from "react-router";
import { useApi } from "../api/ApiContext";
import type { Course } from "../api/types";
import { ErrorMessage } from "../components/ErrorMessage";

export function CoursesPage() {
  const { api } = useApi();
  const [courses, setCourses] = useState<Course[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    api.listCourses().then(setCourses, setError);
  }, [api]);

  return (
    <section>
      <h1>Courses</h1>
      <ErrorMessage error={error} />
      {courses === null && !error && <p className="muted">Loading…</p>}
      {courses?.length === 0 && <p className="muted">No courses yet.</p>}
      <ul className="cards">
        {courses?.map((course) => (
          <li key={course.id} className="card">
            <Link to={`/courses/${course.id}`}>
              <strong>{course.code}</strong> {course.title}
            </Link>
            <p className="muted">
              {course.professor ?? "Unknown professor"} · {course.lecture_count} lecture
              {course.lecture_count === 1 ? "" : "s"} indexed
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}
