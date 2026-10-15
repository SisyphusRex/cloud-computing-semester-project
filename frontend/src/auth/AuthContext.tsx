import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import { config } from "../config";
import { loadGoogleIdentity } from "./gis";
import type { Session } from "./session";

/** Caption endpoints accept no narrower scope (see services/README.md). */
export const YOUTUBE_SCOPE = "https://www.googleapis.com/auth/youtube.force-ssl";

export interface AuthValue {
  session: Session | null;
  signIn(session: Session): void;
  signOut(): void;
  /**
   * A YouTube access token for registering lectures, from a Google consent
   * popup. Kept in memory only, and reused until shortly before it expires.
   */
  requestYouTubeToken(): Promise<string>;
}

export const AuthContext = createContext<AuthValue | null>(null);

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside <AuthProvider>");
  return value;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const youtubeToken = useRef<{ token: string; expiresAt: number } | null>(null);

  const signOut = useCallback(() => {
    setSession(null);
    youtubeToken.current = null;
    window.google?.accounts.id.disableAutoSelect();
  }, []);

  // Sign out when the ID token expires; the APIs would reject it anyway.
  useEffect(() => {
    if (!session) return;
    const timer = window.setTimeout(signOut, Math.max(0, session.expiresAt - Date.now()));
    return () => window.clearTimeout(timer);
  }, [session, signOut]);

  const requestYouTubeToken = useCallback(async (): Promise<string> => {
    if (config.devAuth) {
      // The Ingest API still calls YouTube with this, so registering a lecture
      // fails with youtube_token_invalid in dev mode. Use real sign-in to test ingest.
      return "dev-youtube-token";
    }
    const cached = youtubeToken.current;
    if (cached && cached.expiresAt > Date.now()) return cached.token;

    const google = await loadGoogleIdentity();
    return new Promise<string>((resolve, reject) => {
      const client = google.accounts.oauth2.initTokenClient({
        client_id: config.googleClientId,
        scope: YOUTUBE_SCOPE,
        hint: session?.email,
        callback: (response) => {
          if (response.error) {
            reject(new Error(response.error_description ?? response.error));
            return;
          }
          youtubeToken.current = {
            token: response.access_token,
            expiresAt: Date.now() + (response.expires_in - 60) * 1000,
          };
          resolve(response.access_token);
        },
        error_callback: (error) =>
          reject(new Error(error.message ?? `YouTube permission was not granted (${error.type}).`)),
      });
      client.requestAccessToken({ prompt: "" });
    });
  }, [session]);

  const value = useMemo(
    () => ({ session, signIn: setSession, signOut, requestYouTubeToken }),
    [session, signOut, requestYouTubeToken],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
