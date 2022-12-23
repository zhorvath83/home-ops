**🔹  Postgresql backup with prodrigestivill/docker-postgres-backup-local**

**📣 Manual Backups**
By default this container makes daily backups, but you can start a manual backup by running /backup.sh

**👉  Restore backups**

📍  Create the databasa

📍  Drop existing tables and data

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT quote_ident(tablename) AS tablename, quote_ident(schemaname) AS schemaname FROM pg_tables WHERE schemaname = 'public'
    LOOP
        RAISE INFO 'Dropping table %.%', r.schemaname, r.tablename;
        EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', r.schemaname, r.tablename);
    END LOOP;
END$$;

📍  Restore to a remote server

zcat recipes-20210819-000003.sql.gz | psql --host=postgresql-15.default.svc.cluster.local --port=5432 --username=postgres --dbname=recipes -W
