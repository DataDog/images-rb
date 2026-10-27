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
- `truffleruby`: Due to the nature and state of TruffleRuby, these are experimental and may or may not work as expected.

Tag naming acts as a contract and conveys intended usage:

- If you expect a compiler, use `-gcc` or `-clang` tags; images without this do not guarantee presence of a compiler.
- If you expect a certain libc (variant or version), use the appropriate `-musl`, `-gnu` (glibc), or `-centos` (old glibc) tags.
- "Naked" version tags give you that specific runtime, but assume no specific Linux distribution, libc version or variant, and no compiler.

### Services

Directory: `src/services`

Service images are intended to provide known, fixed behaviour for test suites.

## Updating engine releases

Run the updater with Ruby 3.3 or newer and the repository's bundle, or through
the Nix shell:

```sh
nix develop -c bundle install
nix develop -c rake engine:update DRY_RUN=1
nix develop -c rake engine:update
nix develop -c rake 'engine:update[jruby]'
nix develop -c rake engine:update DRY_RUN=1 FORMAT=json
```

The task discovers upstream releases, inventories the checkout, and updates
each existing series independently. It includes published previews and release
candidates. Newer minor or major series copy their nearest predecessor's
Dockerfiles, Gemfile, and build matrix entries. Inherited build dependencies
and patches are a best-effort starting point; image CI checks compatibility.
Missing historical series are not backfilled.

Sources are Ruby's [archive index](https://cache.ruby-lang.org/pub/ruby/index.txt),
JRuby's [Maven metadata](https://repo1.maven.org/maven2/org/jruby/jruby-dist/maven-metadata.xml),
and TruffleRuby's [GitHub releases](https://github.com/truffleruby/truffleruby/releases).
Versions and SHA-256 pins change together. TruffleRuby follows Community Native
Linux assets for both architectures. If an asset has no published digest, the
updater downloads it and reports a computed content checksum.

Minimum series and exclusions live in `tasks/engine/plan.rb`. Ruby 1.8
retains its manually pinned commit archive. Engines without seed images are
reported and skipped when checking all engines; selecting one explicitly fails.
An optional `GH_TOKEN` or `GITHUB_TOKEN` increases GitHub API limits locally.

The **Update Engines** workflow runs daily and can be dispatched from `main`
for one engine or all engines. It uses `dd-octo-sts` with the
`self.update-engines` trust policy to open or refresh one PR per engine on
`automation/update-<engine>`. The App token allows these pushes to trigger
normal image CI. Manual commits on an automation branch stop further bot
updates until reconciled. Changes are never merged automatically.

The workflow and trust policy must be merged before the first scheduled or
manual run. The STS App needs repository access with contents, pull-request,
and workflow write permissions, since new series change the build matrices.
TruffleRuby checks start automatically once its seed images are present.

Host-side updater tests are separate from the historical-runtime image tests:

```sh
nix develop -c rake engine:test
```
