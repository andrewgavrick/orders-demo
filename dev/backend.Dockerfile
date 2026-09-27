FROM ruby:3.4.10-slim-bookworm

RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
