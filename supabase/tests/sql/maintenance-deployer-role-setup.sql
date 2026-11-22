-- Disposable CI only: match the relevant hosted Supabase postgres role flags.
-- The CI service starts postgres as SUPERUSER; lower it before applying the draft so
-- CREATE ROLE, SET ROLE and ownership transfer are tested with CREATEROLE only.
ALTER ROLE postgres NOSUPERUSER CREATEROLE CREATEDB BYPASSRLS LOGIN;
