import { useCallback, useEffect, useState } from "react";
import type { FormEvent } from "react";
import { useApi } from "../api/ApiContext";
import type { AdminUser, Course, InviteResult, Me, UserChanges, UserRole } from "../api/types";
import { ErrorMessage } from "../components/ErrorMessage";

/**
 * Invite users, manage their roles, and delete users and courses (ADRs 0002,
 * 0003 and 0006). Admins manage everyone, but can only change their own role,
 * not disable or delete themselves or drop their own admin flag. The API
 * enforces the same rules.
 */
export function AdminPage() {
  const { api, me } = useApi();
  const [users, setUsers] = useState<AdminUser[] | null>(null);
  const [courses, setCourses] = useState<Course[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  // Deleting a user deletes their courses, so both lists reload together.
  const refresh = useCallback(
    () => Promise.all([api.listUsers().then(setUsers), api.listCourses().then(setCourses)]).catch(setError),
    [api],
  );
  useEffect(() => {
    if (me?.is_admin) refresh();
  }, [me, refresh]);

  if (!me) return null;
  if (!me.is_admin) return <p>Only admins can manage users.</p>;

  return (
    <section>
      <h1>Users</h1>
      <InviteForm onInvited={refresh} />
      <ErrorMessage error={error} />
      {users && <UserTable users={users} me={me} onChange={refresh} />}
      <h2>Courses</h2>
      {courses && <CourseTable courses={courses} onChange={refresh} />}
    </section>
  );
}

/** Splits pasted text (one per line, or separated by commas, semicolons or spaces). */
export function parseEmails(text: string): string[] {
  return text.split(/[\s,;]+/).filter(Boolean);
}

function InviteForm({ onInvited }: { onInvited: () => void }) {
  const { api } = useApi();
  const [text, setText] = useState("");
  const [role, setRole] = useState<UserRole>("student");
  const [result, setResult] = useState<InviteResult | null>(null);
  const [error, setError] = useState<unknown>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setResult(null);
    setError(null);
    try {
      setResult(await api.inviteUsers(parseEmails(text), role));
      setText("");
      onInvited();
    } catch (e) {
      setError(e);
    }
  }

  return (
    <form onSubmit={submit} className="card">
      <h2>Invite</h2>
      <p className="muted">
        Only invited emails can sign in. Each person signs in with the Google account for that email.
      </p>
      <div className="row">
        <label>
          Emails (one per line, or separated by commas)
          <textarea value={text} onChange={(e) => setText(e.target.value)} rows={3} required />
        </label>
        <label className="narrow">
          Role
          <select value={role} onChange={(e) => setRole(e.target.value as UserRole)}>
            <option value="student">Student</option>
            <option value="professor">Professor</option>
          </select>
        </label>
        <button type="submit">Invite</button>
      </div>
      {result && (
        <p className="success" role="status">
          Invited {result.created.length}.
          {result.already_exists.length > 0 &&
            ` Already had an account: ${result.already_exists.join(", ")}.`}
        </p>
      )}
      <ErrorMessage error={error} />
    </form>
  );
}

function UserTable({ users, me, onChange }: { users: AdminUser[]; me: Me; onChange: () => void }) {
  const { api, refreshMe } = useApi();
  const [error, setError] = useState<unknown>(null);

  async function run(action: () => Promise<unknown>) {
    setError(null);
    try {
      await action();
      onChange();
    } catch (e) {
      setError(e);
    }
  }
  const update = (user: AdminUser, changes: UserChanges) =>
    run(async () => {
      await api.updateUser(user.id, changes);
      if (user.id === me.id) await refreshMe();
    });

  return (
    <div className="card">
      <ErrorMessage error={error} />
      <table className="users">
        <thead>
          <tr>
            <th>Email</th>
            <th>Status</th>
            <th>Role</th>
            <th>Admin</th>
            <th>
              <span className="visually-hidden">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {users.map((user) => {
            const editable = canEdit(me, user);
            return (
              <tr key={user.id}>
                <td>
                  {user.email}
                  {user.name && <div className="muted">{user.name}</div>}
                </td>
                <td>{user.status}</td>
                <td>
                  <select
                    aria-label={`Role for ${user.email}`}
                    value={user.role}
                    onChange={(e) => update(user, { role: e.target.value as UserRole })}
                  >
                    <option value="student">Student</option>
                    <option value="professor">Professor</option>
                  </select>
                </td>
                <td>
                  <input
                    type="checkbox"
                    aria-label={`Admin: ${user.email}`}
                    checked={user.is_admin}
                    disabled={!editable}
                    onChange={(e) => update(user, { is_admin: e.target.checked })}
                  />
                </td>
                <td>
                  {editable &&
                    (user.status === "invited" ? (
                      <button type="button" className="link" onClick={() => run(() => api.deleteUser(user.id))}>
                        Cancel invitation
                      </button>
                    ) : (
                      <div className="actions">
                        <button type="button" className="link" onClick={() => update(user, { is_active: !user.is_active })}>
                          {user.is_active ? "Disable" : "Enable"}
                        </button>
                        <button
                          type="button"
                          className="link"
                          onClick={() =>
                            window.confirm(
                              `Delete ${user.email}? Any courses and lectures they own are deleted too. This can't be undone.`,
                            ) && run(() => api.deleteUser(user.id))
                          }
                        >
                          Delete
                        </button>
                      </div>
                    ))}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function CourseTable({ courses, onChange }: { courses: Course[]; onChange: () => void }) {
  const { api } = useApi();
  const [error, setError] = useState<unknown>(null);

  async function remove(course: Course) {
    if (!window.confirm(`Delete ${course.code} and all its lectures? This can't be undone.`)) return;
    setError(null);
    try {
      await api.deleteCourse(course.id);
      onChange();
    } catch (e) {
      setError(e);
    }
  }

  if (courses.length === 0) return <p className="muted">No courses yet.</p>;
  return (
    <div className="card">
      <ErrorMessage error={error} />
      <table className="users">
        <thead>
          <tr>
            <th>Course</th>
            <th>Professor</th>
            <th>Lectures</th>
            <th>
              <span className="visually-hidden">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody>
          {courses.map((course) => (
            <tr key={course.id}>
              <td>
                {course.code} {course.title}
              </td>
              <td>{course.professor ?? "Unknown professor"}</td>
              <td>{course.lecture_count}</td>
              <td>
                <button
                  type="button"
                  className="link"
                  aria-label={`Delete ${course.code}`}
                  onClick={() => remove(course)}
                >
                  Delete
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Mirrors the API: everything but the role is locked on your own row. */
function canEdit(me: Me, user: AdminUser): boolean {
  return user.id !== me.id;
}
