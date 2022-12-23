`export POSTGRES_PASSWORD=$(sudo kubectl get secret --namespace default postgresql-15 -o jsonpath="{.data.postgres-password}" | base64 --decode)`

`read -s -p "Enter password:" PGPASSWORD`
`export PGPASSWORD`


`kubectl exec -it postgresql-15-0 -- bash -c 'export PGPASSWORD=${POSTGRES_PASSWORD}; time pg_dumpall -h OLDpostgresql.default.svc.cluster.local -U postgres | psql -h NEWpostgresql.default.svc.cluster.local -U postgres'`
