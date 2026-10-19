import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AuthContext } from "../auth/AuthContext";
import type { AuthValue } from "../auth/AuthContext";
import { devSession } from "../auth/session";
import { ApiProvider, useApi } from "./ApiContext";

function Probe() {
  const { role, me, accessError } = useApi();
  return (
    <p>
      role={role ?? "unknown"} admin={String(me?.is_admin ?? "-")} error={accessError?.code ?? "-"}
    </p>
  );
}

function renderWithFetch(response: Response) {
  vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(response)));
  const auth: AuthValue = {
    session: devSession("someone@example.edu"),
    signIn: vi.fn(),
    signOut: vi.fn(),
    requestYouTubeToken: vi.fn(),
  };
  render(
    <AuthContext.Provider value={auth}>
      <ApiProvider>
        <Probe />
      </ApiProvider>
    </AuthContext.Provider>,
  );
  return fetch as unknown as ReturnType<typeof vi.fn>;
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("<ApiProvider>", () => {
  it("reads the role and flags from /ingest/me", async () => {
    const fetchMock = renderWithFetch(
      json(200, { id: 1, email: "a@x", name: null, role: "professor", is_admin: true, is_superuser: false }),
    );
    expect(await screen.findByText("role=professor admin=true error=-")).toBeInTheDocument();
    expect(fetchMock.mock.calls[0][0]).toMatch(/\/ingest\/me$/);
  });

  it("reports an account that hasn't been invited", async () => {
    renderWithFetch(json(403, { error: "not_invited", message: "Your account hasn't been invited." }));
    expect(await screen.findByText("role=unknown admin=- error=not_invited")).toBeInTheDocument();
  });
});
