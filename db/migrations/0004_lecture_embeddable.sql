-- Whether YouTube lets the video play embedded on our site. Hits from lectures
-- that don't link out to youtube.com instead. Existing rows count as embeddable
-- until they're re-registered.
ALTER TABLE lectures ADD COLUMN embeddable boolean NOT NULL DEFAULT true;
