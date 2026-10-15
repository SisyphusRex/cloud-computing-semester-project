const ENTITIES: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
};

function decode(text: string): string {
  return text.replace(/&(?:amp|lt|gt|quot|#39);/g, (entity) => ENTITIES[entity]);
}

export interface ExcerptPart {
  text: string;
  marked: boolean;
}

/**
 * Split the API's excerpt_html into plain text and highlighted matches. The
 * server escapes caption text and adds only <mark> tags, but we never hand the
 * string to innerHTML anyway: anything else that looks like a tag stays text.
 */
export function parseExcerpt(html: string): ExcerptPart[] {
  const parts: ExcerptPart[] = [];
  let last = 0;
  for (const match of html.matchAll(/<mark>(.*?)<\/mark>/gs)) {
    if (match.index > last) parts.push({ text: decode(html.slice(last, match.index)), marked: false });
    parts.push({ text: decode(match[1]), marked: true });
    last = match.index + match[0].length;
  }
  if (last < html.length) parts.push({ text: decode(html.slice(last)), marked: false });
  return parts;
}

export function Excerpt({ html }: { html: string }) {
  return (
    <p className="excerpt">
      {parseExcerpt(html).map((part, i) =>
        part.marked ? <mark key={i}>{part.text}</mark> : <span key={i}>{part.text}</span>,
      )}
    </p>
  );
}
