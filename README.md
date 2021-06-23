# pg_task

<p>

<a href="https://github.com/olirice/pg_task/actions"><img src="https://github.com/olirice/pg_task/workflows/test/badge.svg" alt="Tests" height="18"></a>

</p>

---

**Documentation**: <a href="https://olirice.github.io/pg_task" target="_blank">https://olirice.github.io/pg_task</a>

**Source Code**: <a href="https://github.com/olirice/pg_task" target="_blank">https://github.com/olirice/pg_task</a>

---

A PostgreSQL extension for migrations and DDL tracking.


### Installation

Requires:

 - Postgres 11+


```shell
git clone https://github.com/olirice/pg_task.git
cd pg_task
make install
```

### Testing
Requires:

 - Postgres 11+


```shell
make install && make installcheck;
```

### Usage

In PSQL
```sql
create extension pg_task;

-- TODO
```

