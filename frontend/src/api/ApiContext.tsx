import { createContext, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { useAuth } from "../auth/AuthContext";
import { config } from "../config";
import { ApiError, createApi } from "./client";
import type { Api } from "./client";

/** null while it's being worked out after sign-in. */
export type Role = "professor" | "student" | null;

export interface ApiValue {
  api: Api;
  role: Role;
}

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

  // Roles live in the API's database, so ask: professors can list their
  // courses, students get 403. The answer is tied to the token it was for, so
  // a new sign-in shows "unknown" until its own answer arrives.
  const [answer, setAnswer] = useState<{ token: string; role: Role } | null>(null);
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    api.myCourses().then(
      () => !cancelled && setAnswer({ token, role: "professor" }),
      (error) => {
        const role = error instanceof ApiError && error.status === 403 ? "student" : null;
        if (!cancelled) setAnswer({ token, role });
      },
    );
    return () => {
      cancelled = true;
    };
  }, [api, token]);
  const role = answer?.token === token ? answer.role : null;

  const value = useMemo(() => ({ api, role }), [api, role]);
  return <ApiContext.Provider value={value}>{children}</ApiContext.Provider>;
}
