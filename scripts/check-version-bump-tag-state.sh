#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
REMOTE="${2:-origin}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 vX.Y.Z [remote]" >&2
  exit 2
fi

if git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
  echo "❌ Tag ${VERSION} already exists locally." >&2
  exit 1
fi

set +e
remote_output="$(git ls-remote --exit-code --tags "${REMOTE}" "refs/tags/${VERSION}" 2>&1)"
remote_status=$?
set -e

case "${remote_status}" in
  0)
    echo "❌ Tag ${VERSION} already exists on ${REMOTE}." >&2
    printf '%s\n' "${remote_output}" >&2
    exit 1
    ;;
  2)
    exit 0
    ;;
  *)
    echo "❌ Unable to verify remote tag state for ${VERSION} on ${REMOTE}; refusing to create a release tag." >&2
    printf '%s\n' "${remote_output}" >&2
    exit 1
    ;;
esac
