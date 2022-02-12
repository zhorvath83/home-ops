**🔹  Restore a backup**

📍 You can drop all tables eg. from PGadmin:


DO $$ DECLARE
    r RECORD;
BEGIN
    -- if the schema you operate on is not "current", you will want to
    -- replace current_schema() in query with 'schematodeletetablesfrom'
    -- *and* update the generate 'DROP...' accordingly.
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = current_schema()) LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
    END LOOP;
END $$;


📍 Login to pgbackups container and execute:

Replace $BACKUPFILE, $PORT, $USERNAME and $DBNAME from the following command:

zcat /backups/daily/$BACKUPFILE.sql.gz | psql --host=postgresql.selfhosted.svc.cluster.local --port=$PORT --username=$USERNAME --dbname=$DBNAME -W
