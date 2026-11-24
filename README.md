# Community Voices

Generates a weekly "Community Voices Document" for the [Ruby on Rails Discourse forum](https://discuss.rubyonrails.org):
what the community discussed in the past week, and what it is likely to discuss next.

> Status: **Milestone 1** — ingesting forum posts into Postgres. Embeddings, RAG and report generation come next.

## Requirements

- Ruby 3.4 (see `.ruby-version`)
- Docker (for Postgres + pgvector)

Everything runs locally and free of charge: the forum's public JSON API needs no key.

## Setup

```sh
docker compose up -d          # Postgres 17 with pgvector on localhost:5432
bin/setup --skip-server       # installs gems, creates and migrates the databases
```

The database connection reads `DB_HOST`, `DB_PORT`, `DB_USERNAME` and `DB_PASSWORD`, defaulting to
`localhost`, `5432`, `postgres`, `postgres`. If port 5432 is already taken by a local Postgres, pick another
port for both Docker and Rails:

```sh
export DB_PORT=5433
docker compose up -d
bin/setup --skip-server
```

## Ingesting posts

```sh
bin/rails ingest:discourse        # posts from the last 7 days
bin/rails "ingest:discourse[30]"  # posts from the last 30 days
```

Example output:

```
Fetched 12 posts (12 new). 12 posts stored in total.
```

Reruns are safe: posts are upserted on `[source, source_id]`, so edits are picked up and nothing is duplicated.

## Running the tests

```sh
bundle exec rspec
```

HTTP is stubbed with WebMock against real API responses saved in `spec/fixtures/discourse/`.

## How ingestion works

| Class | Responsibility |
| --- | --- |
| `Ingest::DiscourseClient` | Thin HTTP wrapper over the forum's JSON API (polite User-Agent, pause between requests) |
| `Ingest::DiscourseFetcher` | Pages `/latest.json` until topics fall outside the window, then collects each topic's posts |
| `Ingest::DiscoursePostMapper` | Turns one Discourse post into an `Ingest::FetchedPost` |
| `Ingest::HtmlToText` | Converts Discourse's rendered HTML into plain text, dropping quoted replies |
| `Ingest::PostImporter` | Idempotently upserts fetched posts into the `posts` table |
| `Ingest::Pipeline` | Runs any fetcher through the importer and summarizes the result |

Every source implements the `Ingest::Fetcher` interface (`#fetch` returns `Ingest::FetchedPost` values), so
new sources can be added without touching the importer or the pipeline.

Each Discourse post (opening post or reply) becomes one `Post` row, carrying its topic's title.
Hidden (community-flagged) posts and non-regular posts such as moderator actions are skipped.
