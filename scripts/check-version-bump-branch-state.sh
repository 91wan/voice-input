#!/usr/bin/env bash
set -euo pipefail

RELEASE_BRANCH="${1:-main}"
REMOTE="${2:-origin}"

if [[ -z "${RELEASE_BRANCH}" || -z "${REMOTE}" ]]; then
  echo "Usage: $0 [release-branch] [remote]" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ version-bump branch-state check must run inside a git work tree." >&2
  exit 1
fi

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "${current_branch}" ]]; then
  echo "❌ version-bump must run on ${RELEASE_BRANCH}, not detached HEAD." >&2
  exit 1
fi

if [[ "${current_branch}" != "${RELEASE_BRANCH}" ]]; then
  echo "❌ version-bump must run on ${RELEASE_BRANCH}; current branch is ${current_branch}." >&2
  exit 1
fi

remote_ref="refs/remotes/${REMOTE}/${RELEASE_BRANCH}"

if ! git fetch --quiet "${REMOTE}" "refs/heads/${RELEASE_BRANCH}:${remote_ref}"; then
  echo "❌ Unable to fetch ${REMOTE}/${RELEASE_BRANCH}; refusing to create a release tag." >&2
  exit 1
fi

local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse "${remote_ref}")"

if [[ "${local_head}" != "${remote_head}" ]]; then
  echo "❌ Local ${RELEASE_BRANCH} is not identical to ${REMOTE}/${RELEASE_BRANCH}." >&2
  echo "Local:  ${local_head}" >&2
  echo "Remote: ${remote_head}" >&2
  echo "Sync ${RELEASE_BRANCH} with ${REMOTE}/${RELEASE_BRANCH} before make version-bump, then pass the PR/main gate." >&2
  exit 1
fi
