# AI usage log: Claude Code session, 2026-10-29

| | |
|---|---|
| Tool | Claude Code (VS Code extension), model Claude Opus 5.5 |
| User | Theodore Podewil |
| Date | 2026-10-29 |
| Branch | `development` (pushed to `origin/development`) |
| Commits produced | `0552e98`, plus the commit adding this log |
| Outcome | An explanation of how transcript search works in Postgres, written up as [`docs/search/transcript-search.md`](../../search/transcript-search.md) |

Each entry gives the prompt exactly as typed, then a summary of what Claude did in response.

---

## 1. How SQL searches transcripts

> explain how sql allows us to search transcripts in this project?

Claude read the schema (`db/migrations/0001_init.sql`), the ingest code, and the Search API's query (`services/search/src/search/query.py`). It explained that search is Postgres full-text search, with no separate search engine:
- **Ingest:** splits captions into segments of up to 20 seconds or 400 characters and stores one row per segment.
- **Storage:** each row has a generated `tsv` column, `to_tsvector('english', text)`, with a GIN index on it.
- **Search:** one query using `websearch_to_tsquery`, the `@@` match operator, `ts_rank_cd` for ranking, and `ts_headline` for the highlighted excerpt.
- **Links:** each segment's `start_ms` becomes a timestamped YouTube link.

It noted the main limitation: matching is on word forms, not meaning.

## 2. The match operator

> explain tsv @@ q

Claude explained that `@@` is true when a segment's `tsvector` satisfies the user's `tsquery`. Both sides are stemmed the same way, so "recursion" matches "recursive". It showed how `websearch_to_tsquery` turns input into `&`, `|`, `!`, and `<->` (phrase), and that `@@` only filters; ranking and excerpts are done separately.

## 3. GIN indexes

> what is a gin index?

An inverted index: one entry per lexeme, each pointing to the rows that contain it. Claude contrasted it with a B-tree, walked through answering `'recurs' & 'function'` by intersecting row lists, and covered the trade-offs (slower writes and a larger index, fine for segments that are written once and searched many times). It suggested checking with `EXPLAIN` for a `Bitmap Index Scan on segments_tsv_idx`.

## 4. `tsvector`

> explaine tsvector

A sorted set of normalized words with their positions, not a numeric vector. Claude showed the output of `to_tsvector` on an example sentence (lowercasing, stemming, stop words dropped, positions kept), explained what the positions are used for (phrase search, ranking, highlighting), and what `GENERATED ... STORED` does in this project. It listed what `tsvector` can't do: synonyms, typos, and errors in auto-generated captions.

## 5. Checking understanding

> so we are essentially converting the snippets of transcripts to tsvectors so we can search them?

Yes. Claude added that the original text is kept for display, the search input is converted the same way, Postgres does the conversion itself, and the GIN index makes it fast. Converting per segment, not per lecture, is what makes timestamped results possible.

## 6. Why the conversion makes matching work

> How do vectors make matching possible?

Claude compared `ILIKE '%word%'` with full-text search. Substring matching misses other word forms, gives false matches inside words (`currency` in `concurrency`), has no "both" or "either" logic, and can't use an index. After conversion, matching is a set check on lexemes, and the discrete lexemes are what make the GIN index possible.

## 7. B-tree and GIN side by side

> explain a b-tree index and gin index side by side

Claude drew both structures using the project's own indexes (`segments_lecture_start_idx` and `segments_tsv_idx`) and compared them: entries per row, the operators they serve, sorting, uniqueness, write cost, and size. It listed every index in the schema with the query each one serves.

## 8. The query and its indexes

> Show the search query and what index it uses

Claude tried to run `EXPLAIN` against the local database, but it wasn't running and Docker needs `sudo` on this machine. It annotated the query with the index each condition uses (GIN for `@@`, B-tree primary key and `course_id` index for the join and filter, none for the `ORDER BY rank`), gave the expected plan shape, clearly marked as not real output, and gave the commands to run it locally. It noted that a small table may produce a `Seq Scan` instead.

## 9. Summary

> Can you create a summary of tsvector, the indexes, and how our search query works?

Claude wrote a summary in chat covering ingest, `tsvector`, the two index types, the query step by step, and the limitations.

## 10. Into the docs

> can you turn it into a shareable doc and store it in the appropriate place in docs/?

Claude checked the existing docs layout and style, then wrote `docs/search/transcript-search.md` and linked it from the README's `docs/` row. While checking the code, it added details that hadn't come up in chat: the `q` and `limit` limits, that `segments_lecture_start_idx` serves ingest rather than search, and that every lecture is searched with the `'english'` configuration whatever its `caption_language`. It corrected its local-run instruction to `make dev-up` after checking the Makefile.

## 11. Commit

> can you commit and push

Pushed `0552e98` ("Document how transcript search works") to `development`.

## 12. This log

> can you also summarize my prompts and your responses from this session and store them in a file in the ai_usage directory in the same format as the other files?

Claude wrote this file in the format of the earlier logs.
