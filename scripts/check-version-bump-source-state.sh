#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-}"

if [[ "${PHASE}" != "pre" && "${PHASE}" != "post" ]]; then
  echo "Usage: $0 pre|post" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ version-bump source-state check must run inside a git work tree." >&2
  exit 1
fi

is_allowed_dirty_path() {
  local path="$1"

  case "${PHASE}:${path}" in
    pre:CHANGELOG.md)
      return 0
      ;;
    post:README.md|post:Info.plist|post:CHANGELOG.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

dirty_paths="$( { git diff --name-only; git diff --cached --name-only; } | sort -u )"
untracked_paths="$(git ls-files --others --exclude-standard)"
unexpected_dirty=""

while IFS= read -r path; do
  [[ -z "${path}" ]] && continue
  if ! is_allowed_dirty_path "${path}"; then
    unexpected_dirty+="${path}"$'\n'
  fi
done <<< "${dirty_paths}"

failed=0

if [[ -n "${unexpected_dirty}" ]]; then
  if [[ "${PHASE}" == "pre" ]]; then
    echo "❌ version-bump preflight failed: unexpected dirty files before version bump." >&2
    echo "Only CHANGELOG.md may be dirty before make version-bump." >&2
  else
    echo "❌ version-bump postflight failed: unexpected dirty files after release-check." >&2
    echo "Only README.md, Info.plist, and CHANGELOG.md may be dirty before tagging." >&2
  fi
  printf '%s' "${unexpected_dirty}" | sed '/^$/d; s/^/ - /' >&2
  failed=1
fi

if [[ -n "${untracked_paths}" ]]; then
  echo "❌ version-bump ${PHASE}flight failed: untracked files would make the verified tree ambiguous." >&2
  printf '%s\n' "${untracked_paths}" | sed '/^$/d; s/^/ - /' >&2
  failed=1
fi

exit "${failed}"
