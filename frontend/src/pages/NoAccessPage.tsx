import type { ApiError } from "../api/client";
import { useAuth } from "../auth/AuthContext";

/** Signed in with Google, but the API refuses the account (not invited, or disabled). */
export function NoAccessPage({ error }: { error: ApiError }) {
  const { session, signOut } = useAuth();
  return (
    <main className="signin">
      <h1>Lecture Indexer</h1>
      <section className="card">
        <h2>{error.code === "not_invited" ? "You haven't been invited yet" : "Account disabled"}</h2>
        <p role="alert">{error.message}</p>
        <p className="muted">Signed in as {session?.email}.</p>
        <button type="button" onClick={signOut}>
          Sign in with another account
        </button>
      </section>
    </main>
  );
}
