-- Invite-only sign-in with admin-managed roles (ADR 0002).
-- An invitation is a users row with no google_sub yet; the first sign-in with
-- a matching verified email claims it. Existing rows keep their role.
ALTER TABLE users ALTER COLUMN google_sub DROP NOT NULL;

ALTER TABLE users
    ADD COLUMN is_admin      boolean NOT NULL DEFAULT false,
    ADD COLUMN is_superuser  boolean NOT NULL DEFAULT false,
    ADD COLUMN is_active     boolean NOT NULL DEFAULT true,
    ADD COLUMN invited_by    bigint REFERENCES users (id),
    ADD CONSTRAINT users_superuser_is_admin CHECK (NOT is_superuser OR is_admin);

-- Invitations are matched by email, so one row per address.
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));

-- Who changed which user, and how. actor_id is NULL for the li-admin CLI.
CREATE TABLE user_audit (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor_id    bigint REFERENCES users (id),
    target_id   bigint REFERENCES users (id) ON DELETE SET NULL,
    action      text NOT NULL,
    detail      jsonb NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX user_audit_target_idx ON user_audit (target_id, created_at);
