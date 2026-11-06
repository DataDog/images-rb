FROM debian:13

ENV LANG=en_US.UTF-8 \
    TRUFFLERUBY_VERSION=40.0.0

RUN <<SHELL
set -eux
case "$(uname -m)" in
    x86_64)
        arch=amd64
        sha256=4d744085f48c8ba789228f3686e3c256fcc6b77ce1ff736e456b72031d0cb973
        ;;
    aarch64)
        arch=aarch64
        sha256=0a6e08595c5b0a38707ef94c0b0f81ebe1843305336c252bfdb77ef0eabe5a7d
        ;;
    *) exit 1 ;;
esac
curl -fSL "https://github.com/truffleruby/truffleruby/releases/download/graal-${TRUFFLERUBY_VERSION}/truffleruby-community-${TRUFFLERUBY_VERSION}-linux-${arch}.tar.gz" -o /tmp/truffleruby.tar.gz
echo "$sha256 /tmp/truffleruby.tar.gz" | sha256sum -c -
SHELL
