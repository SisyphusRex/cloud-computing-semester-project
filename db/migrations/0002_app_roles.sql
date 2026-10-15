-- Group roles the services' database users are granted into (li-migrate --grant).
-- On Cloud SQL the services log in as IAM users, which start with no privileges.
-- Roles are cluster-wide, so create them only if missing; grants target the
-- current schema so this also works in the per-test schemas.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'li_ingest_role') THEN
        CREATE ROLE li_ingest_role NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'li_search_role') THEN
        CREATE ROLE li_search_role NOLOGIN;
    END IF;

    EXECUTE format('GRANT USAGE ON SCHEMA %I TO li_ingest_role, li_search_role', current_schema());

    -- Ingest writes everything; it reads users because auth runs on every request.
    EXECUTE format(
        'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO li_ingest_role',
        current_schema());
    EXECUTE format(
        'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO li_ingest_role', current_schema());

    -- Search only reads, except that signing in creates or updates the user row.
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO li_search_role', current_schema());
    GRANT INSERT, UPDATE ON users TO li_search_role;
    GRANT USAGE ON SEQUENCE users_id_seq TO li_search_role;

    -- Tables added by later migrations get the same table-level defaults.
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I '
        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO li_ingest_role', current_schema());
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I '
        'GRANT USAGE, SELECT ON SEQUENCES TO li_ingest_role', current_schema());
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO li_search_role',
        current_schema());
END
$$;
