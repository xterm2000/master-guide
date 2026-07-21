-- Rename the bootstrap superuser to admin
-- (POSTGRES_USER will still create the initial user, we rename it)
ALTER USER admin WITH PASSWORD 'root' SUPERUSER;
