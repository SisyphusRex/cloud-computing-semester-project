import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { useAuth } from "../auth/AuthContext";
import { config } from "../config";
import { ApiError, createApi } from "./client";
import type { Api } from "./client";
import type { Me } from "./types";

/** null while it's being worked out after sign-in. */
export type Role = "professor" | "student" | null;

export interface ApiValue {
  api: Api;
  role: Role;
  /** The signed-in user, from GET /ingest/me; null until it arrives. */
  me: Me | null;
  /** Set when the account can't use the app: 403 not_invited or account_disabled. */
  accessError: ApiError | null;
}

const ACCESS_ERRORS = ["not_invited", "account_disabled"];

export const ApiContext = createContext<ApiValue | null>(null);

export function useApi(): ApiValue {
  const value = useContext(ApiContext);
  if (!value) throw new Error("useApi must be used inside <ApiProvider>");
  return value;
}

export function ApiProvider({ children }: { children: ReactNode }) {
  const { session, signOut } = useAuth();
  const token = session?.token ?? null;

  const api = useMemo(
    () => createApi({ base: config.apiBase, getToken: () => token, onUnauthorized: signOut }),
    [token, signOut],
  );

  // Roles live in the API's database, so ask. The answer is tied to the token
  // it was for, so a new sign-in shows "unknown" until its own answer arrives.
  const [answer, setAnswer] = useState<{
    token: string;
    me: Me | null;
    accessError: ApiError | null;
  } | null>(null);
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    api.me().then(
      (me) => !cancelled && setAnswer({ token, me, accessError: null }),
      (error) => {
        const denied = error instanceof ApiError && ACCESS_ERRORS.includes(error.code);
        if (!cancelled) setAnswer({ token, me: null, accessError: denied ? error : null });
      },
    );
    return () => {
      cancelled = true;
    };
  }, [api, token]);
  const current = answer?.token === token ? answer : null;
  const me = current?.me ?? null;
  const accessError = current?.accessError ?? null;
  const role = me?.role ?? null;

  const value = useMemo(() => ({ api, role, me, accessError }), [api, role, me, accessError]);
  return <ApiContext.Provider value={value}>{children}</ApiContext.Provider>;
}
