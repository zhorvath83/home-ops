**🔹  Postgresql backup with prodrigestivill/docker-postgres-backup-local**

**📣 Manual Backups**
By default this container makes daily backups, but you can start a manual backup by running /backup.sh

**👉  Restore backups**

📍  Restore to a remote server

zcat recipes-20210819-000003.sql.gz | psql --host=postgresql.selfhosted.svc.cluster.local --port=5432 --username=postgres --dbname=recipes -W
