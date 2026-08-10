-- Rename the bootstrap superuser to admin
-- (POSTGRES_USER will still create the initial user, we rename it)
ALTER USER admin WITH PASSWORD 'root' SUPERUSER;

-- admin owns and fully controls public schema; no PUBLIC access
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL PRIVILEGES ON SCHEMA public TO admin;
