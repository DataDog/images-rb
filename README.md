# Container images for Ruby

Instead of cherry-picking images across a variety of sources and bespoke-building images from these sources and yet others, this repository and corresponding packages serves as a central place to look for, provide, define, reuse, manage, an d build a set of images.

The build process is envisioned as being efficient at layering for fast building, cacheability, and (a form of) reproducibility and auditability.

All images should support `aarch64` and `x86_64`. When possible and relevant, there should be `glibc`- and `musl`-based variants.

Use cases include:

- having a consistent set of images to build other images from
- providing base images for CI usage and testing as well as local development
- providing minimal app images using various frameworks for CI testing (integration, system tests), issue reproduction, support engineers, pentesters...
- making CI runtime environment reproducinble locally
- hastening image building and fetching by mutualising commonality
- customising in subsequent layers for bespoke usage

## Images

### Ruby engines

Supported engines include:

- `ruby`: MRI a.k.a CRuby.
- `jruby`: These are based on Eclise Temurin JDK builds.
- `truffleruby`: Due to the nature and state of TruffleRuby these are experimental and may or may not work as expected.

### Apps

#### minimal-rack

These images provide a set of minimal rack-based applications covering a range of frameworks and versions:

- `rack` 1.3 to 3 and up
- `rails` 3.2 to 7 and up
- `sinatra` 1.0 to 4 and up
- `grape` 1.2 to 4 and up
