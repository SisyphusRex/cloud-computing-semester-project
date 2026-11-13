-- Admins can delete accounts that have signed in, not just invitations (ADR 0006).
-- Deleting a professor deletes their courses; lectures and segments already
-- cascade from courses. Audit rows and invitations they made stay, with the
-- reference set to NULL; the delete's own audit row keeps the email.
-- Old code never deletes these rows, so the previous release runs unchanged.
ALTER TABLE courses
    DROP CONSTRAINT courses_owner_id_fkey,
    ADD CONSTRAINT courses_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE user_audit
    DROP CONSTRAINT user_audit_actor_id_fkey,
    ADD CONSTRAINT user_audit_actor_id_fkey
        FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE users
    DROP CONSTRAINT users_invited_by_fkey,
    ADD CONSTRAINT users_invited_by_fkey
        FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE SET NULL;
