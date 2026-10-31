import { render } from "@testing-library/react";
import type { ReactNode } from "react";
import { MemoryRouter, Route, Routes } from "react-router";
import { vi } from "vitest";
import { ApiContext } from "../api/ApiContext";
import type { Role } from "../api/ApiContext";
import type { Api } from "../api/client";
import type { Me } from "../api/types";
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
    me: missing("me"),
    listUsers: missing("listUsers"),
    inviteUsers: missing("inviteUsers"),
    updateUser: missing("updateUser"),
    deleteInvitation: missing("deleteInvitation"),
  };
  return { ...api, ...overrides } as Api;
}

interface Options {
  api: Api;
  role?: Role;
  /** Defaults to a user with `role` who isn't an admin. */
  me?: Partial<Me>;
  refreshMe?: () => Promise<void>;
  auth?: Partial<AuthValue>;
  path: string;
  url: string;
}

/** Render `element` at route `path`, starting at `url`, with fake providers. */
export function renderPage(
  element: ReactNode,
  { api, role = "student", me, refreshMe = vi.fn(() => Promise.resolve()), auth, path, url }: Options,
) {
  const authValue: AuthValue = {
    session: devSession("someone@example.edu"),
    signIn: vi.fn(),
    signOut: vi.fn(),
    requestYouTubeToken: vi.fn(() => Promise.resolve("yt-token")),
    ...auth,
  };
  return render(
    <AuthContext.Provider value={authValue}>
      <ApiContext.Provider
        value={{ api, role, me: fakeMe(role, me), refreshMe, accessError: null }}
      >
        <MemoryRouter initialEntries={[url]}>
          <Routes>
            <Route path={path} element={element} />
          </Routes>
        </MemoryRouter>
      </ApiContext.Provider>
    </AuthContext.Provider>,
  );
}

function fakeMe(role: Role, overrides: Partial<Me> = {}): Me | null {
  if (!role) return null;
  return {
    id: 1,
    email: "someone@example.edu",
    name: "Someone",
    role,
    is_admin: false,
    ...overrides,
  };
}
