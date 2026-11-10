# Base-image mirrors

`mirror.yml` inventories external Dockerfile inputs. Keys retain the exact
Dockerfile spelling; `source` spells out the upstream registry, repository,
and tag. Docker Hub shorthand is expanded, including the existing implicit
`latest` on `datadog/agent`. ECR sources remain ECR sources. Mirror repository
paths include the upstream hostname to keep their identities distinct.

The current inventory requires `linux/amd64` and `linux/arm64`, matching the
union of current consumer platforms. A missing platform is an error, not
permission to substitute another tag, registry, or architecture. Historical
tags must be checked during bootstrap before adopting a lock.

The read-only bootstrap audit on 6 November 2026 verified 22 of the 23 inputs.
The legacy `docker.io/starburstdata/presto:332-e.9` input provided only
`linux/amd64`, despite the service matrix requesting both architectures. The
explicit [Starburst service update](starburst.md) replaces it with
`docker.io/starburstdata/starburst-enterprise:482-e.7`, whose manifests and
configurations were verified for both required platforms on 10 November 2026.

The audit checked manifests and configurations, not layer copying into GHCR.
Whole-index copying also retains Windows entries present in `datadog/agent`
and MongoDB images; their blob availability and transfer remain bootstrap
checks even though this repository's consumers request Linux.

## Local refresh

Use Ruby 3.3 or newer and Skopeo, available together in the Nix shell:

```sh
nix develop -c bundle install
nix develop -c bundle exec rake mirror:check mirror:test
nix develop -c bundle exec rake mirror:inspect
nix develop -c bundle exec rake mirror:refresh
```

`mirror:check` checks inventory coverage without network access, including
external `FROM` and `COPY --from` inputs. Stage references and this project's
runtime-to-compiler dependencies are excluded. There are currently no external
`COPY --from` inputs. Variable-based image references require explicit support
before use; they are not silently resolved by the inventory checker.

`mirror:inspect` reads upstream manifests and configurations without publishing
or writing a lock. `mirror:refresh` publishes images, so authenticate to GHCR
with package write permission first. Skopeo uses its standard credential lookup,
including Docker's login configuration. An explicit `REGISTRY_AUTH_FILE` can
isolate credentials for a refresh. Authenticate separately to each source
registry where needed; credentials are never stored in the inventory or lock.

Each source tag is read once. The copier then uses the resolved digest with
`skopeo copy --all --preserve-digests`, retaining the whole index, including
extra architectures and embedded attestation manifests. It rejects schema or
digest conversion. Detached registry referrers are outside this copy contract.
The verifier checks the index digest, every reachable child manifest digest,
configuration digests, and required platforms against configurations. ARM64's
default `v8` variant is recorded as `linux/arm64`. Layer transfer and integrity
checking are delegated to Skopeo. TLS verification stays enabled. Registry
commands have a timeout and three retries with Skopeo's exponential backoff.

Mirrors receive a `sha256-<hex>` retention tag rather than a moving upstream
tag. A later refresh does not move an earlier tag. Preserve these tags and
digests for the entire supported old-commit rebuild window; configure package
cleanup accordingly. This naming convention does not prevent a registry
administrator from deleting content.

Only complete success atomically replaces `mirror.lock.yml`. Unchanged inputs
produce identical bytes and leave the file untouched. A failed refresh may
publish unreferenced content, but cannot replace an adopted lock. The lock has
no refresh timestamp, and records for each inventory key:

- the authoritative tagged `source`;
- digest-qualified `upstream` and `mirror`, with identical root digests;
- required `platforms`;
- all leaf `manifests`, with their digests and verified platforms.

## Manual workflow and bootstrap

The **Refresh Mirrors** workflow runs only when explicitly dispatched on
`main`. It copies and verifies the inventory, then uploads a candidate lock
artifact named with the checked-out commit. Download it, review against that
revision's inventory, and propose the lock in a normal user-authored PR.
Publication alone does not adopt any new build input. This first increment
does not create bot commits or PRs. A later automated proposer must explicitly
trigger validation or use an App token: ordinary pushes using `GITHUB_TOKEN`
do not trigger other workflows.

Bootstrap requires:

1. Merge the refresh workflow so it can be dispatched from `main`.
2. Grant its `GITHUB_TOKEN` package write access to all mirror repositories,
   including any pre-existing packages. Associate packages with this repository,
   set their intended visibility, and grant consumers read access.
3. Configure the ECR role and `AWS_ECR_PUBLIC_ROLE_ARN` from the separate ECR
   authentication change. Its OIDC trust must cover a dispatch on `main`.
4. Check all historical source tags and required platforms. Resolve unavailable
   inputs explicitly before the first complete refresh. Supply Docker Hub
   credentials if anonymous access is insufficient.
5. Run the refresh, review the candidate lock, and retain the published digests.
6. Adopt the initial lock together with shared local/CI consumption and build
   validation. This increment's offline CI checks inventory coverage and refresh
   failure semantics; it does not yet validate consumer builds against a lock.

The refresh workflow shares PR #127's AWS role contract and `us-east-1` ECR
login, using Skopeo's credential store. That PR owns authentication for existing
builds. Once all ordinary consumers use GHCR-only lock resolution, ECR login
and OIDC permissions can be removed from those build jobs and confined to
refresh. GHCR authentication remains necessary for consumers. Docker Hub
inputs must still be refreshed from Docker Hub.

## Consumer integration boundary

The next increment will provide one resolver for Rake and CI. Given the
Dockerfile, requested platforms, inventory, and committed lock, it must return
BuildKit named contexts mapping each external reference to
`docker-image://<mirror>@sha256:<digest>`. It must check inventory/lock agreement,
normalise `x86_64` to `amd64` and `aarch64` to `arm64`, and fail for missing
mappings, unsupported platforms, or absent mirrored content. It must never
inspect upstream tags or fall back to an upstream pull.

Use that resolver in local `docker:build`, CI's engine push and test-load paths,
and service builds. Include the lock in Rake's freshness inputs so an old local
image cannot skip a changed lock. Move service GHCR login before its first
build. Keep the compiler's existing per-run `BASE_RELEASE_TAG` to
`BASE_RUNID_TAG` context in both build and test-load steps; runtime outputs are
pipeline dependencies, not mirror inventory entries. Local recursive runtime
builds must likewise retain their dependency ordering.

The service workflow also runs `tonistiigi/binfmt` to enable emulation. This
is a CI helper rather than a Dockerfile base; it needs its own explicit locked
mapping before claiming that all build-time registry access is GHCR-only.

These locks control external image content, not every moving build input.
Main already has the compiler split, runtime headers, engine updates, and
Debian archive/HTTPS changes. Bullseye now uses Debian archives rather than
the previously activated snapshot sources. Package indexes and other downloads
still move. `SOURCE_DATE_EPOCH`, `.repro_run_key`, and cache hits do not prove
that clean builds are reproducible.
