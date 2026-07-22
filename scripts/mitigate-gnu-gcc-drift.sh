#!/usr/bin/env bash
#
# TEMPORARY FIX - mitigate drift introduced by PR #91
# (https://github.com/DataDog/images-rb/pull/91), which upgraded
# RubyGems/Bundler to 4.0.16 for Ruby 3.2, 3.3, 3.4, 3.5, and 4.0.
#
# The `-gnu-gcc` tags for those versions are registry-side aliases
# (see `append-tags: gcc` in each Dockerfile.gnu, consumed by
# tasks/docker.rake) pointing at the same build as `-gnu`, not
# independent builds. CI does not appear to repoint them when the
# `-gnu` tag is rebuilt, so they were left stale on RubyGems 3.7.2 /
# Bundler 2.7.2 after PR #91 landed.
#
# This script re-points each affected `-gnu-gcc` tag at its
# corresponding up-to-date `-gnu` tag via scripts/retag-image.sh,
# using `yes` to auto-confirm each retag.
#
# Delete this script once CI is fixed to keep alias tags in sync with
# their source tag automatically.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

REGISTRY="ghcr.io"
REPO="datadog/images-rb"
IMAGE="${REGISTRY}/${REPO}/engines/ruby"

# Versions touched by PR #91.
VERSIONS=(3.2 3.3 3.4 3.5 4.0)

for version in "${VERSIONS[@]}"; do
    source="${IMAGE}:${version}-gnu"
    target="${IMAGE}:${version}-gnu-gcc"

    echo "=== ${target} ==="
    yes | scripts/retag-image.sh "${source}" "${target}"
    echo
done

echo "Done mitigating gnu-gcc drift for: ${VERSIONS[*]}"
