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

TARGETS=()
for version in "${VERSIONS[@]}"; do
    TARGETS+=("engines/ruby:${version}-gnu-gcc")
done

echo "Syncing local images..."
rake "docker:pull[$(IFS=,; echo "${TARGETS[*]}")]"

echo
echo "Building (no push) to verify..."
FORCE=true rake "docker:build[$(IFS=,; echo "${TARGETS[*]}")]"

echo
read -r -p "Build succeeded. Push ${TARGETS[*]} to the registry now? [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Skipping push."
    exit 0
fi

echo "Building and pushing..."
FORCE=true PUSH=true rake "docker:build[$(IFS=,; echo "${TARGETS[*]}")]"

echo
echo "Done mitigating gnu-gcc drift for: ${VERSIONS[*]}"
