# BoringCache validation for finance-query issue 494

This branch runs the complete Docker portion of
[Verdenroz/finance-query#494](https://github.com/Verdenroz/finance-query/issues/494).
The issue reports that the independent server and MCP Docker jobs each rebuild
overlapping Rust dependencies after lockfile or manifest changes because the
existing GitHub BuildKit layer caches do not persist Cargo cache mounts.

## Outcome

BoringCache 1.30.4 does not provide a complete replacement for this workflow's
two-cache topology. The released Docker adapter can share Cargo cache-mount
archives between the server and MCP jobs only when both jobs use the same
BoringCache tag. That tag is also the OCI layer-cache manifest address. Each
independent publisher can therefore replace the layer graph restored by the
other job.

The shared Cargo mounts materially reduced compilation on source and lockfile
changes. They did not retain both image graphs. A later unchanged-source run
made three jobs complete in about one minute while the BoringCache server had
to rebuild after the MCP job had published last. This is a current product
limitation, not a successful prospect proof.

Separate server and MCP BoringCache tags would retain both image graphs, but
would also give them separate Cargo mount archives and would not test the
cross-job reuse requested in the issue. The released CLI and repository plan
schema expose `tag` and the boolean `mount-cache`; they do not expose a separate
mount-cache namespace or tag.

## Workflow under test

Each source revision starts four independent jobs at the same time:

- the upstream `Docker Build` path with its server Dockerfile, release profile,
  `CARGO_FEATURES=translation`, image load, health probe, Trivy scan, and SARIF
  upload;
- the upstream `MCP Docker Build` path with its MCP Dockerfile and corresponding
  build, health, scan, and upload steps;
- the same two jobs using the official BoringCache Docker adapter instead of
  `type=gha`.

The GitHub control retains independent `mode=max` layer-cache scopes for the
server and MCP images. The validation suffix gives this cohort new scopes so
earlier one-job Bake experiments cannot warm the control.

The BoringCache jobs retain the two upstream jobs and Dockerfiles. Their plans
use one shared tag to test cross-job Cargo target and registry reuse. The test
therefore includes the concurrent publication behavior required by the real
workflow instead of combining the images in one Bake job.

BoringCache authentication uses GitHub Actions OIDC. The workflow contains no
static BoringCache token. Publication is limited to the trusted fork branch.
All actions use immutable commit SHAs, cache failures are strict, and per-job
BoringCache evidence is retained.

The server health probe deliberately retains upstream's `|| true`; the MCP
health probe is gating. This branch does not change unrelated upstream test
semantics.

## Rolling-source cohort

The revisions ran oldest to newest, with one workflow completing before the
next started so both providers received the same cache history.

| Order | Source revision | Change represented |
| ---: | --- | --- |
| 1 | `d7faa19b4363066e2ae10e5cac8356df2d6d9a7c` | Initial seed; generated-output update |
| 2 | `6ea3108469eab9d8a8b66cc625063e52797a97e4` | Generated-output-only update |
| 3 | `6250e615def5735a5ed1cb5cd2359afce4f3afeb` | Rust source changes with an unchanged lockfile |
| 4 | `59c8c317260bdb3f9118ed5561b94c4f9b896a6e` | Rust source, manifest, and `Cargo.lock` changes |
| 5 | `a9d680732f02eb94693676333602f6335010ddab` | `CHANGELOG.md`-only update after the lockfile change |

## Complete-workflow results

Durations include the complete configured job. `Build` is the Docker build
step only. Total runner time is the sum of the server and MCP jobs; critical
path is the slower of the two concurrent jobs. Cargo `Compiling` lines are
supporting evidence, not a cache hit rate.

| Revision | Provider | Server job / build | MCP job / build | Total runner | Critical path | Compile lines server / MCP | Result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Seed | GitHub | 18m24s / 17m33s | 16m39s / 15m34s | 35m03s | 18m24s | 331 / 345 | Both complete |
| Seed | BoringCache | 22m26s / 21m51s | 16m34s / 15m27s | 39m00s | 22m26s | 331 / 345 | Both complete |
| Generated-only retry | GitHub | 1m25s / 16s | 1m11s / 10s | 2m36s | 1m25s | 0 / 0 | Both complete |
| Generated-only retry | BoringCache | 1m07s / 24s | 13m42s / 12m44s | 14m49s | 13m42s | 0 / 8 | Both complete |
| Source-only | GitHub | 22m00s / 21m09s | 16m36s / 15m30s | 38m36s | 22m00s | 294 / 307 | Both complete |
| Source-only | BoringCache | 19m53s / 19m13s | 10m49s / 9m50s | 30m42s | 19m53s | 6 / 3 | Both complete |
| Lockfile retry | GitHub | 1m02s / 10s | 15m52s / 14m53s | 16m54s | 15m52s | 0 / 311 | Both complete |
| Lockfile retry | BoringCache | 50s / 14s | 13m07s / 12m17s | 13m57s | 13m07s | 0 / 8 | Both complete |
| Post-lock unchanged | GitHub | Pending | Pending | Pending | Pending | Pending | Pending |
| Post-lock unchanged | BoringCache | Pending | Pending | Pending | Pending | Pending | Pending |

The source-only run reduced BoringCache total runner time by 7m54s (20.5%) and
critical path by 2m07s (9.6%) relative to the GitHub control. The complete
lockfile retry reduced total runner time by 2m57s (17.5%) and critical path by
2m45s (17.3%). The generated-only retry moved in the opposite direction:
BoringCache used 12m13s more runner time and added 12m17s to the critical path.
The shared tag contained the server graph, so MCP restored both Cargo mounts
but rebuilt the four workspace crates under the fat-LTO release profile.

## Transfer and reuse evidence

On the source-only run, the BoringCache server restored its target and registry
mounts in 11.946s and 6.814s. MCP restored them in 18.422s and 7.658s. The
BoringCache layer manifest imports took 0.3s and 0.1s, and each layer export
reported 0.6s. The corresponding GitHub manifest imports took 0.4s and 0.5s;
its layer exports took 12.1s and 13.7s. GitHub did not restore either Cargo
mount because `type=gha` does not export their contents.

On the lockfile retry, the BoringCache server was a complete graph hit. MCP
restored the shared target and registry mounts in 11.073s and 6.329s before
compiling eight crates. The GitHub MCP control emitted 311 compile lines.

The logs also show that BoringCache publications reused remote content rather
than uploading every owned body. Those counters are not equivalent to network
bytes transferred, so this report does not relabel them as upload volume.

## Reliability observations

Two failed attempts are excluded from the timing table but remain relevant:

- [run 35023492187](https://github.com/boringcache/finance-query/actions/runs/35023492187)
  restored both Cargo mounts for MCP, completed the long compilation, and then
  failed strict cache export with HTTP 500: `Failed to refresh the brokered
  workload capability`. The complete retry succeeded. This workflow used OIDC;
  no static-token fallback was added.
- [run 35028408284](https://github.com/boringcache/finance-query/actions/runs/35028408284)
  lost the GitHub MCP control before its build when `setup-buildx` timed out
  pulling `moby/buildkit:buildx-stable-1` from Docker Hub. The other three jobs
  completed. The complete four-job lockfile retry succeeded and supplies the
  comparison above.

Configured image tests, Trivy scans, and SARIF uploads completed on every job
marked complete in the table. The server probe remains non-gating because that
is the upstream behavior.

## Run record

- Seed: [35021208829](https://github.com/boringcache/finance-query/actions/runs/35021208829)
- Generated-only successful retry: [35025020739](https://github.com/boringcache/finance-query/actions/runs/35025020739)
- Source-only: [35026384383](https://github.com/boringcache/finance-query/actions/runs/35026384383)
- Lockfile successful retry: [35030494868](https://github.com/boringcache/finance-query/actions/runs/35030494868)
- Post-lock unchanged: [35031883018](https://github.com/boringcache/finance-query/actions/runs/35031883018)

## Decision boundary

The storage comparison retains the fat-LTO release build because changing the
profile at the same time would prevent attribution. The issue's cheaper
`release-ci` profile may remove more time with less operational complexity.
`cargo-chef`, `buildkit-cache-dance`, building the workspace once, using
`mode=min`, and narrowing triggers also remain valid alternatives.

The current Docker adapter should not be pitched as the full solution to issue
494. A product path that gives the two jobs independent OCI graph tags while
sharing a separate Cargo mount-cache namespace would address the measured
limitation. Until that exists, the simpler upstream alternatives should be
evaluated first.

## Reproduction

```console
gh workflow run boringcache-validation.yml \
  --repo boringcache/finance-query \
  --ref boringcache-validation \
  -f providers=all \
  -f source_ref=<upstream-commit-sha>
```
