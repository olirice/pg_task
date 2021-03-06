# Quickstart

## Installation

pg_task is available as a PostgreSQL extension, and as a standalone SQL script

### Extension

If you have PostgreSQL (>=11) with development packages, clone the repository and then
```shell
make install
```
then, in your database
```sql
create extension pg_task;
```

To update a previously installed version of `pg_task`, follow the installation steps for the new version and then run
```sql
alter extension pg_task update;
```
in your database.

### Standalone Script

As a pure SQL/PLPGSQL extension, `pg_task` can be installed in your database without access to the server. To install the latest version, execute the contents of `sql/pg_task--<version>.sql` in your database.

To update a previously installed version, execute the contents of each sql file matching the pattern `sql/pg_task--<start_version>--<end_version>.sql` beginning with the `<start_version>` currently installed in your database.

For example, to upgrade from version 0.0.1 to 0.0.3, execute
```
sql/pg_task--0.0.1--0.0.2.sql
sql/pg_task--0.0.2--0.0.3.sql
```
