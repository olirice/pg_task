EXTENSION = pg_task
DATA = sql/pg_task--0.0.1.sql
REGRESS = pg_task_test
REGRESS_OPTS = --inputdir=test

# postgres build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
