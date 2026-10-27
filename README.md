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

#### AddressSanitizer

CRuby 3.4 has an ASan build for `x86_64` and `aarch64`. These tags identify
the same glibc-based image:

- `3.4-asan`
- `3.4-asan-clang`
- `3.4-asan-gnu`
- `3.4-asan-gnu-clang`

`Dockerfile.asan` builds Ruby, OpenSSL, and libyaml with Clang 19 and ASan.
The image retains Clang, native-extension build dependencies, debug information,
and `llvm-symbolizer`. Use a `-clang` alias to depend explicitly on the compiler.
Other system libraries and YJIT-generated code are not ASan-instrumented.
M:N threading is disabled following [CRuby's ASan guidance][ruby-asan].

Ruby's build configuration passes instrumentation flags to `mkmf` extensions.
Build native gems from source in this image rather than reusing ordinary native
gem binaries or a bundle cache from another image:

```sh
bundle config set force_ruby_platform true
bundle install
bundle exec rake test
```

Extensions using custom build systems, including Rust extensions, need their
own ASan configuration. ASan runs without the compiler once everything
has been built; it remains installed here for native-gem development and CI.

Leak detection follows Ruby's default of being disabled. To enable it:

```sh
RUBY_FREE_AT_EXIT=1 ASAN_OPTIONS=detect_leaks=1 bundle exec rake test
```

Projects can supply their own `LSAN_OPTIONS=suppressions=/path/to/lsan.supp`.
Run containers with `--cap-add=SYS_PTRACE` when enabling leak detection so
LeakSanitizer can inspect other threads.
The image does not install project-specific suppressions. Musl variants are
not currently provided.

[ruby-asan]: https://github.com/ruby/ruby/blob/master/doc/contributing/building_ruby.md#building-with-address-sanitizer

### Services

Directory: `src/services`

Service images are intended to provide known, fixed behaviour for test suites.
