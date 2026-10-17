# Performance evidence

## Scope

Review base: `43d72cd84a5bdae2954d895c7e058db696754a87`.
Measurements below are a deterministic **Linux SQLite microbenchmark**, not macOS UI,
GRDB, power, cold-disk or image-rendering measurements. SQLite version 3.53.1, x86_64,
in-memory databases, 1 warmup and 5 measured runs, median milliseconds. Fixtures contain
roughly 500 characters of synthetic text per item, one source app, and a match every
97 rows. Before/after use the same query shapes and data; the schema reserves a hash
column in both cases, but only the after case has the hash index/predicate.

Reproduce: `python3 Scripts/benchmark-storage.py`. Raw results:
[sqlite-benchmark.json](review/sqlite-benchmark.json).

| Rows | Dedup before → indexed lookup | Recent 200 before → after | ASCII before → after | CJK before → after |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 0.100 → 0.003 ms | 0.266 → 0.617 ms | 0.443 → 0.448 ms | 1.877 → 2.673 ms |
| 10,000 | 2.211 → 0.003 ms | 0.303 → 0.259 ms | 3.224 → 3.347 ms | 19.358 → 19.868 ms |
| 50,000 | 18.931 → 0.004 ms | 0.288 → 0.325 ms | 24.349 → 24.888 ms | 105.421 → 98.607 ms |

The hash index targets repeated full-payload comparisons. Hash computation is excluded
from this lookup microbenchmark and must be included in end-to-end ingest profiling.
The application still verifies the full payload, type and source app after hashing.
There is **no claim of a CJK, overall UI or percentage speedup**: search SQL is largely
unchanged and observed differences include measurement noise. CJK substring matching
remains linear; several terms or large bodies can cost considerably more than this fixture.

## Native measurements

`RepositoryPerformanceTests.testLargeHistoriesRemainBoundedAndSearchable` exercises real
GRDB at 1k/10k/50k rows and records `BENCH` timings in XCTest output. It asserts result
bounds/correctness, not machine-specific timing thresholds. See the review record for the
actual CI status. These fixtures use shorter text than the microbenchmark, so results are
not directly comparable. Native pre-change timings have not been collected.

Measured on macOS 15.7.9 arm64, Xcode 26.0.1 at commit
`2d36900b999e90191193e3dfa136a4dbc3e80f90`, in
[successful CI run 39052758182](https://github.com/sanwan99/magpie/actions/runs/39052758182).
One sample per query after fixture insertion, in-memory SQLite; includes repository
query/record decoding and excludes fixture setup and UI rendering. These are diagnostic
samples, not latency percentiles or a native before/after comparison.

| Rows | Recent 200 | ASCII search | CJK search |
| ---: | ---: | ---: | ---: |
| 1,000 | 1.138 ms | 0.641 ms | 1.203 ms |
| 10,000 | 1.224 ms | 3.539 ms | 8.902 ms |
| 50,000 | 1.283 ms | 15.551 ms | 42.588 ms |

Exact values, fixture scope and CI evidence: [native-benchmark.json](review/native-benchmark.json).

## Targeted changes and retained limits

- Add v5 payload hash index with bounded migration batches; preserve exact dedup semantics.
- Cancel old search publication immediately when the query changes, including debounce time;
  propagate cancellation to detached workers between expensive operations. A synchronous
  SQLite query already running is not forcibly interrupted.
- Keep the existing 200-item UI limit, 512-character card text and 32 MiB thumbnail cache.
  The selected/full payloads are still available for preview/paste. Extremely large text
  payloads can still use substantial memory even within a bounded item count.
- Keep 400 ms pasteboard polling for compatibility; unchanged ticks read only changeCount.
  Add 10% timer tolerance. No claimed battery saving without measurement.
- Explicitly release scrolling image/preview/task references on completion/cancellation.
  Screenshot drawing, PNG export and stitching still have main-thread work requiring
  Instruments profiling on real displays. No invented peak-memory or FPS results.

## Device profiling protocol

Use disposable histories at all three sizes; include ASCII, CJK and mixed queries, ten
rapid query changes, duplicate copies, 1 MiB text, repeated PNGs, 4K/Retina captures and a
40MP scrolling result. Record hardware, OS, Xcode, commit and warm/cold state. Use Instruments
Time Profiler / Allocations and the panel signposts. Measure P50/P95 show/search latency,
peak RSS and memory after cancel/close, plus responsiveness during capture and ingest.
Store synthetic fixture parameters and raw traces; do not commit real clipboard content.
