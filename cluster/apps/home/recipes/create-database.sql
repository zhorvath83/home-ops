CREATE DATABASE recipes;
CREATE USER recipes WITH ENCRYPTED PASSWORD '${SECRET_PSQL_RECIPES_PWD}';
GRANT all privileges ON database recipes TO recipes;
ALTER DATABASE recipes OWNER TO recipes;
