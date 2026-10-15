import { NavLink, Outlet } from "react-router";
import { useApi } from "../api/ApiContext";
import { useAuth } from "../auth/AuthContext";

export function Layout() {
  const { session, signOut } = useAuth();
  const { role } = useApi();
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
        </nav>
        <div className="user">
          <span title={session?.email}>{session?.name ?? session?.email}</span>
          {role && <span className="role">{role}</span>}
          <button type="button" className="link" onClick={signOut}>
            Sign out
          </button>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
    </>
  );
}
