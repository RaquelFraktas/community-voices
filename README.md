# Community Voices

Generates a weekly "Community Voices Document" for the [Ruby on Rails Discourse forum](https://discuss.rubyonrails.org):
what the community discussed in the past week, and what it is likely to discuss next.

> Status: **Milestone 3** — posts are ingested, chunked and embedded, and the weekly document is generated
> twice, with and without retrieved forum context, so the two can be compared side by side.

## Requirements

- Ruby 3.4 (see `.ruby-version`)
- Docker (for Postgres + pgvector)
- [Ollama](https://ollama.com) (for local embeddings and the chat model)

Everything runs locally and free of charge: the forum's public JSON API needs no key, and both models run on
your machine.

## Setup

```sh
docker compose up -d          # Postgres 17 with pgvector on localhost:5432
bin/setup --skip-server       # installs gems, creates and migrates the databases
```

The database connection reads `DB_HOST`, `DB_PORT`, `DB_USERNAME` and `DB_PASSWORD`, defaulting to
`localhost`, `5432`, `postgres`, `postgres`. If port 5432 is already taken by a local Postgres, pick another
port for both Docker and Rails:

```sh
export DB_PORT=5434
docker compose up -d
bin/setup --skip-server
```

Check that nothing else listens on the port you pick (`lsof -nP -iTCP:5434 -sTCP:LISTEN` should show only
Docker). A local Postgres on the same port answers `localhost` first, and if it happens to have a `postgres`
user, Rails connects to it without any error.

Then download the models (about 275 MB and 2 GB, once):

```sh
ollama pull nomic-embed-text
ollama pull llama3.2
```

**Start Ollama with a larger context window.** The RAG prompt is about 5,000 tokens, and Ollama silently cuts
off prompts longer than its context length instead of reporting an error:

```sh
OLLAMA_CONTEXT_LENGTH=8192 ollama serve
```

If you use the Ollama desktop app instead, run `launchctl setenv OLLAMA_CONTEXT_LENGTH 8192` and restart the app.

The models and server can be changed with `OLLAMA_EMBEDDING_MODEL` (default `nomic-embed-text`),
`OLLAMA_CHAT_MODEL` (default `llama3.2`) and `OLLAMA_BASE_URL` (default `http://localhost:11434/v1`).
A different embedding model must also produce 768-dimension vectors, the size of the `chunks.embedding` column.

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

## Generating and comparing reports

From the terminal:

```sh
bin/rails reports:generate                 # the most recent complete week
bin/rails "reports:generate[2026-11-16]"   # the week containing that date
```

It writes both versions of the document, one after the other, and prints the comparison metrics.

In the browser, run `bin/dev` and open <http://localhost:3000>. The home page lists every week that has posts.
**Generate reports** creates both versions as background jobs and opens the comparison page, which refreshes
itself until both are done. You can also open a comparison directly at `/reports/compare?week_of=2026-11-16`.

Weeks run Monday to Sunday. In development, jobs run in the web server's process (Active Job's default
`:async` adapter), so restarting the server abandons reports that are still generating. A report still
pending or generating after 10 minutes (`Report::GENERATION_TIMEOUT`) is shown as failed with a **Retry**
button, and the page stops refreshing.

## Running the tests

```sh
bundle exec rspec
```

HTTP is stubbed with WebMock against real API responses saved in `spec/fixtures/discourse/`. No test reaches
the network or Ollama: the test environment embeds with `Embeddings::FakeClient`, which derives a
deterministic vector from each text, and writes with `Llm::FakeChatClient`, which returns canned markdown.
Similarity search still runs against real pgvector.

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
| `Chunking::ChunkSyncer` | Stores a post's chunks, keeping unchanged ones (same SHA256 digest) and their embeddings; a changed chunk is replaced by a new row |
| `Embeddings::OllamaClient` | Embeds documents in batches and queries one at a time through `ruby_llm`, adding nomic's task prefixes |
| `Embeddings::FakeClient` | Deterministic, offline embeddings for the test suite |
| `Embeddings::PendingEmbedder` | Embeds every chunk without an embedding, in batches of 32 |
| `Search::SimilarChunks` | Returns the chunks nearest to a query by cosine distance, optionally only from posts within a time window |

Each chunk starts with its post's title, so it makes sense on its own when retrieved. Chunks hold at most 1,500
characters and overlap the previous chunk by up to 150. Posts under 20 characters ("Thanks!", "+1") are skipped.

**Handling overly large amounts of data:** `PostChunker::MAX_CHUNKS_PER_POST` (8) caps how many chunks one post
can contribute, so a single huge post cannot crowd everything else out of search results. Embedding runs in
batches and only touches pending chunks, so cost grows with new content rather than with the size of the database.

`Embeddings.client` is the one place that picks the implementation: `FakeClient` in tests, `OllamaClient`
everywhere else. Both implement the `Embeddings::Client` interface (`#embed_documents`, `#embed_query`).
Chunks are searched through an HNSW index with `vector_cosine_ops`.
Time-filtered searches run with `hnsw.iterative_scan = relaxed_order` (pgvector 0.8+). Without it, HNSW finds
its nearest candidates across all weeks first and filters by date afterwards, so a search for one week can
come back with fewer matches than asked for, or none.

## How the A/B comparison works

Each week's document is written twice by the same chat model, from the same prompt template
(`app/prompts/community_voices.md.erb`), with the same week dates and instructions:

- **RAG** gets numbered excerpts from that week's forum posts and must cite them as `[n]`.
- **Baseline** gets no excerpts, so it can only draw on what the model already knows.

The context is the only difference, so differences between the two documents come from retrieval.

`Reports::ContextRetriever` builds the RAG context. It runs six facet queries ("new releases and upgrades",
"bugs, errors, and help requests", "deployment and infrastructure", "gems and libraries", "architecture and
best practices", "jobs, community, and events"), each limited to posts from that week. It takes the top 4
chunks per facet, interleaves the facets by rank, removes duplicates, and keeps at most 16 chunks so the prompt
fits the context window. Every chunk used is stored as a `Retrieval` with a snapshot of its content, title and
URL, so a report stays explainable after the chunk is edited or deleted.

The comparison page shows these metrics above the two documents:

| Metric | What it tells you |
| --- | --- |
| Valid citations | `[n]` that point at a real context entry |
| Invalid citations | `[n]` with no matching entry. Every citation in the baseline is invalid, because it was given no sources |
| Distinct posts cited | How many different forum posts the valid citations cover |
| Post titles mentioned | How many of the week's real thread titles appear in the text (fuzzy match within one line) |
| Words, generation time | Length and cost of each version |

Citations in the RAG document link to their source posts. Invalid citations are struck through in red. The
**Retrieved context** panel lists each retrieved chunk with the facet that found it and its cosine distance.

| Class | Responsibility |
| --- | --- |
| `Llm::OllamaChatClient` / `Llm::FakeChatClient` | Chat completions through `ruby_llm`; `Llm.client` picks one |
| `Reports::ContextRetriever` | Builds the numbered RAG context for a week, behind the `Reports::Retriever` interface |
| `Reports::PromptBuilder` | Renders the shared prompt template |
| `Reports::RagGenerator` / `Reports::BaselineGenerator` | Write one report; the shared flow lives in `Reports::Generator` |
| `GenerateReportJob` | Runs a generator in the background |
| `Reports::ComparisonMetrics` | Computes the comparison metrics (plain Ruby) |
| `Reports::Comparison` | The latest RAG and baseline reports for a week, with their retrievals and metrics |
| `Reports::MarkdownRenderer` | Renders a report as safe HTML with linked citations |
