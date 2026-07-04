#!/usr/bin/env bash
set -euo pipefail

CHANGELOG_FILE="${1:-}"
TAG="${2:-}"

if [ -z "$CHANGELOG_FILE" ] || [ -z "$TAG" ]; then
  echo "Usage: $0 CHANGELOG.md vX.Y.Z" >&2
  exit 1
fi

if [ "$TAG" = "Unreleased" ] || [ "$TAG" = "[Unreleased]" ]; then
  echo "CHANGELOG.md [Unreleased] is not valid tag release notes" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "CHANGELOG.md not found: $CHANGELOG_FILE" >&2
  exit 1
fi

awk -v tag="$TAG" '
function headingName(line, heading) {
  heading = line
  sub(/^##[[:space:]]+\[/, "", heading)
  sub(/^##[[:space:]]+/, "", heading)
  sub(/\].*$/, "", heading)
  sub(/[[:space:]].*$/, "", heading)
  return heading
}

/^##[[:space:]]+/ {
  if (found) {
    done = 1
    next
  }
  if (headingName($0) == tag) {
    found = 1
  }
  next
}

done {
  next
}

found {
  if (!started && $0 ~ /^[[:space:]]*$/) {
    next
  }
  started = 1
  lines[++count] = $0
}

END {
  if (!found) {
    exit 2
  }
  while (count > 0 && lines[count] ~ /^[[:space:]]*$/) {
    count--
  }
  if (count == 0) {
    exit 3
  }
  for (i = 1; i <= count; i++) {
    print lines[i]
  }
}
' "$CHANGELOG_FILE" || {
  status=$?
  if [ "$status" -eq 2 ]; then
    echo "CHANGELOG.md missing release notes for ${TAG}" >&2
  elif [ "$status" -eq 3 ]; then
    echo "CHANGELOG.md release notes for ${TAG} are empty" >&2
  else
    echo "Failed to extract release notes for ${TAG}" >&2
  fi
  exit 1
}
