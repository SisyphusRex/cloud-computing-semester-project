export interface Session {
  /** Sent as the bearer token: a Google ID token, or "dev:<email>" in dev mode. */
  token: string;
  email: string;
  name?: string;
  /** Epoch milliseconds; Google ID tokens last about an hour. */
  expiresAt: number;
}

/**
 * Read the display fields from a Google ID token. The signature is NOT checked
 * here; the APIs verify every token. This is only for showing who's signed in.
 */
export function sessionFromIdToken(token: string): Session {
  const payload = token.split(".")[1];
  if (!payload) throw new Error("Malformed ID token");
  const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
  const json = new TextDecoder().decode(
    Uint8Array.from(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, "=")), (c) =>
      c.charCodeAt(0),
    ),
  );
  const claims = JSON.parse(json) as { email?: string; name?: string; exp?: number };
  if (!claims.email || !claims.exp) throw new Error("ID token is missing email or expiry");
  return { token, email: claims.email, name: claims.name, expiresAt: claims.exp * 1000 };
}

export function devSession(email: string): Session {
  return { token: `dev:${email}`, email, expiresAt: Date.now() + 12 * 60 * 60 * 1000 };
}
