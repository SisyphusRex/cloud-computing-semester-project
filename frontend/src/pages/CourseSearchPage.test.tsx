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
  embeddable: true,
};

function setup(url: string, hits = [hit]) {
  const search = vi.fn((_courseId: number, q: string) => Promise.resolve({ query: q, hits }));
  const api = fakeApi({ listCourses: vi.fn(() => Promise.resolve([course])), search });
  renderPage(<CourseSearchPage />, { api, path: "/courses/:courseId", url });
  return { search };
}

describe("<CourseSearchPage>", () => {
  it("runs the search from the URL and plays a hit in the embedded player", async () => {
    const { search } = setup("/courses/1?q=lambda");

    const link = await screen.findByRole("link", { name: "03:22" });
    expect(link).toHaveAttribute("href", "/courses/1?q=lambda&v=abcdefghijk&t=202");
    expect(link).not.toHaveAttribute("target");
    expect(screen.getByText("Lambda").tagName).toBe("MARK");
    expect(screen.getByRole("heading", { name: "CS6030 Cloud Computing" })).toBeInTheDocument();
    expect(search).toHaveBeenCalledWith(1, "lambda");
    expect(document.querySelector("iframe")).toBeNull();

    await userEvent.click(link);

    const player = screen.getByTitle("Fall Lecture 4");
    expect(player).toHaveAttribute("src", expect.stringContaining("youtube-nocookie.com/embed/abcdefghijk?"));
    expect(player).toHaveAttribute("src", expect.stringContaining("start=202"));
    expect(link.closest("li")).toHaveAttribute("aria-current", "true");
  });

  it("opens the player from a shared URL", async () => {
    setup("/courses/1?q=lambda&v=abcdefghijk&t=202");

    expect(await screen.findByTitle("Fall Lecture 4")).toHaveAttribute(
      "src",
      expect.stringContaining("start=202"),
    );
  });

  it("links out to YouTube when the video can't be embedded", async () => {
    setup("/courses/1?q=lambda", [{ ...hit, embeddable: false }]);

    const link = await screen.findByRole("link", { name: /03:22/ });
    expect(link).toHaveAttribute("href", hit.url);
    expect(link).toHaveAttribute("target", "_blank");
  });

  it("closes the player on a new search", async () => {
    const { search } = setup("/courses/1?q=lambda&v=abcdefghijk&t=202");
    await screen.findByTitle("Fall Lecture 4");

    await userEvent.clear(screen.getByRole("textbox"));
    await userEvent.type(screen.getByRole("textbox"), "calculus");
    await userEvent.click(screen.getByRole("button", { name: "Search" }));

    await waitFor(() => expect(search).toHaveBeenCalledWith(1, "calculus"));
    expect(document.querySelector("iframe")).toBeNull();
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
