# Container images for Ruby

Instead of cherry-picking images across a variety of sources and bespoke-building images from these sources and yet others, this repository and corresponding packages serve as a central place to look for, provide, define, reuse, manage, and build a set of images.

The build process is envisioned as being efficient at layering for fast building, cacheability, and (a form of) reproducibility and auditability.

All images should support `aarch64` and `x86_64`. When possible and relevant, there should be `glibc`- and `musl`-based variants.

Use cases include:

- having a consistent set of images to build other images from
- providing base images for CI usage and testing as well as local development
- providing service images for integration with testing suites
- providing minimal app images using various frameworks for CI testing (integration, system tests), issue reproduction, support engineers, pentesters...
- making CI runtime environment reproducible locally
- hastening image building and fetching by mutualising commonality
- customising in subsequent layers for bespoke usage

## Images

### Ruby engines

Directory: `src/engines`

Supported engines include:

- `ruby`: MRI a.k.a CRuby.
- `jruby`: These are based on Eclipse Temurin JDK builds.
- `truffleruby`: Community Native builds. The `40.0` series targets Ruby 4.0 and provides glibc-based runtime, GCC, and Clang images for `x86_64` and `aarch64`.

Tag naming acts as a contract and conveys intended usage:

- If you expect a compiler, use `-gcc` or `-clang` tags; images without this do not guarantee presence of a compiler.
- If you expect a certain libc (variant or version), use the appropriate `-musl`, `-gnu` (glibc), or `-centos` (old glibc) tags.
- "Naked" version tags give you that specific runtime, but assume no specific Linux distribution, libc version or variant, and no compiler.

### Services

Directory: `src/services`

Service images are intended to provide known, fixed behaviour for test suites.

## CI registry authentication

Image builds authenticate to Amazon ECR Public using GitHub OIDC. See
[ECR Public authentication](docs/ecr-public-auth.md) for the AWS role and
repository-variable setup required before running CI.
