-- Superuser merges into admin (ADR 0003). The code no longer reads is_superuser,
-- but the previous release still does, so the column stays for one release
-- (docs/release-process.md). The check goes now: it would stop an admin from
-- revoking admin from a former superuser.
ALTER TABLE users DROP CONSTRAINT users_superuser_is_admin;
