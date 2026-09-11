FROM postgres:17-bookworm AS postgres_tools
FROM ruby:3.4.10-slim-bookworm

RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config liblz4-1 libzstd1 libreadline8 libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Match the PostgreSQL server version for Rails structure.sql dump/load.
COPY --from=postgres_tools /usr/lib/postgresql/17/bin/pg_dump /usr/local/bin/pg_dump
COPY --from=postgres_tools /usr/lib/postgresql/17/bin/psql /usr/local/bin/psql
COPY --from=postgres_tools /usr/lib/x86_64-linux-gnu/libpq.so.5* /usr/lib/x86_64-linux-gnu/
