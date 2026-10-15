import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Excerpt, parseExcerpt } from "./Excerpt";

describe("parseExcerpt", () => {
  it("splits plain text and <mark> matches and decodes entities", () => {
    expect(parseExcerpt("<mark>Lambda</mark> calculus &amp; <mark>types</mark>!")).toEqual([
      { text: "Lambda", marked: true },
      { text: " calculus & ", marked: false },
      { text: "types", marked: true },
      { text: "!", marked: false },
    ]);
  });

  it("handles text without matches", () => {
    expect(parseExcerpt("no hits here")).toEqual([{ text: "no hits here", marked: false }]);
  });
});

describe("<Excerpt>", () => {
  it("renders escaped markup from captions as text, never as elements", () => {
    const { container } = render(
      <Excerpt html="Careful: &lt;script&gt;alert(1)&lt;/script&gt; <mark>lambda</mark> &amp; friends" />,
    );
    expect(container.querySelector("script")).toBeNull();
    expect(container).toHaveTextContent("Careful: <script>alert(1)</script> lambda & friends");
    expect(screen.getByText("lambda").tagName).toBe("MARK");
  });

  it("does not turn unexpected raw tags into elements", () => {
    const { container } = render(<Excerpt html={'<img src=x onerror="alert(1)"> <mark>ok</mark>'} />);
    expect(container.querySelector("img")).toBeNull();
    expect(container).toHaveTextContent('<img src=x onerror="alert(1)"> ok');
  });
});
