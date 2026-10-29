# How transcript search works

Transcript search uses **PostgreSQL's built-in full-text search** in the Cloud SQL database (`li-pg`). There's no separate search engine: caption text, its search index, and the query all live in Postgres. This page covers how segments are stored, what a `tsvector` is, which indexes the search uses, and how the Search API's query works.

## 1. Ingest stores captions as segments

When a professor registers a lecture, the Ingest API downloads its YouTube caption track (WebVTT) and [`captions.py`](../../services/ingest/src/ingest/captions.py) merges the short caption cues into **segments** of at most 20 seconds or 400 characters.

Each segment is one row in `segments` ([`0001_init.sql`](../../db/migrations/0001_init.sql)), bulk-loaded with `COPY` in [`ingest/routes.py`](../../services/ingest/src/ingest/routes.py). Re-registering a lecture deletes its old segments first.

| Column | Purpose |
|---|---|
| `lecture_id` | the lecture the segment belongs to |
| `start_ms`, `end_ms` | when it's spoken; `start_ms` becomes the `?t=` deep link |
| `text` | the caption text, shown in results |
| `tsv` | the searchable form of `text` (below) |

Search returns individual segments, not whole lectures, so every hit has its own timestamp.

## 2. `tsvector`: the searchable form of the text

```sql
tsv  tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED
```

A `tsvector` is a **sorted set of normalized words (lexemes), each with the positions where it appeared**. It isn't a numeric vector like an AI embedding.

```sql
SELECT to_tsvector('english',
  'Recursion is when a function calls itself. Recursive functions need a base case.');
-- 'base':12 'call':6 'case':13 'function':5,9 'need':10 'recurs':1,8 'when':3
```

`to_tsvector('english', ...)`:

- **lowercases** the text,
- **stems** each word to a root (`recursion`, `recursive` → `recurs`; `functions` → `function`),
- **drops stop words** (`is`, `a`, `itself`),
- **merges duplicates and keeps positions** (`'function':5,9`). Positions are used for phrase search, ranking, and choosing the excerpt.

Because the column is `GENERATED ... STORED`, Postgres computes `tsv` on every insert and saves it. Ingest only writes `text`, so the two can't get out of sync. `text` is kept for display.

### Why not `ILIKE '%word%'`?

The user's query goes through the same normalization (`websearch_to_tsquery`, below), so matching compares lexemes, not raw strings. Substring matching can't do that:

| Caption text | Search | `ILIKE` | Full-text search |
|---|---|---|---|
| "a recursive function" | `recursion` | no match (different word form) | match (`recurs`) |
| "the concurrency model" | `currency` | false match (substring) | no match (different lexeme) |
| "base … case" (not adjacent) | `base case` | only the exact string | match on both words; `"base case"` in quotes requires the phrase |

`ILIKE '%…%'` also can't use an index, so it reads every segment.

## 3. Indexes

| | **B-tree** (Postgres default) | **GIN** (Generalized Inverted Index) |
|---|---|---|
| Stores | one entry per row, sorted by the column value | one entry per lexeme, pointing to the rows that contain it |
| Answers | `=`, `<`, `>`, `BETWEEN`, `ORDER BY`, `UNIQUE` | "contains": `@@` (text search), `@>`/`&&` (arrays, JSONB) |
| Writes | cheap (one entry per row) | more expensive (one entry per distinct word in the row) |
| Can return rows sorted / enforce uniqueness | yes | no |

A GIN index on `tsv` works like the index at the back of a textbook:

```
'base'     → {1, 7}
'case'     → {1, 7}
'function' → {9}
'recurs'   → {1, 9}
```

For `'recurs' & 'function'`, Postgres reads the two lists and intersects them (→ `{9}`). `|` takes the union and `!` subtracts a list. The cost depends on the number of matches, not on the table size. The higher write cost is fine here: segments are bulk-loaded once per lecture and searched many times.

Indexes this search relies on:

| Index | Type | Used for |
|---|---|---|
| `segments_tsv_idx ON segments USING gin (tsv)` | GIN | `s.tsv @@ q`, the transcript match |
| `lectures_pkey` | B-tree (automatic) | joining each matching segment to its lecture |
| `lectures_course_idx (course_id)` | B-tree | `lectures.course_id = ...` |
| `segments_lecture_start_idx (lecture_id, start_ms)` | B-tree | not used by search; serves ingest's per-lecture delete and time-ordered reads |

## 4. The search query

`GET /search/courses/<course_id>/segments?q=...&limit=...` (`q` 1–200 characters, `limit` 1–50, default 20) runs one query, in [`search/query.py`](../../services/search/src/search/query.py):

```sql
SELECT l.id AS lecture_id, l.title AS lecture_title, l.youtube_video_id AS video_id,
       l.embeddable, s.start_ms,
       ts_headline('english', <HTML-escaped s.text>, q,
                   'StartSel=<mark>, StopSel=</mark>, MinWords=8, MaxWords=30, MaxFragments=2'
       ) AS excerpt_html,
       ts_rank_cd(s.tsv, q) AS rank
FROM segments s
JOIN lectures l ON l.id = s.lecture_id,
     websearch_to_tsquery('english', %(q)s) AS q
WHERE l.course_id = %(course_id)s
  AND l.status = 'indexed'
  AND s.tsv @@ q
ORDER BY rank DESC, l.id, s.start_ms
LIMIT %(limit)s
```

| Step | What it does |
|---|---|
| `websearch_to_tsquery('english', q)` | Turns the user's input into a `tsquery` with the same stemming. Supports search-engine syntax and never raises a syntax error. |
| `s.tsv @@ q` | The match operator: true if the segment's lexemes satisfy the query. Served by the GIN index. |
| `course_id`, `status = 'indexed'` | Restricts results to the selected course and to lectures that finished ingesting. |
| `ts_rank_cd(s.tsv, q)` | Scores each match by cover density: higher when the query terms appear close together. |
| `ts_headline(...)` | Builds the excerpt with matched words in `<mark>`. The text is HTML-escaped first, so the only tags in `excerpt_html` are ours and the frontend can render it as HTML. |
| `ORDER BY ... LIMIT` | `rank` is computed per query, so no index can supply this order; Postgres sorts the matches and keeps the top `limit`. |

All values are bound parameters (`%(q)s`), so user input never becomes SQL.

How `websearch_to_tsquery` reads input, and what `@@` then checks:

| User types | `tsquery` | A segment matches if it contains… |
|---|---|---|
| `recursion functions` | `'recurs' & 'function'` | both stems, anywhere in the segment |
| `recursion or loops` | `'recurs' \| 'loop'` | either stem |
| `recursion -tail` | `'recurs' & !'tail'` | `recurs` but not `tail` |
| `"base case"` | `'base' <-> 'case'` | `base` immediately followed by `case` (uses positions) |

Finally, [`search_segments`](../../services/search/src/search/query.py) converts each row's `start_ms` into a display timestamp (`MM:SS`, or `H:MM:SS`) and a link to `https://www.youtube.com/watch?v=<id>&t=<seconds>s`, so a hit opens the video where the words are spoken.

### Query plan

On a realistically sized table the plan has this shape:

```
Limit
  -> Sort  (Sort Key: (ts_rank_cd(s.tsv, q)) DESC, l.id, s.start_ms)
       -> Nested Loop
            -> Nested Loop
                 -> Function Scan on websearch_to_tsquery q
                 -> Bitmap Heap Scan on segments s
                      Recheck Cond: (tsv @@ q)
                      -> Bitmap Index Scan on segments_tsv_idx      ← GIN
            -> Index Scan using lectures_pkey on lectures l         ← B-tree
                 Filter: (course_id = ... AND status = 'indexed')
```

The **Bitmap Index Scan** is the GIN lookup. The **Bitmap Heap Scan** reads the matching rows and rechecks `@@`, which phrase queries need because positions are checked on the row itself.

To check it locally (`make dev-up`, then `psql postgresql://li:li@localhost:55432/li`):

```sql
EXPLAIN ANALYZE
SELECT s.id, ts_rank_cd(s.tsv, q) AS rank
FROM segments s
JOIN lectures l ON l.id = s.lecture_id,
     websearch_to_tsquery('english', 'recursion') AS q
WHERE l.course_id = 1 AND l.status = 'indexed' AND s.tsv @@ q
ORDER BY rank DESC LIMIT 20;
```

With only a few lectures loaded, the planner may choose `Seq Scan on segments`, because reading a small table directly is cheaper. To see that the index can be used, run `SET enable_seqscan = off;` in the session first.

## 5. Limitations

- **Word forms, not meaning:** `loop` won't find `iteration`.
- **No typo tolerance:** `recusion` doesn't stem to `recurs`.
- **Caption quality:** errors in YouTube's auto-generated captions affect search.
- **English only:** the `'english'` configuration is used for every lecture, whatever its `caption_language`.

Possible extensions: a synonym dictionary in the text search configuration, trigram matching (`pg_trgm`) for typos, or embedding-based semantic search.
