# Community Voices

Generates a weekly "Community Voices Document" for the [Ruby on Rails Discourse forum](https://discuss.rubyonrails.org):
what the community discussed in the past week, and what it is likely to discuss next.

> Status: **Milestone 4** — posts are ingested, chunked, embedded and grouped into themes with weekly trends.
> The weekly document is generated twice, with and without retrieved forum context, and compared side by side.

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

In the browser, start the app with one command:

```sh
bin/dev
```

It starts the web server and the background job worker together, then open <http://localhost:3000>. The home
page lists every week that has posts. **Generate reports** creates both versions as background jobs and opens
the comparison page, which refreshes itself until both are done. You can also open a comparison directly at
`/reports/compare?week_of=2026-11-16`.

Weeks run Monday to Sunday. Jobs are stored in their own database (`community_voices_development_queue`,
created by `bin/setup` or `bin/rails db:prepare`) and run by Solid Queue inside the web server process, so a
report that was still generating is picked up again after a restart. A report still pending or generating
after 10 minutes (set `REPORT_GENERATION_TIMEOUT_MINUTES` to change it) is shown as failed with a **Retry**
button, and the page stops refreshing.

Pressing Ctrl-C prints a `ThreadError ... can't be called from trap context` trace after Solid Queue has
already shut down cleanly. It comes from Rails' logging during Puma's shutdown and does not affect any jobs.

### Other pages

| Page | What it shows |
| --- | --- |
| `/embeddings?week_of=2026-11-16` | Every chunk of the six weeks as a point on a 2D map, colored by theme, with the report week highlighted. Linked from the comparison page |
| `/embeddings.json?week_of=2026-11-16` | The data behind the map |
| `/retrievals/stats` | The chunks, posts and themes that RAG reports retrieve most often |

## Building themes

```sh
bin/rails themes:build                 # the six weeks ending with the most recent complete week
bin/rails "themes:build[2026-11-16]"   # the six weeks ending with that week
```

It prints each theme's label, size, chunks per week and trend:

```
7 themes from 88 chunks, Oct 12 – Nov 22, 2026 (silhouette 0.11, seed 42)

Theme                             Size  Weekly (Oct 12 → Nov 16)  Trend
compound · limitations · objects  2     0 0 0 0 0 2               new
check · migration · production    24    1 3 7 2 5 6               rising (momentum 1.66)
ractor · safe · releases          36    9 4 5 8 5 5               steady (momentum 0.76)
api · association · correlating   8     0 8 0 0 0 0               fading (momentum 0.0)
```

You rarely need to run it by hand: `reports:generate` and the **Generate reports** button build the week's
themes when there are none yet. Set `RAG_RETRIEVER=facets` to go back to Milestone 3's fixed facet queries.

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
Searches run with `hnsw.iterative_scan = relaxed_order` (pgvector 0.8+). Without it, HNSW finds its nearest
candidates first and drops unwanted ones afterwards, both rows outside a time filter and deleted rows not yet
vacuumed, so a search can come back with fewer matches than asked for, or none.

## How the A/B comparison works

Each week's document is written twice by the same chat model, from the same prompt template
(`app/prompts/community_voices.md.erb`), with the same week dates and instructions:

- **RAG** gets numbered excerpts from that week's forum posts and a table of theme trends, and must cite the
  excerpts as `[n]`.
- **Baseline** gets neither, so it can only draw on what the model already knows.

Retrieved data is the only difference, so differences between the two documents come from retrieval.

By default, `Reports::ThemeContextRetriever` builds the RAG context from the week's themes (see below): for
each theme with posts that week, the chunks closest to the theme's center, taking the themes with the most
momentum first. It interleaves the themes by rank, removes duplicates, and keeps at most 16 chunks so the
prompt fits the context window. `Reports::ContextRetriever` (`RAG_RETRIEVER=facets`) instead runs six fixed
facet queries ("new releases and upgrades", "deployment and infrastructure", ...). Every chunk used is stored
as a `Retrieval` with a snapshot of its content, title and URL, so a report stays explainable after the chunk
is edited or deleted.

The comparison page shows these metrics above the two documents:

| Metric | What it tells you |
| --- | --- |
| Valid citations | `[n]` that point at a real context entry |
| Invalid citations | `[n]` with no matching entry. Every citation in the baseline is invalid, because it was given no sources |
| Distinct posts cited | How many different forum posts the valid citations cover |
| Post titles mentioned | How many of the week's real thread titles appear in the text (fuzzy match within one line) |
| Words, generation time | Length and cost of each version |

Citations in the RAG document link to their source posts. Invalid citations are struck through in red. The
**Retrieved context** panel lists each retrieved chunk with the theme (or facet) that found it and its cosine
distance.

A large valid-citation count is not always a good sign: a model that ends a sentence with every source
(`[1][2]…[12]`) scores twelve valid citations for one claim. Read the count together with distinct posts cited.

| Class | Responsibility |
| --- | --- |
| `Llm::OllamaChatClient` / `Llm::FakeChatClient` | Chat completions through `ruby_llm`; `Llm.client` picks one |
| `Reports::Retriever` | The retriever interface: interleaves, de-duplicates, caps and numbers candidates; `RAG_RETRIEVER` picks the implementation |
| `Reports::ThemeContextRetriever` | Builds the RAG context from the week's themes, ordered by momentum, with their trend table |
| `Reports::ContextRetriever` | Builds the RAG context from fixed facet queries |
| `Reports::PromptBuilder` | Renders the shared prompt template |
| `Reports::RagGenerator` / `Reports::BaselineGenerator` | Write one report; the shared flow lives in `Reports::Generator` |
| `GenerateReportJob` | Runs a generator in the background |
| `Reports::ComparisonMetrics` | Computes the comparison metrics (plain Ruby) |
| `Reports::Comparison` | The latest RAG and baseline reports for a week, with their retrievals and metrics |
| `Reports::MarkdownRenderer` | Renders a report as safe HTML with linked citations |

## How themes and predictions work

**Clustering.** Every embedded chunk from the six weeks ending with the report week is a point in a
768-dimension space, where chunks about similar things sit close together. K-means splits those points into
*k* groups (themes) by repeatedly assigning each point to its nearest group center and moving each center to
the middle of its points.

**Choosing k.** The clusterer tries every k from 3 to 8 and keeps the one with the best *silhouette score*,
which measures how much closer each chunk is to its own theme than to the next nearest one (1 is perfectly
separated, 0 is overlapping). A fixed random seed (42) means the same data always gives the same themes.
Forum text overlaps a lot, so expect low scores, around 0.1: the themes are useful groupings, not sharp
categories.

**Labels.** Each theme is named by the three words that best set its post titles apart from all titles in the
window (TF-IDF), ignoring stop words and words every Rails thread uses, such as "rails", "ruby" and "using".
No language model is involved.

**The map.** PCA (principal component analysis) flattens the 768 dimensions to the two directions in which the
chunks differ most, which gives the x and y of each point on the embedding map. Distances on the map are
approximate: two dimensions cannot keep all 768 apart.

**Momentum and trends.** For each theme, count its chunks per week. Its *share* of a week is its chunks divided
by all chunks that week. *Momentum* is this week's share divided by the theme's average share in the earlier
weeks (weeks with no chunks at all, such as weeks before ingestion started, are left out). Then:

| Trend | Rule |
| --- | --- |
| new | No chunks in earlier weeks, some this week |
| rising | Momentum of 1.5 or more |
| fading | Momentum of 0.67 or less, or no chunks this week |
| steady | Anything else |

**Predictions.** Both versions are told to base their predictions on rising and new themes. Only the RAG version
gets the trend table and the excerpts behind it, and must cite them, so its predictions point at real threads
that are growing. The baseline has to guess.

| Class | Responsibility |
| --- | --- |
| `Themes::KMeansSelector` | Runs k-means for each k and keeps the best silhouette score (plain Numo math) |
| `Themes::Clusterer` | Clusters a window's chunks and saves the `Clustering`, its `Cluster`s and memberships |
| `Themes::Labeler` | Names clusters by their most distinctive title words (plain Ruby) |
| `Themes::Projector` | Stores each chunk's 2D position from PCA |
| `Themes::Builder` | Runs the three steps above for a week |
| `Themes::TrendAnalyzer` | Weekly counts, momentum and trend for each cluster (plain Ruby) |
| `Themes::EmbeddingMapSerializer` | The JSON behind the embedding map |
| `RetrievalStatsQuery` | The queries behind the retrieval stats page |
