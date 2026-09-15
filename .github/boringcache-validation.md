# BoringCache validation for finance-query issue 494

This branch contains a controlled comparison for
[Verdenroz/finance-query#494](https://github.com/Verdenroz/finance-query/issues/494).
The issue reports that the server and MCP Docker jobs take 15–21 minutes after
`Cargo.lock` or manifest changes because the two jobs rebuild overlapping Rust
dependencies. Their current `type=gha,mode=max` exports BuildKit layers but does
not preserve the contents of the Dockerfiles' Cargo cache mounts.

## What the branch tests

The workflow builds the server and MCP images from an exact upstream commit on
separate clean GitHub-hosted `ubuntu-latest` runners for each provider. Both
providers build the same two targets in one Docker Bake invocation and run the
same image health checks.

- The GitHub control keeps the repository's existing independent
  `type=gha,mode=max` scopes, `docker-server` and `docker-mcp`.
- The BoringCache arm uses the official Docker adapter, one workspace tag
  family for the two Bake targets, and the adapter's opt-in native cache-mount
  persistence.
- BoringCache obtains a short-lived credential through GitHub Actions OIDC.
  The workflow contains no static BoringCache token.
- Publish jobs may update cache state. The clean-runner verification jobs use
  restore-only trust.
- All third-party actions use immutable commit SHAs. BoringCache uses
  `boringcache/one@1039999c65011be670f5655e0e48ad556188ab12` and CLI v1.30.4.

The test retains the upstream release profile, including fat LTO, and passes
the existing `CARGO_FEATURES=translation` argument. It does not use the cheaper
CI profile proposed in the issue. Normal layer-cache export does not preserve
cache-mount contents; the BoringCache arm enables mount persistence through the
documented `mount-cache = true` product path.

## Rolling-source cohort

The commits were dispatched oldest to newest. Each run completed before the
next run began so each provider observed the same source sequence.

| Order | Source revision | Change represented |
| ---: | --- | --- |
| 1 | `d7faa19b4363066e2ae10e5cac8356df2d6d9a7c` | Initial seed; generated-output update |
| 2 | `6ea3108469eab9d8a8b66cc625063e52797a97e4` | Generated-output-only update |
| 3 | `6250e615def5735a5ed1cb5cd2359afce4f3afeb` | Rust source changes with an unchanged lockfile |
| 4 | `59c8c317260bdb3f9118ed5561b94c4f9b896a6e` | Rust source, manifest, and `Cargo.lock` changes |
| 5 | `a9d680732f02eb94693676333602f6335010ddab` | `CHANGELOG.md`-only update after the lockfile change |

## Results

The table reports the duration of the build action step, not the total job
duration. For BoringCache, the parenthetical value is the wrapped Docker command
duration from the retained `boringcache/one` evidence. The clean-runner columns
measure a second build at the same source revision after the publish job.

| Source and run | GitHub publish | BoringCache publish | GitHub clean restore | BoringCache clean restore |
| --- | ---: | ---: | ---: | ---: |
| [`d7faa19` run 34980455589](https://github.com/boringcache/finance-query/actions/runs/34980455589) | 30m10s | 35m27s (35m24s) | 11s | 11s (9.9s) |
| [`6ea3108` run 34984663113](https://github.com/boringcache/finance-query/actions/runs/34984663113) | 14s | 13s (12.3s) | 11s | 21s (20.1s) |
| [`6250e61` run 34984968036](https://github.com/boringcache/finance-query/actions/runs/34984968036) | 27m10s | 30m56s (30m54s) | 10s | 16s (12.5s) |
| [`59c8c31` run 34988729795](https://github.com/boringcache/finance-query/actions/runs/34988729795) | 30m07s | 24m08s (24m04.5s) | 12s | 29s (24.1s) |
| [`a9d6807` run 34992288403](https://github.com/boringcache/finance-query/actions/runs/34992288403) | 15s | 12s (11.1s) | 7s | 11s (9.6s) |

Every completed publish and clean-runner restore built both images and passed
the server and MCP health checks.

The publish logs provide separate evidence for Cargo work inside the layer. The
counts below are the number of Cargo `Compiling` progress lines, not a cache hit
counter. They show how many crate compilation events Cargo reported across the
two targets.

| Source | GitHub publish | BoringCache publish |
| --- | ---: | ---: |
| `d7faa19` | 410 | 409 |
| `6ea3108` | 0 | 0 |
| `6250e61` | 370 | 5 |
| `59c8c31` | 376 | 13 |
| `a9d6807` | 0 | 0 |

The first run seeded each provider's independent cache and is not a warm
comparison. The generated-output update in the second run was a layer-cache hit
for both providers. On the real Rust source change in the third run,
BoringCache did not reduce the measured publish time: its build step was 3m46s
longer than the GitHub control. It did reduce Cargo's reported compilation
events from 370 to 5, which is direct evidence that the BoringCache arm reused
Cargo state outside the exported layer graph. The retained fat-LTO application
build, link, image export, and cache publication still determined that run's
end-to-end result.

On the source, manifest, and lockfile change in the fourth run, BoringCache
reduced reported compilation events from 376 to 13 and completed the publish
build 5m59s, or 19.9%, faster than the GitHub control. Both providers restored
the just-published images on clean runners in seconds. The BoringCache restore
step was 17s slower in that run. The following `CHANGELOG.md`-only revision was
a full layer-cache hit for both providers: BoringCache published in 12s versus
15s for the GitHub control, while its clean restore took 11s versus 7s.

## Interpretation and limits

- The measurements are one sample per source revision. GitHub assigned the
  same hosted runner class but not the same physical runner to each arm, so
  runner and network variance remain.
- Both targets run in one Bake invocation for both providers. This controls the
  provider comparison and allows a single builder to reuse its Cargo mounts
  between targets, but it does not reproduce the upstream workflow's two
  parallel Docker jobs or its total elapsed wall time.
- The GitHub control measures the repository's current separate GHA layer-cache
  scopes. It does not add `buildkit-cache-dance`, cargo-chef, or a cheaper Rust
  profile.
- The BoringCache Docker adapter creates target-specific cache references under
  the workspace tag family. The report does not treat one target's exported
  layer graph as the other target's graph.
- Clean restore proves that each provider can reproduce the just-published
  images from a new runner. It is not evidence that every individual Cargo
  object came from a persisted cache mount.
- BoringCache evidence reports `cache_result_not_evaluated` because setup
  prepares the cache backend but does not classify reuse inside the wrapped
  build. The timing table therefore uses GitHub step timestamps and the
  evidence's wrapped-command duration rather than assigning a hit rate.
- The comparison covers five adjacent upstream commits selected to include a
  seed, unchanged dependency inputs, real Rust changes, a lockfile change, and
  a following warm revision. It does not establish long-term cache retention
  or repository-wide runner-minute savings.

## Reproduction

Run the workflow from the validation branch with a 40-character upstream
commit:

```console
gh workflow run boringcache-validation.yml \
  --repo boringcache/finance-query \
  --ref boringcache-validation \
  -f providers=all \
  -f source_ref=<upstream-commit-sha>
```

The BoringCache jobs require the repository-to-workspace OIDC connection in
`.github/workflows/boringcache-connect.yml`. The validation workflow itself
requests only `contents: read` globally and grants `id-token: write` only to
the BoringCache jobs.
