# strip-tags: gnu
# append-tags: gcc

FROM ruby:3.3.2-bookworm

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

# Configure apt retries to improve automation reliability
RUN echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries

# `apt-get update` is uncontrolled and fetches whatever is today's index.
# For the sake of reproducibility subsequent steps (including in dependent
# images) should not do `apt-get update`, instead this base image should be
# updated by changing the `REPRO_RUN_KEY`.
RUN true "${REPRO_RUN_KEY}" && apt-get update

# Install system dependencies for building
RUN apt-get install -y libc6-dev build-essential git locales tzdata --no-install-recommends && rm -rf /var/lib/apt/lists/*

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
RUN gem update --system 3.5.21
RUN gem install bundler:2.3.26

# Install additional gems that are in CRuby but missing from the above
# JRuby install distribution. These are version-pinned for reproducibility.
RUN gem install rake:13.2.1

# Start IRB as a default
CMD [ "irb" ]
