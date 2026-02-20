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
    RUBY_MAJOR="2.2"                                                                        \
    RUBY_VERSION="2.2.10"                                                                   \
    RUBY_DOWNLOAD_SHA256="bf77bcb7e6666ccae8d0882ea12b05f382f963f0a9a5285a328760c06a9ab650"

# - Compile Ruby with `--disable-shared`
# - Update gem version

RUN <<SHELL
set -eux

# --- Install compiler and build dependencies ---
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
    --no-install-recommends

# --- Build Ruby ---

# Ruby 2.2 needs OpenSSL 1.0.x; Debian 11 ships 1.1.x which is incompatible
OPENSSL_VERSION='1.0.2u'
OPENSSL_SHA256='ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16'

curl -L -o openssl.tar.gz "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
echo "$OPENSSL_SHA256 *openssl.tar.gz" | sha256sum --check --strict
mkdir -p /usr/src/openssl
tar -xzf openssl.tar.gz -C /usr/src/openssl --strip-components=1
rm openssl.tar.gz

cd /usr/src/openssl

./config \
    --prefix=/usr/local/ssl \
    --openssldir=/usr/local/ssl \
    shared \
    zlib
make
make install

echo "/usr/local/ssl/lib" > /etc/ld.so.conf.d/openssl.conf
ldconfig

# point OpenSSL to system CA certificates so SSL verification works
rmdir /usr/local/ssl/certs
ln -s /etc/ssl/certs /usr/local/ssl/certs

cd /
rm -r /usr/src/openssl

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
    --disable-shared \
    --with-openssl-dir=/usr/local/ssl
make -j "$(nproc)"
make install

cd /
rm -r /usr/src/ruby

# verify ruby is not installed via apt
if dpkg -l ruby 2>/dev/null | grep -q '^ii'; then exit 1; fi

# update gem version
gem update --system 2.7.11
gem install bundler --version 1.17.3 --force

# rough smoke test
ruby --version
gem --version
bundle --version

# --- Clean up compiler and build dependencies ---
# Note: --auto-remove is deliberately NOT used because runtime libraries
# (libyaml, libffi, libssl, etc.) were auto-installed as dependencies of
# -dev packages and apt has no way to know that Ruby needs them at runtime.
apt-get purge -y \
    gcc g++ cpp make autoconf bison patch build-essential xz-utils \
    libc6-dev zlib1g-dev libyaml-dev libgdbm-dev libreadline-dev \
    libncurses5-dev libncurses-dev libffi-dev libssl-dev


SHELL

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH

# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 1777 "$GEM_HOME"

CMD [ "irb" ]
