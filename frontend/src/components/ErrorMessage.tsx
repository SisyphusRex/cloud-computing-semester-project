import { ApiError } from "../api/client";

export function errorText(error: unknown): string {
  if (error instanceof ApiError || error instanceof Error) return error.message;
  return "Something went wrong.";
}

export function ErrorMessage({ error }: { error: unknown }) {
  if (!error) return null;
  return (
    <p className="error" role="alert">
      {errorText(error)}
    </p>
  );
}
