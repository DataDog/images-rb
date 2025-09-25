# strip-tags: gnu
# append-tags: gcc

FROM eclipse-temurin:11-jammy AS jruby-9.3.9.0-jre11

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

# Ensure sane locale (`eclipse-temurin` already updated `/etc/locale.gen` for `en_US.UTF-8`)
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en

# Ensure consistent timezone
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Install JRuby, pinned for reproducibility
ENV JRUBY_VERSION 9.3.9.0
ENV JRUBY_SHA256 251e6dd8d1d2f82922c8c778d7857e1bef82fe5ca2cf77bc09356421d0b05ab8
RUN mkdir /opt/jruby \
 && curl -fSL https://repo1.maven.org/maven2/org/jruby/jruby-dist/${JRUBY_VERSION}/jruby-dist-${JRUBY_VERSION}-bin.tar.gz -o /tmp/jruby.tar.gz \
 && echo "$JRUBY_SHA256 /tmp/jruby.tar.gz" | sha256sum -c - \
 && tar -zx --strip-components=1 -f /tmp/jruby.tar.gz -C /opt/jruby \
 && rm /tmp/jruby.tar.gz \
 && update-alternatives --install /usr/local/bin/ruby ruby /opt/jruby/bin/jruby 1
ENV PATH /opt/jruby/bin:$PATH

# Skip installing gem documentation
RUN mkdir -p /opt/jruby/etc \
 && echo -e 'install: --no-document\nupdate: --no-document' >> /opt/jruby/etc/gemrc

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH

# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 1777 "$GEM_HOME"

## Install a pinned RubyGems and Bundler
RUN gem update --system 3.4.22
RUN gem install bundler:2.4.22

# Install additional gems that are in CRuby but missing from the above
# JRuby install distribution. These are version-pinned for reproducibility.
RUN gem install rake:13.2.1

# Start IRB as a default
CMD [ "irb" ]
