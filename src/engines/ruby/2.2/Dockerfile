# ruby:2.2.10-jessie was based on jessie, and had a aarch64 image
# aarch64 used to be supported upon release but is not part of LTS,
# so archive.debian.org does not contain aarch64: https://www.debian.org/releases/jessie/

# Note: See the "Publishing updates to images" note in ./README.md for how to publish new builds of this container image

# Here be dragons: Last time we tried to move away from Debian stretch, we ran into issues with two gems that are used in some
# of our CI tests/test apps.
# If you're going to try your luck, make sure that the following work after your changes:
# gem install mysql
#
# taken from https://github.com/docker-library/ruby/blob/b5ef401d348ca9b1d9f6a5cb4b25f32bf013daca/2.2/jessie/Dockerfile
FROM buildpack-deps:stretch AS ruby-2.2.10-stretch

# skip installing gem documentation
RUN mkdir -p /usr/local/etc \
  && { \
    echo 'install: --no-document'; \
    echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc

ENV RUBY_MAJOR 2.2
ENV RUBY_VERSION 2.2.10
ENV RUBY_DOWNLOAD_SHA256 bf77bcb7e6666ccae8d0882ea12b05f382f963f0a9a5285a328760c06a9ab650
ENV RUBYGEMS_VERSION 2.7.11
ENV BUNDLER_VERSION 1.17.3

# Pull packages from debian archive, old repos don't work any more
RUN echo "deb [trusted=yes] http://archive.debian.org/debian/ stretch main contrib non-free" | tee /etc/apt/sources.list

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
RUN set -ex \
  && apt-get update \
  # ruby 2.2 needs libssl1.0-dev
  && apt-get install -y --no-install-recommends wget \
  && apt-get remove -y libssl-dev libcurl4-openssl-dev \
  && ARCH=$(dpkg --print-architecture) \
  && wget "https://snapshot.debian.org/archive/debian-security/20220317T093342Z/pool/updates/main/o/openssl1.0/libssl1.0.2_1.0.2u-1~deb9u7_${ARCH}.deb" \
  && dpkg -i libssl1.0.2*.deb \
  && rm -rf libssl1.0.2*.deb \
  && wget "https://snapshot.debian.org/archive/debian-security/20220317T093342Z/pool/updates/main/o/openssl1.0/libssl1.0-dev_1.0.2u-1~deb9u7_${ARCH}.deb" \
  && dpkg -i libssl1.0-dev*.deb \
  && rm -rf libssl1.0-dev*.deb \
# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
  && buildDeps=' \
    bison \
    dpkg-dev \
    libgdbm-dev \
    ruby \
  ' \
  && apt-get install -y --no-install-recommends $buildDeps \
  && rm -rf /var/lib/apt/lists/* \
  \
  && wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz" \
  && echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum -c - \
  \
  && mkdir -p /usr/src/ruby \
  && tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1 \
  && rm ruby.tar.xz \
  \
  && cd /usr/src/ruby \
  \
# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
  && { \
    echo '#define ENABLE_PATH_CHECK 0'; \
    echo; \
    cat file.c; \
  } > file.c.new \
  && mv file.c.new file.c \
  \
  && autoconf \
  && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
  && ./configure \
    --build="$gnuArch" \
    --disable-install-doc \
    --enable-shared \
  && make -j "$(nproc)" \
  && make install \
  \
  && apt-get purge -y --auto-remove $buildDeps \
  && cd / \
  && rm -r /usr/src/ruby

# \
# && gem update --system "$RUBYGEMS_VERSION" \
# && gem install bundler --version "$BUNDLER_VERSION" --force \
# && rm -r /root/.gem/

# install things globally, for great justice
# and don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_BIN="$GEM_HOME/bin" \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
  && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

CMD [ "irb" ]

FROM ruby-2.2.10-stretch

# A few RUN actions in Dockerfiles are subject to uncontrollable outside
# variability: an identical command would be the same from `docker build`'s
# point of view but does not indicate the result would be identical at
# different points in time.
#
# This causes two possible issues:
#
# - one wants to capture a new state and so wants the identical
#   non-reproducible command to produce a new result. This could be achieved
#   with --no-cache but this affects every single operation in a Dockerfile
# - one wants to identify a specific state and leverage caching at that
#   specific state.
#
# To that end a BUILD_ARG is introduced to capture an arbitrary identifier of
# that state (typically time) that is introduced in non-reproducible commands
# to make them appear different to Docker.
#
# Of course it only works when caching data is available: two independent
# builds with the same value and no cache shared would produce different
# results.
ARG REPRO_RUN_KEY=0

# `apt-get update` is uncontrolled and fetches whatever is today's index.
# For the sake of reproducibility subsequent steps (including in dependent
# images) should not do `apt-get update`, instead this base image should be
# updated by changing the `REPRO_RUN_KEY`.
RUN true "${REPRO_RUN_KEY}" && apt-get update

# Install system dependencies for building
RUN apt-get install -y libc6-dev gcc git locales tzdata --no-install-recommends && rm -rf /var/lib/apt/lists/*

# Ensure sane locale (Uncomment `en_US.UTF-8` from `/etc/locale.gen` before running `locale-gen`)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

# Ensure consistent timezone
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Install things at a specific path and create ".bundle" in there as well:
# This prevents pollution of an app volume and makes the bundle path mountable
# as a volume as well.
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_BIN="$GEM_HOME/bin" \
    BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $BUNDLE_BIN:$PATH
RUN mkdir -p "$GEM_HOME" "$BUNDLE_BIN" \
 && chmod 777 "$GEM_HOME" "$BUNDLE_BIN"

## Install a pinned RubyGems and Bundler
RUN gem update --system 2.7.11
RUN gem install bundler --version 1.17.3

# Install additional gems that are in CRuby but missing from the above
# JRuby install distribution. These are version-pinned for reproducibility.
RUN gem install rake:13.0.6

# Start IRB as a default
CMD [ "irb" ]
