import { useEffect, useRef } from "react";

/**
 * youtube-nocookie.com sets no cookies until playback starts. A plain iframe
 * keeps YouTube's player script out of our CSP's script-src; the cost is that
 * jumping to another timestamp reloads the player.
 */
export function embedUrl(videoId: string, start: number): string {
  const params = new URLSearchParams({ start: String(start), autoplay: "1", rel: "0" });
  return `https://www.youtube-nocookie.com/embed/${encodeURIComponent(videoId)}?${params}`;
}

interface Props {
  videoId: string;
  start: number;
  title: string;
}

/** Remount (via `key`) to play a different clip. */
export function VideoPlayer({ videoId, start, title }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  // The player sits above the hits, so bring it back into view when a hit
  // further down starts a clip. jsdom has no scrollIntoView.
  useEffect(() => {
    ref.current?.scrollIntoView?.({ block: "nearest", behavior: "smooth" });
  }, []);

  return (
    <div className="player" ref={ref}>
      <iframe
        src={embedUrl(videoId, start)}
        title={title}
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
        allowFullScreen
        // YouTube refuses to play embeds that send no Referer.
        referrerPolicy="strict-origin-when-cross-origin"
      />
      <p className="muted">{title}</p>
    </div>
  );
}
