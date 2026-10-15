import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { fakeApi, renderPage } from "../test/render";
import { CourseSearchPage } from "./CourseSearchPage";

const course = { id: 1, code: "CS6030", title: "Cloud Computing", professor: "Prof", lecture_count: 2 };
const hit = {
  lecture_id: 4,
  lecture_title: "Fall Lecture 4",
  video_id: "abcdefghijk",
  start_seconds: 202,
  timestamp: "03:22",
  excerpt_html: "<mark>Lambda</mark> calculus is the basis",
  url: "https://www.youtube.com/watch?v=abcdefghijk&t=202s",
};

function setup(url: string) {
  const search = vi.fn((_courseId: number, q: string) => Promise.resolve({ query: q, hits: [hit] }));
  const api = fakeApi({ listCourses: vi.fn(() => Promise.resolve([course])), search });
  renderPage(<CourseSearchPage />, { api, path: "/courses/:courseId", url });
  return { search };
}

describe("<CourseSearchPage>", () => {
  it("runs the search from the URL and links each hit to its timestamp", async () => {
    const { search } = setup("/courses/1?q=lambda");

    const link = await screen.findByRole("link", { name: "03:22" });
    expect(link).toHaveAttribute("href", hit.url);
    expect(link).toHaveAttribute("target", "_blank");
    expect(screen.getByText("Lambda").tagName).toBe("MARK");
    expect(screen.getByRole("heading", { name: "CS6030 Cloud Computing" })).toBeInTheDocument();
    expect(search).toHaveBeenCalledWith(1, "lambda");
  });

  it("searches when the form is submitted", async () => {
    const { search } = setup("/courses/1");

    await userEvent.type(screen.getByRole("textbox"), '"lambda calculus"');
    await userEvent.click(screen.getByRole("button", { name: "Search" }));

    await waitFor(() => expect(search).toHaveBeenCalledWith(1, '"lambda calculus"'));
    expect(await screen.findByRole("link", { name: "03:22" })).toBeInTheDocument();
  });

  it("says when nothing matched", async () => {
    const api = fakeApi({
      listCourses: vi.fn(() => Promise.resolve([course])),
      search: vi.fn(() => Promise.resolve({ query: "zebra", hits: [] })),
    });
    renderPage(<CourseSearchPage />, { api, path: "/courses/:courseId", url: "/courses/1?q=zebra" });

    expect(await screen.findByText("No matches for “zebra”.")).toBeInTheDocument();
  });
});
