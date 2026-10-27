import { describe, expect, it } from "vitest";
import { embedUrl } from "./VideoPlayer";

describe("embedUrl", () => {
  it("starts the privacy-enhanced player at the given second", () => {
    expect(embedUrl("abcdefghijk", 202)).toBe(
      "https://www.youtube-nocookie.com/embed/abcdefghijk?start=202&autoplay=1&rel=0",
    );
  });

  it("can't be steered off the embed path by a crafted video id", () => {
    expect(embedUrl("../watch?x", 0)).toMatch(/^https:\/\/www\.youtube-nocookie\.com\/embed\/\.\.%2Fwatch%3Fx\?/);
  });
});
