import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ApiError } from "../api/client";
import type { Api } from "../api/client";
import { fakeApi, renderPage } from "../test/render";
import { ManagePage } from "./ManagePage";

const myCourse = { id: 1, code: "CS6030", title: "Cloud", created_at: "2026-10-15", lecture_count: 0 };
const indexed = {
  id: 9,
  course_id: 1,
  youtube_video_id: "abcdefghijk",
  title: "Fall Lecture 4",
  caption_language: "en",
  status: "indexed" as const,
  error: null,
  indexed_at: "2026-10-15",
  created_at: "2026-10-15",
  segment_count: 42,
};

function setup(registerLecture: Api["registerLecture"]) {
  const requestYouTubeToken = vi.fn(() => Promise.resolve("yt-token"));
  const api = fakeApi({
    myCourses: vi.fn(() => Promise.resolve([myCourse])),
    listLectures: vi.fn(() => Promise.resolve([])),
    registerLecture,
  });
  renderPage(<ManagePage />, {
    api,
    role: "professor",
    auth: { requestYouTubeToken },
    path: "/manage",
    url: "/manage",
  });
  return { requestYouTubeToken };
}

describe("<ManagePage>", () => {
  it("asks for YouTube access, then registers the lecture with that token", async () => {
    const registerLecture = vi.fn(() => Promise.resolve(indexed));
    const { requestYouTubeToken } = setup(registerLecture);

    await userEvent.type(await screen.findByLabelText(/YouTube video URL/), "https://youtu.be/abcdefghijk");
    await userEvent.click(screen.getByRole("button", { name: "Register lecture" }));

    expect(await screen.findByRole("status")).toHaveTextContent("Indexed “Fall Lecture 4”: 42 segments.");
    expect(requestYouTubeToken).toHaveBeenCalledOnce();
    expect(registerLecture).toHaveBeenCalledWith(1, "https://youtu.be/abcdefghijk", "yt-token");
  });

  it("shows why registration failed", async () => {
    const registerLecture = vi.fn(() =>
      Promise.reject(new ApiError(403, "not_video_owner", "You can only register videos from your own YouTube channel")),
    );
    setup(registerLecture);

    await userEvent.type(await screen.findByLabelText(/YouTube video URL/), "abcdefghijk");
    await userEvent.click(screen.getByRole("button", { name: "Register lecture" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("only register videos from your own YouTube channel");
  });

  it("tells students the page isn't for them", () => {
    renderPage(<ManagePage />, { api: fakeApi(), role: "student", path: "/manage", url: "/manage" });
    expect(screen.getByText("Only professors can manage courses.")).toBeInTheDocument();
  });
});
