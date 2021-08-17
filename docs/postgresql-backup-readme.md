**🔹  Postgresql backup with prodrigestivill/docker-postgres-backup-local**

**📣 Manual Backups**
By default this container makes daily backups, but you can start a manual backup by running /backup.sh

**👉  Restore backups**

📍  Restore to a remote server

zcat backupFileName.sql.gz | psql --host=postgresql.data.svc.cluster.local --port=5432 --username=postgres --dbname=databasenameToRestore -W
