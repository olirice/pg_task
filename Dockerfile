FROM postgres:latest

COPY Makefile tmp/pg_task/Makefile
COPY pg_task.control tmp/pg_task/pg_task.control
COPY sql tmp/pg_task/sql

RUN apt-get update \
    && apt-get install build-essential -y --no-install-recommends \
    && cd tmp/pg_task \
    && make install \
    && apt-get clean \
    && apt-get remove build-essential -y \
    && apt-get autoremove -y \
    && rm -rf /tmp/pg_task /var/lib/apt/lists/* /var/tmp/*
