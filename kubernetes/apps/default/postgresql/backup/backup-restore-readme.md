**🔹 Restore a backup**

zcat /backups/last/dbname-latest.sql.gz | psql --username=postgres -W


📍 If needed drop all tables:

DO $$ DECLARE
r RECORD;
BEGIN
-- if the schema you operate on is not "current", you will want to
-- replace current*schema() in query with 'schematodeletetablesfrom'
-- \_and* update the generate 'DROP...' accordingly.
FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = current_schema()) LOOP
EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
END LOOP;
END $$;
