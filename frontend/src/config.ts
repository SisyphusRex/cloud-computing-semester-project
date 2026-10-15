export const config = {
  /** "" locally (the Vite dev server proxies /ingest and /search). */
  apiBase: (import.meta.env.VITE_API_BASE ?? "").replace(/\/$/, ""),
  googleClientId: import.meta.env.VITE_GOOGLE_CLIENT_ID ?? "",
  /** Type an email instead of using Google; the APIs must run with LI_DEV_AUTH=1. */
  devAuth: import.meta.env.VITE_DEV_AUTH === "1",
};
