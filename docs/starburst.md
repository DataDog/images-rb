# Starburst service image

The Starburst service uses `docker.io/starburstdata/starburst-enterprise:482-e.7`,
from the [482 LTS series][release]. It replaces the build recipe for
`starburstdata/presto:332-e.9`, whose upstream image supports AMD64 only. Both
AMD64 and ARM64 are available in the new source image.

The published target is
`ghcr.io/datadog/images-rb/services/starburstdata/starburst-enterprise:482-e.7`,
with the usual `482` series tag. Existing `services/starburstdata/presto:332-e.9`
tags are not aliases for the new version. Consumers must explicitly select the
new image after it has been built and validated.

## Client compatibility

Starburst's [migration documentation][migration] says that legacy `X-Presto-*`
header support was removed in 467-e. However, a direct test of the 482-e.7
container accepted these headers without any compatibility configuration.
Treat the following as evidence for this specific image, not a compatibility
guarantee for future updates.

On 10 November 2026, native AMD64 tests with Ruby 3.3.5 and `presto-client`
0.6.6 passed 15 option sets covering user, catalogue, schema, time zone,
language, and legacy model versions. Each exercised `SELECT 1`, named rows,
asynchronous queries, cancellation of an unknown query ID, and a SQL error.
`SELECT current_user, current_catalog, current_schema` also confirmed that the
legacy headers were honoured. `SELECT version()` returned `482-e.7`.

`trino-client` 2.3.1 also passed basic queries with JSON 2.21.2. With JSON 3.1.0,
that client's positional options argument to `JSON.parse` raised an argument
error. This is a separate client dependency issue; upgrading the image does
not require changing to that client. The modern client's Ruby 3.2 minimum and
`Trino::Client` namespace also require separate consideration for consumers
which still test older Rubies or instrument `Presto::Client`.

The verified upstream index was:

```text
sha256:4ea8006b2ddb4a23c95d2669c10ad69c2b6813d81d892753f96e72fb69776741
```

These observations apply to the digest above; the upstream tag can move.
ARM64 manifests and configurations were checked; ARM64 execution and the full
consumer integration suite remain adoption checks.

[release]: https://docs.starburst.io/latest/release/release-482-e.html
[migration]: https://docs.starburst.io/latest/appendix/to-sep-354-plus.html
