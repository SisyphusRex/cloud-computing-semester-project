import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, createApi } from "./client";

function respond(status: number, body?: unknown) {
  return vi.fn(() =>
    Promise.resolve(
      new Response(body === undefined ? null : JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json" },
      }),
    ),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("createApi", () => {
  const api = createApi({ base: "https://api.test", getToken: () => "id-token" });

  it("sends the bearer token and builds encoded search URLs", async () => {
    const fetch = respond(200, { query: "a&b", hits: [] });
    vi.stubGlobal("fetch", fetch);

    await api.search(3, "a&b", 5);

    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.test/search/courses/3/segments?q=a%26b&limit=5");
    expect(new Headers(init.headers).get("Authorization")).toBe("Bearer id-token");
  });

  it("sends the YouTube token only when registering a lecture", async () => {
    const fetch = respond(201, { id: 1, status: "indexed" });
    vi.stubGlobal("fetch", fetch);

    await api.registerLecture(7, "https://youtu.be/abcdefghijk", "yt-token");

    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit];
    const headers = new Headers(init.headers);
    expect(url).toBe("https://api.test/ingest/courses/7/lectures");
    expect(init.method).toBe("POST");
    expect(headers.get("X-YouTube-Token")).toBe("yt-token");
    expect(headers.get("Content-Type")).toBe("application/json");
    expect(JSON.parse(init.body as string)).toEqual({ video: "https://youtu.be/abcdefghijk" });
  });

  it("turns JSON error responses into ApiError", async () => {
    vi.stubGlobal(
      "fetch",
      respond(403, { error: "not_video_owner", message: "Not your video", lecture_id: null }),
    );

    const error = await api.registerLecture(7, "x", "t").catch((e) => e);

    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 403, code: "not_video_owner", message: "Not your video" });
  });

  it("reports network failures as ApiError", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new TypeError("Failed to fetch"))));

    await expect(api.listCourses()).rejects.toMatchObject({ status: 0, code: "network_error" });
  });

  it("calls onUnauthorized on 401", async () => {
    vi.stubGlobal("fetch", respond(401, { error: "unauthorized", message: "expired" }));
    const onUnauthorized = vi.fn();
    const client = createApi({ base: "", getToken: () => "old", onUnauthorized });

    await expect(client.listCourses()).rejects.toBeInstanceOf(ApiError);
    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("returns undefined for 204 responses", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response(null, { status: 204 }))));

    await expect(api.deleteLecture(4)).resolves.toBeUndefined();
  });
});
