# pg_migrate

<p>

<a href="https://github.com/olirice/pg_migrate/actions"><img src="https://github.com/olirice/pg_migrate/workflows/test/badge.svg" alt="Tests" height="18"></a>

</p>

---

**Documentation**: <a href="https://olirice.github.io/pg_migrate" target="_blank">https://olirice.github.io/pg_migrate</a>

**Source Code**: <a href="https://github.com/olirice/pg_migrate" target="_blank">https://github.com/olirice/pg_migrate</a>

---

A PostgreSQL extension for migrations and DDL tracking.


## API

- migrations.revision
- migrations.persist_ddl()
- TODO: migrations.upgrade(revision_id_or_tag text)
- TODO: migrations.downgrade(revision_id_or_tag text)
- TODO: migrations.merge(revision_id, revision_id)
- TODO: migrations.export()



### Installation

Requires:

 - Postgres 11+


```shell
git clone https://github.com/olirice/pg_migrate.git
cd pg_migrate
make install
```

### Testing
Requires:

 - Postgres 11+


```shell
PGUSER=postgres make install && PGUSER=postgres make installcheck || (cat regression.diffs && /bin/false)
```

### Usage

Setup
```shell
createdb pgmig
createuser -s postgres
```

Launch postgres repl with
```
psql -d pgmig -U postgres
```

In PSQL
```sql
create extension pg_migrate;

-- Confirm everything worked
select * from migrations.revision
```

