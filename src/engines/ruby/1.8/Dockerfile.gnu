# platforms: linux/x86_64

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
    RUBY_MAJOR="1.8"                                                                        \
    RUBY_VERSION="1.8.7-p376"                                                               \
    RUBY_DOWNLOAD_SHA256="8dfe254590e77b82ceaffba29ad38d1cee7c4180ab50340fecdb76a6fa59330b"

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

# Ruby 1.8 needs OpenSSL 1.0.x; Debian 11's OpenSSL 1.1.x is incompatible
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

# point OpenSSL to the system CA certificates so SSL verification works
rmdir /usr/local/ssl/certs
ln -s /etc/ssl/certs /usr/local/ssl/certs

cd /
rm -r /usr/src/openssl

# Ruby 1.8 is downloaded from GitHub archive (not cache.ruby-lang.org)
curl -L -o ruby.tar.gz "https://github.com/ruby/ruby/archive/f48ae0d10c5b586db5748b0d4b645c7e9ff5d52e.tar.gz"
echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.gz" | sha256sum --check --strict
mkdir -p /usr/src/ruby
tar -xzf ruby.tar.gz -C /usr/src/ruby --strip-components=1
rm ruby.tar.gz

cd /usr/src/ruby

# hack in "ENABLE_PATH_CHECK" disabling to suppress:
#   warning: Insecure world writable dir
{
    echo '#define ENABLE_PATH_CHECK 0'
    echo
    cat file.c
} > file.c.new
mv file.c.new file.c

# https://github.com/rbenv/ruby-build/issues/444
# https://bugs.ruby-lang.org/issues/9065
# https://github.com/ruby/ruby/commit/f895841e2c2861f8d3ea2247817d6ffd35dff71c.patch
patch -p1 <<'PATCH'
diff --git a/ext/openssl/ossl_pkey_ec.c b/ext/openssl/ossl_pkey_ec.c
index 8e6d88f60609b3..29e28ca2f4420f 100644
--- a/ext/openssl/ossl_pkey_ec.c
+++ b/ext/openssl/ossl_pkey_ec.c
@@ -762,8 +762,10 @@ static VALUE ossl_ec_group_initialize(int argc, VALUE *argv, VALUE self)
                 method = EC_GFp_mont_method();
             } else if (id == s_GFp_nist) {
                 method = EC_GFp_nist_method();
+#if !defined(OPENSSL_NO_EC2M)
             } else if (id == s_GF2m_simple) {
                 method = EC_GF2m_simple_method();
+#endif
             }

             if (method) {
@@ -817,8 +819,10 @@ static VALUE ossl_ec_group_initialize(int argc, VALUE *argv, VALUE self)

             if (id == s_GFp) {
                 new_curve = EC_GROUP_new_curve_GFp;
+#if !defined(OPENSSL_NO_EC2M)
             } else if (id == s_GF2m) {
                 new_curve = EC_GROUP_new_curve_GF2m;
+#endif
             } else {
                 ossl_raise(rb_eArgError, "unknown symbol, must be :GFp or :GF2m");
             }
PATCH

autoconf

gnuArch="$(gcc -dumpmachine)"
./configure \
    --build="$gnuArch" \
    --disable-install-doc \
    --disable-shared \
    --with-openssl-dir=/usr/local/ssl
# parallel make causes race conditions in old Ruby's extension build system so we don't use `-j $(nproc)`
make
make install

cd /
rm -r /usr/src/ruby

# verify ruby is not installed via apt
if dpkg -l ruby 2>/dev/null | grep -q '^ii'; then exit 1; fi

# Ruby 1.8 doesn't come with rubygems, so we need to bootstrap it
curl -o rubygems.tar.gz "https://rubygems.org/rubygems/rubygems-1.6.2.tgz"
echo "cb5261818b931b5ea2cb54bc1d583c47823543fcf9682f0d6298849091c1cea7 *rubygems.tar.gz" | sha256sum --check --strict
mkdir -p /usr/src/rubygems
tar -xzf rubygems.tar.gz -C /usr/src/rubygems --strip-components=1
rm rubygems.tar.gz

cd /usr/src/rubygems
ruby setup.rb
cd /
rm -r /usr/src/rubygems

# update gem version
gem update --system 2.7.11
gem install bundler --version 1.17.3 --force

# patch away annoying deprecations
cd /usr/local/lib/ruby/gems/1.8/gems/rubygems-update-2.7.11/lib
patch -p1 <<'PATCH'
--- a/rubygems/deprecate.rb	2024-11-21 14:48:56
+++ b/rubygems/deprecate.rb	2024-11-21 14:49:45
@@ -24,7 +24,7 @@
 module Gem::Deprecate

   def self.skip # :nodoc:
-    @skip ||= false
+    @skip ||= true
   end

   def self.skip= v # :nodoc:
PATCH
cd /usr/local/lib/ruby/site_ruby/1.8
patch -p1 <<'PATCH'
--- a/rubygems/deprecate.rb	2024-11-21 14:48:56
+++ b/rubygems/deprecate.rb	2024-11-21 14:49:45
@@ -24,7 +24,7 @@
 module Gem::Deprecate

   def self.skip # :nodoc:
-    @skip ||= false
+    @skip ||= true
   end

   def self.skip= v # :nodoc:
PATCH
cd /

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
