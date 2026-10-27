# strip-tags: gnu

FROM public.ecr.aws/docker/library/debian:13

ARG REPRO_RUN_KEY=0

RUN echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries

# Retain the package index for compiler layers; refresh it through REPRO_RUN_KEY.
RUN true "${REPRO_RUN_KEY}" && apt-get update
RUN apt-get install -y \
    ca-certificates \
    curl \
    git \
    locales \
    tzdata \
    zlib1g \
    libstdc++6 \
    libmariadb3 \
    libpq5 \
    libsqlite3-0 \
    --no-install-recommends

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
RUN ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
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
mkdir -p /opt/truffleruby
tar -xzf /tmp/truffleruby.tar.gz --strip-components=1 -C /opt/truffleruby
rm /tmp/truffleruby.tar.gz
/opt/truffleruby/lib/truffle/post_install_hook.sh
SHELL

ENV PATH=/opt/truffleruby/bin:$PATH

COPY <<GEMRC /opt/truffleruby/etc/gemrc
install: --no-document
update: --no-document
GEMRC

# RubyGems retains the archive's build-time system configuration path.
ENV GEMRC=/opt/truffleruby/etc/gemrc \
    GEM_HOME=/usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH=$GEM_HOME/bin:$PATH
RUN mkdir -p "$GEM_HOME" && chmod 1777 "$GEM_HOME"

CMD [ "irb" ]
