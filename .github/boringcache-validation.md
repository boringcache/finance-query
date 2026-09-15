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

The shared Cargo mounts materially reduced compilation on the fresh lockfile
transition, but they saved only 42 seconds of total runner time because the
fat-LTO links dominated. They did not retain both image graphs. On the next
unchanged-Docker-input run, three jobs completed in about one minute while the
BoringCache MCP job took 14m35s after the server had published last. This is a
current product limitation, not a successful prospect proof.

Separate server and MCP BoringCache tags would retain both image graphs, but
would also give them separate Cargo mount archives and would not test the
cross-job reuse requested in the issue. The released CLI and repository plan
schema expose `tag` and the boolean `mount-cache`; they do not expose a separate
mount-cache namespace or tag.

The shared target archive also followed last-writer state rather than merging
the two independent target directories. After the server published last, MCP
restored the archive but still compiled 81 MCP-specific crates on an unchanged
Docker input. Separate OCI tags alone would therefore not supply the cross-job
target reuse tested here.

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

## Fresh rolling-source cohort

The primary `v3` cohort used new GitHub scopes and a new BoringCache tag. The
revisions ran sequentially so both providers received the same cache history.

| Order | Source revision | Change represented |
| ---: | --- | --- |
| 1 | `6250e615def5735a5ed1cb5cd2359afce4f3afeb` | Cold seed at the parent state |
| 2 | `59c8c317260bdb3f9118ed5561b94c4f9b896a6e` | Rust source, manifest, and `Cargo.lock` changes |
| 3 | `a9d680732f02eb94693676333602f6335010ddab` | `CHANGELOG.md`-only update; Markdown is excluded from both Docker contexts |

## Complete-workflow results

Durations include the complete configured job. `Build` is the Docker build
step only. Total runner time is the sum of the server and MCP jobs; critical
path is the slower of the two concurrent jobs. Cargo `Compiling` lines are
supporting evidence, not a cache hit rate.

| Revision | Provider | Server job / build | MCP job / build | Total runner | Critical path | Compile lines server / MCP | Result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Fresh cold seed | GitHub | 21m55s / 21m11s | 16m05s / 15m08s | 38m00s | 21m55s | 331 / 345 | Both complete |
| Fresh cold seed | BoringCache | 22m33s / 21m51s | 15m35s / 14m42s | 38m08s | 22m33s | 331 / 345 | Both complete |
| Fresh lock transition | GitHub | 20m54s / 20m06s | 15m16s / 14m22s | 36m10s | 20m54s | 297 / 311 | Both complete |
| Fresh lock transition | BoringCache | 20m26s / 19m51s | 15m02s / 14m10s | 35m28s | 20m26s | 6 / 81 | Both complete |
| Fresh post-lock unchanged | GitHub | 49s / 7s | 1m04s / 8s | 1m53s | 1m04s | 0 / 0 | Both complete |
| Fresh post-lock unchanged | BoringCache | 55s / 15s | 14m35s / 13m39s | 15m30s | 14m35s | 0 / 81 | Both complete |

The cold seeds differed by eight seconds of total runner time. On the fresh
lock transition, BoringCache reduced 608 compile lines to 87 but saved only 42
seconds of total runner time (1.9%) and 28 seconds of critical path (2.2%). On
the following unchanged-Docker-input revision, BoringCache used 13m37s more
runner time and added 13m31s to the critical path. The server publication had
replaced the MCP graph and target snapshot, so MCP restored both mount archives
but still compiled 81 crates and repeated its fat-LTO link.

An earlier `v2` source-only comparison showed a larger changed-source saving,
but later `v2` recovery runs had asymmetric history after infrastructure
failures. The fresh `v3` sequence above is the decision dataset.

## Transfer and reuse evidence

On the fresh lock transition, the BoringCache server restored its target and
registry mounts in 7.421s and 6.226s. MCP restored them in 7.818s and 5.546s.
Each BoringCache layer-manifest import took 0.1s; its layer exports reported
0.3s for server and 0.5s for MCP. GitHub did not restore either Cargo mount
because `type=gha` does not export their contents.

On the fresh post-lock run, MCP restored the target and registry mounts in
7.743s and 5.191s. The restore was a hit, but the server's last-published target
snapshot lacked the MCP-specific outputs, and MCP emitted 81 compile lines.

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
  completed. A complete four-job retry succeeded, but its cache history was no
  longer symmetric. It is recovery evidence only. The later fresh `v3` cohort
  supplies the comparison above.

Configured image tests, Trivy scans, and SARIF uploads completed on every job
marked complete in the table. The server probe remains non-gating because that
is the upstream behavior.

## Run record

- Fresh seed: [35032676695](https://github.com/boringcache/finance-query/actions/runs/35032676695)
- Fresh lock transition: [35034450000](https://github.com/boringcache/finance-query/actions/runs/35034450000)
- Fresh post-lock unchanged: [35036054819](https://github.com/boringcache/finance-query/actions/runs/35036054819)
- Earlier source-only exploratory run: [35026384383](https://github.com/boringcache/finance-query/actions/runs/35026384383)
- Earlier post-lock collision in the opposite direction: [35031883018](https://github.com/boringcache/finance-query/actions/runs/35031883018)

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
