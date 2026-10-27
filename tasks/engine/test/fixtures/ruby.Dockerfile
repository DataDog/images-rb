FROM debian:13

ENV LANG="en_US.UTF-8" \
    RUBY_MAJOR="3.4" \
    RUBY_VERSION="3.4.7" \
    RUBY_DOWNLOAD_SHA256="db425a86f6e07546957578f4946cc700a91e7fd51115a86c56e096f30e0530c7"

RUN <<SHELL
curl -o ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"
echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict
gem install bundler --version 3.4.7
SHELL
