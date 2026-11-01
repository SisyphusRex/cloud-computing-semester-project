-- The contract steps from ADRs 0002 and 0003 (docs/release-process.md). Sign-in
-- only claims invitations, an UPDATE, so search no longer needs to create users.
-- Nothing reads is_superuser, so a rollback to before prod-2026-10-31.1 won't work.
REVOKE INSERT ON users FROM li_search_role;
REVOKE USAGE ON SEQUENCE users_id_seq FROM li_search_role;
ALTER TABLE users DROP COLUMN is_superuser;
