import { useState } from "react";
import { NavLink, Outlet } from "react-router";
import { useApi } from "../api/ApiContext";
import type { Me, UserRole } from "../api/types";
import { useAuth } from "../auth/AuthContext";
import { ErrorMessage } from "./ErrorMessage";

export function Layout() {
  const { session, signOut } = useAuth();
  const { api, role, me, refreshMe } = useApi();
  const [error, setError] = useState<unknown>(null);

  async function switchRole(user: Me, next: UserRole) {
    setError(null);
    try {
      await api.updateUser(user.id, { role: next });
      await refreshMe();
    } catch (e) {
      setError(e);
    }
  }

  return (
    <>
      <header className="topbar">
        <NavLink to="/" className="brand">
          Lecture Indexer
        </NavLink>
        <nav>
          <NavLink to="/" end>
            Courses
          </NavLink>
          {role === "professor" && <NavLink to="/manage">Manage</NavLink>}
          {me?.is_admin && <NavLink to="/admin">Admin</NavLink>}
        </nav>
        <div className="user">
          <span title={session?.email}>{session?.name ?? session?.email}</span>
          {me?.is_admin ? (
            <select
              className="role"
              aria-label="Your role"
              value={me.role}
              onChange={(e) => switchRole(me, e.target.value as UserRole)}
            >
              <option value="student">student</option>
              <option value="professor">professor</option>
            </select>
          ) : (
            role && <span className="role">{role}</span>
          )}
          <button type="button" className="link" onClick={signOut}>
            Sign out
          </button>
        </div>
      </header>
      <main>
        <ErrorMessage error={error} />
        <Outlet />
      </main>
    </>
  );
}
