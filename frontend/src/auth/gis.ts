const SCRIPT_URL = "https://accounts.google.com/gsi/client";

let loading: Promise<NonNullable<Window["google"]>> | null = null;

/** Load Google Identity Services once; resolves to `window.google`. */
export function loadGoogleIdentity(): Promise<NonNullable<Window["google"]>> {
  if (window.google?.accounts) return Promise.resolve(window.google);
  loading ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = SCRIPT_URL;
    script.async = true;
    script.onload = () =>
      window.google ? resolve(window.google) : reject(new Error("Google sign-in failed to load."));
    script.onerror = () => {
      loading = null;
      reject(new Error("Could not load Google sign-in. Check your connection."));
    };
    document.head.appendChild(script);
  });
  return loading;
}
