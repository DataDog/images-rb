# append-tags: gcc
FROM eclipse-temurin:22-jammy AS jruby-10.0.0.1-jre22

ENV JRUBY_VERSION=10.0.2.0
ENV JRUBY_SHA256=b8a026f38aa98461a04ed0aa0b20891ce257ecbe53e124719ce9ee5b804525f1
RUN curl -fSL https://repo1.maven.org/maven2/org/jruby/jruby-dist/${JRUBY_VERSION}/jruby-dist-${JRUBY_VERSION}-bin.tar.gz -o /tmp/jruby.tar.gz
