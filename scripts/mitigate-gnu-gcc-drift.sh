#!/usr/bin/env bash
#
# Mitigate drift introduced by PR #91
# (https://github.com/DataDog/images-rb/pull/91), which upgraded
# RubyGems/Bundler to 4.0.16 on the `-gnu` tags for Ruby 3.2, 3.3, 3.4,
# 3.5, and 4.0.
#
# The `-gnu-gcc` tags for those versions are registry-side aliases
# (see `append-tags: gcc` in each Dockerfile.gnu, consumed by
# tasks/docker.rake's `targets` method) that reuse the same
# Dockerfile.gnu as their `-gnu` counterpart, just tagged differently.
# Nothing repoints them automatically when `-gnu` is rebuilt, so they
# were left stale on RubyGems 3.7.2 / Bundler 2.7.2 after PR #91
# landed.
#
# This rebuilds and republishes each affected `*-gnu-gcc` tag from
# source via the project's own rake tasks (same mechanism CI uses),
# rather than copying an existing tag in the registry.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Versions touched by PR #91.
VERSIONS=(3.2 3.3 3.4 3.5 4.0)

# Build the comma-separated rake glob, e.g. "engines/ruby:3.2-gnu-gcc,engines/ruby:4.0-gnu-gcc"
TARGETS=""
for version in "${VERSIONS[@]}"; do
    TARGETS+="engines/ruby:${version}-gnu-gcc,"
done
TARGETS="${TARGETS%,}" # drop trailing comma

echo "Affected tags: ${TARGETS}"
echo

echo "==> Pulling current images so rake has a baseline to compare against"
rake "docker:pull[${TARGETS}]"

echo
echo "==> Rebuilding locally (no push yet) to confirm the fix works"
FORCE=true rake "docker:build[${TARGETS}]"

echo
read -r -p "Build looks good. Push these tags to the registry now? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Skipping push. Nothing was published."
    exit 0
fi

echo
echo "==> Rebuilding and pushing to the registry"
FORCE=true PUSH=true rake "docker:build[${TARGETS}]"

echo
echo "Done. Refreshed: ${TARGETS}"
