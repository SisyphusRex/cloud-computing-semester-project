import { render } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter, Route, Routes } from "react-router";
import { vi } from "vitest";
import { ApiContext } from "../api/ApiContext";
import type { Role } from "../api/ApiContext";
import type { Api } from "../api/client";
import { AuthContext } from "../auth/AuthContext";
import type { AuthValue } from "../auth/AuthContext";
import { devSession } from "../auth/session";

/** An Api whose methods all reject unless the test overrides them. */
export function fakeApi(overrides: Partial<Api> = {}): Api {
  const missing = (name: string) => vi.fn(() => Promise.reject(new Error(`unexpected ${name}()`)));
  const api = {
    listCourses: missing("listCourses"),
    listLectures: missing("listLectures"),
    search: missing("search"),
    myCourses: missing("myCourses"),
    createCourse: missing("createCourse"),
    registerLecture: missing("registerLecture"),
    getLecture: missing("getLecture"),
    deleteLecture: missing("deleteLecture"),
  };
  return { ...api, ...overrides } as Api;
}

interface Options {
  api: Api;
  role?: Role;
  auth?: Partial<AuthValue>;
  path: string;
  url: string;
}

/** Render `element` at route `path`, starting at `url`, with fake providers. */
export function renderPage(element: ReactNode, { api, role = "student", auth, path, url }: Options) {
  const authValue: AuthValue = {
    session: devSession("someone@example.edu"),
    signIn: vi.fn(),
    signOut: vi.fn(),
    requestYouTubeToken: vi.fn(() => Promise.resolve("yt-token")),
    ...auth,
  };
  return render(
    <AuthContext.Provider value={authValue}>
      <ApiContext.Provider value={{ api, role }}>
        <MemoryRouter initialEntries={[url]}>
          <Routes>
            <Route path={path} element={element} />
          </Routes>
        </MemoryRouter>
      </ApiContext.Provider>
    </AuthContext.Provider>,
  );
}
