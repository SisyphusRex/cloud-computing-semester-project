-- Users are created on first sign-in from their verified Google ID token.
CREATE TABLE users (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    google_sub  text NOT NULL UNIQUE,
    email       text NOT NULL,
    name        text,
    role        text NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'professor')),
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE courses (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_id    bigint NOT NULL REFERENCES users (id),
    code        text NOT NULL,
    title       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (owner_id, code)
);

CREATE TABLE lectures (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id         bigint NOT NULL REFERENCES courses (id) ON DELETE CASCADE,
    youtube_video_id  text NOT NULL,
    title             text NOT NULL DEFAULT '',
    caption_language  text,
    status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'indexed', 'failed')),
    error             text,
    indexed_at        timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (course_id, youtube_video_id)
);

-- One row per caption window; start_ms becomes the ?t= deep link.
CREATE TABLE segments (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lecture_id  bigint NOT NULL REFERENCES lectures (id) ON DELETE CASCADE,
    start_ms    integer NOT NULL CHECK (start_ms >= 0),
    end_ms      integer NOT NULL CHECK (end_ms >= start_ms),
    text        text NOT NULL,
    tsv         tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED
);

CREATE INDEX segments_tsv_idx ON segments USING gin (tsv);
CREATE INDEX segments_lecture_start_idx ON segments (lecture_id, start_ms);
CREATE INDEX lectures_course_idx ON lectures (course_id);
