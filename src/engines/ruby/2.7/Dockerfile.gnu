# strip-tags: gnu
# append-tags: gcc

# Debian 11 (bullseye)
FROM public.ecr.aws/docker/library/debian:11

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

# Install locale and timezone support first
RUN apt-get install -y locales tzdata --no-install-recommends

# Ensure sane locale (Uncomment `en_US.UTF-8` from `/etc/locale.gen` before running `locale-gen`)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Ensure consistent timezone
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

# Skip installing gem documentation
COPY <<GEMRC /usr/local/etc/gemrc
install: --no-document
update: --no-document
GEMRC

ENV LANG="en_US.UTF-8"                                                                      \
    LANGUAGE="en_US:en"                                                                     \
    RUBY_MAJOR="2.7"                                                                        \
    RUBY_VERSION="2.7.8"                                                                    \
    RUBY_DOWNLOAD_SHA256="f22f662da504d49ce2080e446e4bea7008cee11d5ec4858fc69000d0e5b1d7fb"

# - Compile Ruby with `--disable-shared`
# - Update gem version

RUN <<SHELL
set -eux

apt-get install -y \
    curl \
    ca-certificates \
    gcc \
    g++ \
    make \
    autoconf \
    bison \
    patch \
    libc6-dev \
    build-essential \
    git \
    xz-utils \
    zlib1g-dev \
    libyaml-dev \
    libgdbm-dev \
    libreadline-dev \
    libncurses5-dev \
    libffi-dev \
    libssl-dev \
    --no-install-recommends

curl -o ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"
echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict
mkdir -p /usr/src/ruby
tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1
rm ruby.tar.xz

cd /usr/src/ruby

# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
{
    echo '#define ENABLE_PATH_CHECK 0'
    echo
    cat file.c
} > file.c.new
mv file.c.new file.c

autoconf

gnuArch="$(gcc -dumpmachine)"
./configure \
    --build="$gnuArch" \
    --disable-install-doc \
    --disable-shared
make -j "$(nproc)"
make install

cd /
rm -r /usr/src/ruby

# verify ruby is not installed via apt
if dpkg -l ruby 2>/dev/null | grep -q '^ii'; then exit 1; fi

# update gem version
gem update --system 3.4.22

# rough smoke test
ruby --version
gem --version
bundle --version

# clean up apt lists
rm -rf /var/lib/apt/lists/*

SHELL

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH

# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 1777 "$GEM_HOME"

CMD [ "irb" ]
