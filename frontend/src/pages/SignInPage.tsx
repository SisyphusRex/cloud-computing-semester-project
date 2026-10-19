import { useState } from "react";
import type { FormEvent } from "react";
import { useAuth } from "../auth/AuthContext";
import { devSession } from "../auth/session";
import { GoogleSignInButton } from "../components/GoogleSignInButton";
import { config } from "../config";

const DEV_ACCOUNTS = ["prof@example.edu", "student@example.edu"];

export function SignInPage() {
  return (
    <main className="signin">
      <h1>Lecture Indexer</h1>
      <p>Search your course's recorded lectures and jump to the moment a term is spoken.</p>
      {config.devAuth ? (
        <DevSignIn />
      ) : config.googleClientId ? (
        <GoogleSignInButton />
      ) : (
        <p className="error" role="alert">
          Sign-in isn't configured: set VITE_GOOGLE_CLIENT_ID, or VITE_DEV_AUTH=1 for local development.
        </p>
      )}
    </main>
  );
}

function DevSignIn() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState("");

  function submit(event: FormEvent) {
    event.preventDefault();
    if (email.trim()) signIn(devSession(email.trim()));
  }

  return (
    <section className="card">
      <h2>Development sign-in</h2>
      <p className="muted">
        The APIs must run with LI_DEV_AUTH=1. Sign-in is invite-only: docker compose invites
        these two accounts, and prof@example.edu is a superuser who can invite others.
      </p>
      <div className="row">
        {DEV_ACCOUNTS.map((account) => (
          <button key={account} type="button" onClick={() => signIn(devSession(account))}>
            {account}
          </button>
        ))}
      </div>
      <form onSubmit={submit} className="row">
        <label>
          Other email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <button type="submit">Sign in</button>
      </form>
    </section>
  );
}
