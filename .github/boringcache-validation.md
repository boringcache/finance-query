# BoringCache validation for finance-query issue 494

This branch runs the complete Docker portion of
[Verdenroz/finance-query#494](https://github.com/Verdenroz/finance-query/issues/494).
The issue reports that the independent server and MCP Docker jobs each rebuild
overlapping Rust dependencies after lockfile or manifest changes because the
existing GitHub BuildKit layer caches do not persist Cargo cache mounts.

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

The BoringCache jobs use one shared Docker tag family. This lets the two clean
runners address the same BuildKit layer graph and the same Cargo registry and
target cache-mount archives. Both jobs remain independent and concurrent, as
they are upstream. The experiment therefore also tests concurrent publication
to that shared namespace rather than assuming it works.

BoringCache authentication uses GitHub Actions OIDC. The workflow contains no
static BoringCache token. The validation branch and repository restriction
limit publication to the trusted fork branch. All actions use immutable commit
SHAs, cache failures are strict, and per-job BoringCache evidence is retained.

The server health probe deliberately retains upstream's `|| true`; the MCP
health probe is gating. This branch does not change unrelated upstream test
semantics.

## Rolling-source cohort

The revisions run oldest to newest, with one workflow completing before the
next starts so both providers receive the same cache history.

| Order | Source revision | Change represented |
| ---: | --- | --- |
| 1 | `d7faa19b4363066e2ae10e5cac8356df2d6d9a7c` | Initial seed; generated-output update |
| 2 | `6ea3108469eab9d8a8b66cc625063e52797a97e4` | Generated-output-only update |
| 3 | `6250e615def5735a5ed1cb5cd2359afce4f3afeb` | Rust source changes with an unchanged lockfile |
| 4 | `59c8c317260bdb3f9118ed5561b94c4f9b896a6e` | Rust source, manifest, and `Cargo.lock` changes |
| 5 | `a9d680732f02eb94693676333602f6335010ddab` | `CHANGELOG.md`-only update after the lockfile change |

## Measurements

Results are pending. The completed report will record, for every revision and
provider:

- server and MCP build-step duration;
- complete server and MCP job duration, including health checks and Trivy;
- total runner time across the two jobs;
- workflow critical path;
- Cargo compilation progress as supporting evidence, not as a cache hit rate;
- BoringCache layer and cache-mount restore, publication, byte, timing, and
  error evidence;
- whether both images completed their upstream correctness path.

## Decision boundary

The storage comparison retains the fat-LTO release build because changing the
profile at the same time would prevent attribution. The issue's cheaper
`release-ci` profile may remove more time with less operational complexity.
`cargo-chef`, `buildkit-cache-dance`, building the workspace once, using
`mode=min`, and narrowing triggers also remain valid alternatives. The final
conclusion must compare BoringCache's complete workflow result with those
choices; fewer Cargo compilation lines alone are not a product win.

## Reproduction

```console
gh workflow run boringcache-validation.yml \
  --repo boringcache/finance-query \
  --ref boringcache-validation \
  -f providers=all \
  -f source_ref=<upstream-commit-sha>
```
