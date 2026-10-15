import { useEffect, useRef, useState } from "react";
import { useAuth } from "../auth/AuthContext";
import { loadGoogleIdentity } from "../auth/gis";
import { sessionFromIdToken } from "../auth/session";
import { config } from "../config";
import { ErrorMessage } from "./ErrorMessage";

export function GoogleSignInButton() {
  const { signIn } = useAuth();
  const container = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    let cancelled = false;
    loadGoogleIdentity()
      .then((google) => {
        if (cancelled || !container.current) return;
        google.accounts.id.initialize({
          client_id: config.googleClientId,
          callback: ({ credential }) => {
            try {
              signIn(sessionFromIdToken(credential));
            } catch (e) {
              setError(e);
            }
          },
        });
        google.accounts.id.renderButton(container.current, {
          theme: "outline",
          size: "large",
          text: "signin_with",
        });
      })
      .catch((e) => !cancelled && setError(e));
    return () => {
      cancelled = true;
    };
  }, [signIn]);

  return (
    <>
      <div ref={container} />
      <ErrorMessage error={error} />
    </>
  );
}
