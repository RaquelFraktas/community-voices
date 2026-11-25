# Prompting
This app was generated with prompts broken up in 5 different Milestones.

#
I'm building a take-home coding challenge called "Community Voices" in Rails. Help me build it step by step. Do ONLY Milestone 1 below, then stop so I can review.

## The challenge (summary)
A web app that generates a "Community Voices Document": what an online community discussed in the past week, and a prediction of what it will discuss next week. It must use RAG (pgvector), ingest the community's posts automatically, and include an A/B comparison of the document generated with RAG vs. without RAG. Reviewers will git clone the repo, follow the README, and run it locally.

The community is the Ruby on Rails Discourse forum: https://discuss.rubyonrails.org (public JSON API, no auth).

## Hard constraints
- Zero cost. No paid APIs. LLM and embeddings will run locally via Ollama (`nomic-embed-text` for embeddings, 768 dims; `llama3.2` for chat), called through the `ruby_llm` gem. No AI code in Milestone 1, though.
- Postgres with pgvector, run via docker-compose (`pgvector/pgvector:pg17` image) — the database only; Rails runs natively.
- Rails 8, RSpec, WebMock. Faraday for HTTP.
- The reviewers value: self-documenting code, unit tests, compact functions, and Uncle Bob's Clean Code. Keep methods short, use intention-revealing names, put no logic in controllers, and give each service object a single responsibility. Avoid comments that restate the code.

## Milestone 1: ingest one week of Discourse topics into Postgres
1. `rails new community_voices -d postgresql -T`, add docker-compose.yml for pgvector, add the `neighbor`, `ruby_llm`, `faraday`, `rspec-rails`, and `webmock` gems, enable the vector extension, and set database.yml to read from ENV (defaulting to localhost / postgres / postgres).
2. `Post` model: source (string, e.g. "discourse"), source_id, title, body (plain text), author, url, posted_at, reply_count. Unique index on [source, source_id].
3. `Ingest::DiscourseClient`: thin HTTP wrapper with `latest(page:)` → GET /latest.json?page=N and `topic(id:)` → GET /t/{id}.json. Set a descriptive User-Agent and sleep briefly between requests.
4. `Ingest::DiscourseFetcher`: pages through /latest.json until topics fall outside a configurable window (default 7 days), fetches each topic, strips the HTML from each post's `cooked` field into plain text, and returns plain Ruby structs (not ActiveRecord objects). For topics with more posts than the first payload includes, fetch the rest via /t/{id}/posts.json?post_ids[]=... using `post_stream.stream`.
5. `Ingest::PostImporter`: upserts structs on [source, source_id] so reruns are idempotent.
6. `rake ingest:discourse[days]` wires these together and prints a summary.
7. Tests: before writing the client, fetch one real /latest.json and one real /t/{id}.json, save them under spec/fixtures/discourse/, and use them with WebMock. Unit-test each class in isolation.
8. A README with setup steps so far (docker compose up -d, bin/setup, rake ingest:discourse).

Design for later: the fetcher should be one implementation of a fetcher interface, because I'll add a Reddit fetcher (headless browser) and a fixture-based fetcher later.

Work in small steps, run the test suite after each one, and show me the actual ingested row counts at the end. Don't start chunking, embeddings, or report generation yet.

#
Milestone 1 is done: Discourse topics are ingested into `posts`. Read the existing code, CLAUDE.md, and README first, and follow the conventions already in place. Now do ONLY Milestone 2 below, then stop so I can review.

## Milestone 2: chunk posts and store embeddings in pgvector

Constraints as before: zero cost, local Ollama only (`nomic-embed-text`, 768 dims) via the `ruby_llm` gem, RSpec + WebMock, Clean Code (short methods, intention-revealing names, single-responsibility service objects, no comments that restate the code).

1. **Chunk model**: post_id (FK, cascade delete), position (integer), content (text), content_digest (string, SHA256 of content), embedding (`vector(768)`, nullable until embedded), retrievals_count (integer, default 0, for retrieval stats in a later milestone).
   - Use the `neighbor` gem: `has_neighbors :embedding, dimensions: 768`.
   - Add an HNSW index on embedding with `vector_cosine_ops`, a unique index on [post_id, position], and a scope `pending_embedding`.

2. **`Chunking::PostChunker`**: turns a Post into an array of chunk texts.
   - Prefix every chunk with the post title, so each chunk makes sense on its own.
   - Split on paragraph boundaries into chunks of about 1,500 characters max, with a small overlap. Hard-split any single paragraph that is over the limit.
   - Skip tiny or empty content below a minimum length.
   - Cap chunks per post (configurable, e.g. 8) so one huge thread can't dominate. This is part of the challenge's "handle overly large amounts of data" requirement, so name it clearly.
   - Pure Ruby with no database access, so it's easy to unit-test.

3. **`Chunking::ChunkSyncer`**: persists chunks for a post. If a chunk's content_digest is unchanged, keep it and its embedding. If the content changed, replace the chunk and clear its embedding. Delete chunks whose positions no longer exist. Rerunning on unchanged posts must cause zero writes.

4. **Embedding client interface** (`Embeddings::` namespace):
   - `embed_documents(texts) -> Array<Array<Float>>` and `embed_query(text) -> Array<Float>`.
   - `OllamaClient` adds nomic's task prefixes ("search_document: " for documents, "search_query: " for queries) and sends documents in batches if ruby_llm supports array input; otherwise it loops.
   - Read the model name and Ollama base URL from ENV, defaulting to `nomic-embed-text` and `http://localhost:11434/v1`.
   - If Ollama isn't reachable or the model isn't pulled, raise a clear error that says exactly what to run (`ollama serve`, `ollama pull nomic-embed-text`).
   - `FakeClient` is deterministic: it seeds a vector from a hash of the text and normalizes it to 768 dims. Same text gives the same vector. Use it in all tests.
   - Choose the implementation in one place (e.g. `Embeddings.client`), with the fake used in the test environment.

5. **`Embeddings::PendingEmbedder`**: embeds all chunks with a null embedding, in batches (configurable size, e.g. 32), and returns a count of how many it embedded.

6. **`Search::SimilarChunks`**: given a query string, embeds it with `embed_query` and returns the nearest N chunks with their cosine distance. Allow an optional `since:` time filter on post posted_at. Don't track retrieval counts yet; that comes in Milestone 3.

7. **Rake tasks**:
   - `rake chunks:sync`: chunks all posts and prints counts of created, unchanged, and replaced chunks.
   - `rake embed:pending`: embeds pending chunks and prints the count.
   - `rake pipeline:refresh[days]`: runs ingest, then sync, then embed.
   - `rake search:similar["query text"]`: prints the top 5 matches (post title, distance, first 100 chars) so I can sanity-check retrieval by hand.

8. **Tests**: unit-test the chunker thoroughly (boundaries, overlap, cap, skipping tiny content), the syncer's idempotency and change detection, PendingEmbedder with FakeClient, and OllamaClient with WebMock stubs of the Ollama HTTP endpoint (including prefixes and the helpful error). Test SimilarChunks against real pgvector using FakeClient vectors. No test may hit the network or real Ollama.

9. **README**: add the Ollama setup steps (`ollama pull nomic-embed-text`) and the new rake tasks.

Work in small steps, run the full test suite after each one, and finish by running `rake pipeline:refresh[7]` against real Ollama. Show me the counts of posts, chunks, and embedded chunks, plus the output of two `search:similar` queries ("upgrading to a new Rails version" and "deployment problems"). Don't build report generation or the visualization yet.

#
Milestones 1–2 are done: posts are ingested, chunked, and embedded in pgvector, and `Search::SimilarChunks` works. Read the existing code, CLAUDE.md, and README first, and follow the established conventions. Do ONLY Milestone 3 below, then stop so I can review.

## Milestone 3: generate the Community Voices Document, with RAG vs. without RAG

Constraints as before: zero cost, local Ollama only via `ruby_llm` (chat model from ENV, default `llama3.2`), RSpec + WebMock, Clean Code (short methods, intention-revealing names, single-responsibility service objects, thin controllers, no comments that restate the code).

### Part A: adjustments from the Milestone 2 review (do these first)

1. **Chunk replacement creates a new row.** Change `Chunking::ChunkSyncer` so that a changed chunk is deleted and a new row inserted (new id), not updated in place. Unchanged chunks keep their row, embedding, and retrievals_count. Update the syncer tests; the zero-writes-on-rerun test must still pass.

2. **Time-filtered search returns full results.** In `Search::SimilarChunks`, when `since:` is given, run the query inside a transaction with `SET LOCAL hnsw.iterative_scan = relaxed_order`, so filtered searches still return N results once several weeks are ingested. Add a test that creates chunks across several weeks and asserts that a `since:`-filtered search returns N results, all from the target window.

### Part B: report generation and comparison

3. **Chat client interface** (`Llm::` namespace, mirroring `Embeddings::`):
   - `complete(system:, user:) -> String`.
   - `OllamaChatClient` reads the model from ENV. If Ollama is down or the model isn't pulled, it raises a clear error that says exactly what to run.
   - `FakeChatClient` returns canned text for tests.
   - Choose the implementation in one place (`Llm.client`), with the fake used in the test environment.

4. **Models**:
   - `Report`: week_of (date, start of the 7-day window), variant (enum: rag, baseline), status (enum: pending, generating, complete, failed), model_name, prompt (text, the full prompt sent), body (markdown), error_message, generation_seconds (float).
   - `Retrieval`: report_id, chunk_id (foreign key with `on_delete: :nullify`, so history survives chunk replacement), content_snapshot (text, the chunk content at retrieval time), post_title_snapshot, post_url_snapshot, query_label (string), rank (integer), distance (float).
   - Creating a Retrieval increments `chunks.retrievals_count`. Make sure this still works when chunk_id is later nulled.

5. **`Reports::ContextRetriever`**: builds the RAG context for a week.
   - Runs a configurable list of facet queries through `Search::SimilarChunks`, limited to posts in the window. Example facets: "new releases and upgrades", "bugs, errors, and help requests", "deployment and infrastructure", "gems and libraries", "architecture and best practices", "jobs, community, and events".
   - Takes the top K per facet, removes duplicate chunks, and caps the total (e.g. 16) so the prompt fits the context window.
   - Returns numbered context entries (number, post title, url, posted_at, chunk content) plus unsaved Retrieval attributes.
   - Put it behind a small interface (e.g. `#retrieve(week_of) -> RetrievalResult`) so a clustering-based retriever can replace it in Milestone 4.

6. **Prompt template**: one shared ERB template (e.g. `app/prompts/community_voices.md.erb`) used by both variants, so the only difference between them is the context.
   - Sections: Summary; Top discussions this past week; Recurring themes; Predictions for next week (each with its reasoning).
   - The RAG variant gets the numbered context and must cite sources as [n]. The baseline variant gets no context, but the same instructions and the same week dates.

7. **Generators**: `Reports::RagGenerator` and `Reports::BaselineGenerator`. Put the shared flow (mark generating → build prompt → call LLM → save body, timing, model name → mark complete; on error mark failed and save error_message) in one place, and keep each variant small. The RAG generator saves its Retrievals in the same transaction as the completed report.

8. **Background job**: `GenerateReportJob(report_id)`, using the Active Job adapter already configured for development.

9. **`Reports::ComparisonMetrics`**: pure Ruby, given a RAG report, a baseline report, and the RAG report's retrievals. Each metric is a small, well-named method:
   - Valid citations: [n] that match a real context entry.
   - Invalid citations: [n] with no matching entry.
   - Distinct real posts cited.
   - Real post titles mentioned (fuzzy match against posts in the window), computed for both variants.
   - Word count.
   - Generation time.

10. **UI** (plain Rails views with minimal styling; no JS framework):
    - `/` lists weeks that have posts, with a "Generate reports" button that creates both reports as pending and enqueues the jobs.
    - `/reports/compare?week_of=...` shows the RAG and baseline reports side by side, renders the markdown (add a free markdown gem), turns [n] citations into links to the source post URLs, shows the metrics table above both reports, and has a collapsible "Retrieved context" panel listing each retrieval's snapshot title, query_label, distance, and content_snapshot.
    - Pending or generating reports show their status and refresh automatically (Turbo or a simple meta refresh).

11. **Rake**: `rake reports:generate[week_of]` runs both generators synchronously and prints the metrics. Default to the most recent week.

12. **Tests** (no network, no real Ollama):
    - ContextRetriever with FakeClient embeddings: facets, dedupe, cap, time window.
    - Generators with FakeChatClient: status transitions, failure path, the prompt contains context for RAG and omits it for the baseline, retrievals saved with snapshots.
    - Retrieval history survives a chunk replacement: chunk_id becomes null and the snapshot is intact.
    - ComparisonMetrics, thoroughly, including invalid citations.
    - The counter cache.
    - A request spec for the compare page.

13. **README**: add `ollama pull llama3.2`, the context-length note (start Ollama with `OLLAMA_CONTEXT_LENGTH=8192`, since Ollama silently truncates long prompts otherwise), how to generate and view a comparison, and a short "How the A/B comparison works" section.

Work in small steps and run the full suite after each one. Finish by running `rake reports:generate` for the most recent week against real Ollama, and show me the metrics output and the first ~20 lines of each report. As before, end with a short "choices worth reviewing" list. Don't build clustering, trend analysis, or the embedding visualization yet.

#
Milestones 1–3 are done: ingestion, chunking, embeddings, and RAG vs. baseline report generation with a comparison page. Read the existing code, CLAUDE.md, and README first, and follow the established conventions. Do ONLY Milestone 4 below, then stop so I can review.

Constraints as before: zero cost, local Ollama only, RSpec + WebMock, Clean Code (short methods, intention-revealing names, single-responsibility service objects, thin controllers, no comments that restate the code).

## Milestone 4
### Part A: adjustments from the Milestone 3 review (do these first)

1. **Durable jobs in development.** Switch development from `:async` to Solid Queue, with its own queue database configured in database.yml so `bin/rails db:prepare` sets it up. One command must start both the web server and the job worker (`bin/dev` with Procfile.dev, or the Solid Queue Puma plugin; pick one and explain why). Tests keep using the test adapter.

2. **Stuck reports.** A report that has been `generating` for longer than a configurable timeout (default 10 minutes) counts as stale. Show it as failed, with a "Retry" button that re-enqueues it. Put the stale check in a model method or a small service, not in the view, and test it.

3. **Rename the metric.** Label invalid citations as "Citations to nonexistent sources" on the compare page and in the rake output. Keep a clear method name in `ComparisonMetrics`.

### Part B: themes, trends, and visualization

4. **Clustering models**:
   - `Clustering`: window_start, window_end, k, random_seed, created_at.
   - `Cluster`: clustering_id, label, centroid (`vector(768)`), size.
   - `ClusterMembership`: cluster_id, chunk_id (foreign key, cascade delete), distance_to_centroid, x, y (2D projection coordinates).
   - `Report` gets an optional `clustering_id`.

5. **`Themes::Clusterer`**: runs k-means over all embedded chunks in a multi-week window (configurable, default the 6 weeks ending at the report week).
   - Use the `rumale` gem (Numo-based). If it won't install cleanly, implement k-means in plain Ruby with Numo, keep it small, and tell me.
   - Choose k with a simple, documented rule (e.g. the best silhouette score for k in 3..8). Use a fixed random seed so results are reproducible.
   - Saves a Clustering with its Clusters and memberships.

6. **`Themes::Labeler`**: labels each cluster without an LLM. Use the top distinctive terms (TF-IDF over cluster post titles versus all titles in the window, minus stopwords, including generic Rails words like "rails", "ruby", "using"), shown as e.g. "migrations · production · rollback". Pure Ruby and unit-tested.

7. **`Themes::Projector`**: projects all chunk embeddings in the clustering to 2D with PCA (rumale), and saves x and y on each membership.

8. **`Themes::TrendAnalyzer`**: pure Ruby. For each cluster, count members per week across the window, and compute momentum = this week's share of chunks compared with the average share over previous weeks. Classify each cluster as rising, steady, fading, or new. Returns plain structs.

9. **`Reports::ThemeContextRetriever`**: a second implementation of the ContextRetriever interface from Milestone 3.
   - For each cluster with members in the report week, take the chunks from that week closest to the cluster centroid.
   - Order clusters by momentum, cap the total at 16, and number the entries [n] as before.
   - Saves Retrievals with query_label set to the cluster label.
   - Also returns the trend table.
   - Choose the retriever via ENV (`RAG_RETRIEVER=themes|facets`), defaulting to themes. Keep the facet retriever working.

10. **Prompt changes (RAG variant only)**: add a "Theme trends" section listing each theme's label, weekly counts, and trend classification, and instruct the model to base its "Predictions for next week" on rising and new themes and cite evidence with [n]. The baseline gets the same instructions and dates but no trend data, because the trend data comes from retrieval. Keep the rule that shared instructions come first, sources and trends last, and the citation rule at the very end. Update the test that enforces identical shared instructions.

11. **Embedding visualization page** at `/embeddings?week_of=...`:
    - Add Chart.js via importmap. Draw a scatter of the clustering's 2D points: color by cluster, point size by `chunks.retrievals_count`, points from the report week fully opaque and older weeks faded.
    - Tooltip shows the post title and cluster label. Clicking a point opens the post.
    - Add a legend with cluster labels and trend badges.
    - Data comes from a small JSON endpoint whose serialization lives outside the controller.
    - Link to this page from the compare page.

12. **Retrieval stats page** at `/retrievals/stats`:
    - The 20 most-retrieved chunks (title, snippet, retrievals_count, last retrieved at), the most-retrieved posts (summed over their chunks), and the most-retrieved cluster labels.
    - Put the queries in a query object, not the controller.

13. **Rake**: `rake themes:build[week_of]` runs the clusterer, labeler, and projector and prints each cluster's label, size, weekly counts, and trend. `reports:generate` builds the clustering automatically when the themes retriever needs one.

14. **Tests** (no network, no real Ollama):
    - Clusterer with synthetic vectors forming known separated groups: it finds them, and the same seed gives the same result.
    - Labeler term extraction.
    - Projector output shape.
    - TrendAnalyzer classifications, including the new and fading edge cases.
    - ThemeContextRetriever ordering, cap, and time window.
    - Prompt contains trends for RAG and omits them for the baseline.
    - Stale-report detection and retry.
    - The stats query object.
    - Request specs for the embeddings page, its JSON endpoint, and the stats page.

15. **README**: add the one-command dev startup, `rake themes:build`, the new pages, and a short "How themes and predictions work" section explaining clustering, the choice of k, PCA, and momentum in plain language.

Work in small steps and run the full suite after each one. Finish against real data and real Ollama:
- Run `rake themes:build` for the last complete week and show me its output.
- Run `rake reports:generate` for that week and show the metrics and the Predictions section of each report.
- Confirm the embeddings JSON endpoint returns points for every cluster.

As before, end with a short "choices worth reviewing" list. Don't build the recurring weekly job or seed data yet; that's Milestone 5.

#
Milestones 1–4 are done: ingestion, chunking, embeddings, RAG vs. baseline reports, theme clustering, trends, the embedding scatter plot, and retrieval stats. Read the existing code, CLAUDE.md, and README first, and follow the established conventions. Do ONLY Milestone 5 below. It is the final milestone, so the goal is a repo that a reviewer can clone and demo with no surprises.

Constraints as before: zero cost, local Ollama only, RSpec + WebMock, Clean Code (short methods, intention-revealing names, single-responsibility service objects, thin controllers, no comments that restate the code).
## Milestone 5
### Part A: adjustments from the Milestone 4 review (do these first)

1. **Stop citation inflation.**
   - Prompt: tell the model to cite at most 3 sources per sentence, and only ones that directly support it.
   - Metrics: count any single citation group (e.g. `[1][2][3][4]` or `[1]…[12]`) as citing at most 3 sources. Make "distinct real posts cited" the first, headline metric on the compare page and in the rake output.
   - Keep the test that shared instructions are identical for both variants. Add tests for the citation-group cap.

2. **Readable theme labels.** Add `Themes::LlmLabeler`: for each cluster, send the titles and short snippets of the ~5 chunks closest to its centroid to the chat model, and ask for a 2–4 word theme name, returned as plain text with no quotes. Sanitize and length-limit the result. If Ollama is unavailable or returns junk, fall back to the existing TF-IDF labeler. Choose the labeler in one place, and test both paths with FakeChatClient.

3. **Normalize vectors before clustering.** L2-normalize embeddings before k-means and PCA, so Euclidean distance there agrees with the cosine distance used in search. Run `rake themes:build` on the last complete week before and after the change, and show me both silhouette scores and both sets of cluster sizes. Keep the change only if the clusters are at least as good; otherwise revert and tell me.

### Part B: automation, seed data, and the reviewer experience

4. **Recurring weekly pipeline.**
   - `WeeklyPipelineJob` runs ingest → chunk sync → embed → themes build → generate both reports for the most recent complete week.
   - Each step is its own small service or existing task. The job only coordinates them, and it is idempotent: running it twice for the same week causes no duplicate posts or chunks, and skips report generation if a complete pair already exists for that week unless `force: true`.
   - Schedule it in `config/recurring.yml` (Solid Queue) for Monday mornings, active in development too, so the demo can show it.
   - Add `rake pipeline:weekly[force]` to run it on demand.
   - Log a one-line summary per step.
   - Test the job with all steps stubbed: order, idempotency, and stopping cleanly with a clear message if a step fails.

5. **Seed data with precomputed embeddings.**
   - `rake seeds:export` writes posts, chunks (with embeddings), clusterings, clusters, memberships, reports, and retrievals for the last ~6 weeks to compressed JSON under `db/seeds/`.
   - `bin/rails db:seed` imports it without needing Ollama or the network, so every page (compare, embeddings, stats) works immediately after setup.
   - The import is idempotent.
   - Generate the export from my real local data once Part A is done, and commit it. Keep it reasonably small (report the file size).
   - Test the round trip: export then import gives identical records.

6. **Status page** at `/status`: shows whether Postgres, pgvector, and Ollama are reachable, whether each configured model is pulled, record counts, the latest week ingested, and the next scheduled pipeline run. Put each check in a small service object. This is my pre-demo checklist, and it's useful for reviewers too. Link it in the nav.

7. **Docker Ollama option.** If it isn't already there, add an optional `ollama` profile to docker-compose.yml: an `ollama/ollama` service with a volume, `OLLAMA_CONTEXT_LENGTH=8192`, and a healthcheck, plus a one-shot service that pulls the two models. `docker compose up -d` must still start only Postgres.

8. **`bin/setup`**: installs gems, prepares all databases (including the queue database), loads seeds, and prints next steps. It checks whether Ollama is reachable and which models are missing, printing exact commands if so, but doesn't fail without Ollama, since the seeded demo works without it.

9. **README rewrite**, aimed at a reviewer who has never seen the project:
   - **Quickstart**: three or four commands from clone to a running app, with the seeded demo working before Ollama is set up.
   - **Ollama setup**: native (recommended on Mac, uses the GPU) vs. the Docker profile (CPU only on Mac, slower), with the context-length note.
   - **Demo walkthrough**: which pages to open, in which order, and what each shows.
   - **How it maps to the challenge**: a short section per requirement 1–5, pointing to the relevant pages, classes, and rake tasks.
   - **Architecture**: a Mermaid diagram of the pipeline (Discourse → fetcher → posts → chunker → embeddings → pgvector → retrievers → prompt → Ollama → reports) plus a short paragraph.
   - **A/B findings**: real numbers from the seeded reports (distinct posts cited, citations to nonexistent sources, titles mentioned), plus 3–5 sentences of honest observations. Leave a clearly marked spot where I'll add my own notes.
   - **Decisions & tradeoffs**: local Ollama for zero cost and zero credentials (a hosted model would improve quality and latency, and `ruby_llm` makes that a config change); Discourse over Reddit because of Reddit's API approval policy and its shutdown of unauthenticated JSON in 2026; how large data is handled (score and length filters, chunk caps, digest-based skipping, batching, retrieval caps); facet vs. theme retrieval; the weak-silhouette caveat.
   - **Limitations & future work**: a Reddit fetcher (headless browser or approved API) through the existing fetcher interface, a hosted-LLM option, better theme labels.
   - **Running tests**.

10. **Final quality pass.** Run the full suite and RuboCop (the Rails 8 omakase config), and fix any offenses. Remove dead code, unused gems, and leftover debug output. Confirm no secrets or local paths are committed.

11. **Fresh-clone check.** Clone the repo into a temporary directory and follow the README Quickstart exactly as a reviewer would, using a fresh database name. Confirm the compare, embeddings, stats, and status pages all return 200 with seeded data. Report every step where the README was wrong or unclear, and fix it.

Finish with: the full test count and RuboCop result, the seed file size, the before/after silhouette numbers from step 3, the fresh-clone check result, and a short "choices worth reviewing" list.