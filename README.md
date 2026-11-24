# Community Voices

Generates a weekly "Community Voices Document" for the [Ruby on Rails Discourse forum](https://discuss.rubyonrails.org):
what the community discussed in the past week, and what it is likely to discuss next.

> Status: **Milestone 2** — posts are ingested, chunked and embedded into pgvector for similarity search.
> Report generation comes next.

## Requirements

- Ruby 3.4 (see `.ruby-version`)
- Docker (for Postgres + pgvector)
- [Ollama](https://ollama.com) (for local embeddings)

Everything runs locally and free of charge: the forum's public JSON API needs no key, and embeddings come
from a model running on your machine.

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

Then download the embedding model (about 275 MB, once) and make sure Ollama is running:

```sh
ollama pull nomic-embed-text
ollama serve                  # not needed if the Ollama desktop app is already running
```

The model and server can be changed with `OLLAMA_EMBEDDING_MODEL` (default `nomic-embed-text`) and
`OLLAMA_BASE_URL` (default `http://localhost:11434/v1`). A different model must also produce 768-dimension
vectors, the size of the `chunks.embedding` column.

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

## Chunking, embedding and search

```sh
bin/rails chunks:sync                                     # split posts into chunks
bin/rails embed:pending                                   # embed chunks that have no embedding yet
bin/rails "pipeline:refresh[7]"                           # ingest the last 7 days, then sync, then embed
bin/rails "search:similar[upgrading to a new Rails version]"  # print the 5 closest chunks
```

Example output:

```
Synced chunks for 47 posts: 3 created, 52 unchanged, 1 replaced, 0 deleted.
Embedded 4 chunks.
```

`search:similar` prints each match's cosine distance (0 is identical), post title and the start of the chunk.

Reruns are cheap: a chunk whose content is unchanged keeps its embedding, so only new or edited text is sent
to Ollama, and syncing unchanged posts writes nothing.

If Ollama is not running or the model is missing, the tasks stop with the command that fixes it.

## Running the tests

```sh
bundle exec rspec
```

HTTP is stubbed with WebMock against real API responses saved in `spec/fixtures/discourse/`. No test reaches
the network or Ollama: the test environment embeds with `Embeddings::FakeClient`, which derives a
deterministic vector from each text, while similarity search still runs against real pgvector.

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

## How chunking, embedding and search work

| Class | Responsibility |
| --- | --- |
| `Chunking::TextSplitter` | Packs paragraphs into pieces of a maximum length with a small overlap, hard-splitting oversized paragraphs at word boundaries |
| `Chunking::PostChunker` | Turns a post into chunk texts: title prefix, minimum content length, and a cap on chunks per post |
| `Chunking::ChunkSyncer` | Stores a post's chunks, keeping unchanged ones (same SHA256 digest) and their embeddings |
| `Embeddings::OllamaClient` | Embeds documents in batches and queries one at a time through `ruby_llm`, adding nomic's task prefixes |
| `Embeddings::FakeClient` | Deterministic, offline embeddings for the test suite |
| `Embeddings::PendingEmbedder` | Embeds every chunk without an embedding, in batches of 32 |
| `Search::SimilarChunks` | Returns the chunks nearest to a query by cosine distance, optionally only from posts since a given time |

Each chunk starts with its post's title, so it makes sense on its own when retrieved. Chunks hold at most 1,500
characters and overlap the previous chunk by up to 150. Posts under 20 characters ("Thanks!", "+1") are skipped.

**Handling overly large amounts of data:** `PostChunker::MAX_CHUNKS_PER_POST` (8) caps how many chunks one post
can contribute, so a single huge post cannot crowd everything else out of search results. Embedding runs in
batches and only touches pending chunks, so cost grows with new content rather than with the size of the database.

`Embeddings.client` is the one place that picks the implementation: `FakeClient` in tests, `OllamaClient`
everywhere else. Both implement the `Embeddings::Client` interface (`#embed_documents`, `#embed_query`).
Chunks are searched through an HNSW index with `vector_cosine_ops`.
