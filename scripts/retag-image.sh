#!/usr/bin/env bash
#
# TEMPORARY FIX mechanism - retag an existing published image to another tag
# without going through the CI build pipeline.
#
# Use this only as a stopgap (e.g. pointing a stale/broken tag at a known-good
# one) while the real fix lands through CI. It performs a registry-side copy
# (docker buildx imagetools create), so it is multi-arch safe and does not
# require pulling image layers locally.
#
# Usage:
#   scripts/retag-image.sh <source-image:tag> <target-image:tag>
#
# Example:
#   scripts/retag-image.sh \
#     ghcr.io/datadog/images-rb/engines/ruby:4.0-gnu \
#     ghcr.io/datadog/images-rb/engines/ruby:4.0-gnu-gcc

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <source-image:tag> <target-image:tag>" >&2
    exit 1
fi

SOURCE="$1"
TARGET="$2"

echo "Inspecting source ${SOURCE}..."
docker buildx imagetools inspect "${SOURCE}" >/dev/null

read -r -p "This will overwrite ${TARGET} in the registry to match ${SOURCE}. Continue? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Aborted."
    exit 1
fi

echo "Retagging ${SOURCE} -> ${TARGET} directly in the registry (multi-arch safe)..."
docker buildx imagetools create --tag "${TARGET}" "${SOURCE}"

echo "Verifying..."
docker run --rm --pull always "${TARGET}" /bin/sh -c '
    echo "ruby:   $(ruby --version 2>/dev/null || echo n/a)"
    echo "gem:    $(gem --version 2>/dev/null || echo n/a)"
    echo "bundle: $(bundle --version 2>/dev/null || echo n/a)"
'

echo "Done. ${TARGET} now matches ${SOURCE}."
