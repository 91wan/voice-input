#!/usr/bin/env bash
set -euo pipefail

if [ "${FINDER_AUTOMATION_TIMEOUT_SECONDS+x}" = "x" ]; then
    TIMEOUT_SECONDS="$FINDER_AUTOMATION_TIMEOUT_SECONDS"
else
    TIMEOUT_SECONDS=60
fi

if [ "${OSASCRIPT_BIN+x}" = "x" ]; then
    OSASCRIPT_EXECUTABLE="$OSASCRIPT_BIN"
else
    OSASCRIPT_EXECUTABLE=/usr/bin/osascript
fi

if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "FINDER_AUTOMATION_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 2
fi

if [ ! -x "$OSASCRIPT_EXECUTABLE" ]; then
    echo "OSASCRIPT_BIN is missing or not executable: $OSASCRIPT_EXECUTABLE" >&2
    exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceinput-finder-applescript.XXXXXX")"
SCRIPT_FILE="$TMP_DIR/script.applescript"
STDOUT_FILE="$TMP_DIR/stdout"
STDERR_FILE="$TMP_DIR/stderr"
CHILD_PID=""

terminate_owned_child() {
    if [ -z "$CHILD_PID" ]; then
        return 0
    fi

    if kill -0 "$CHILD_PID" >/dev/null 2>&1; then
        kill -TERM "$CHILD_PID" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            if ! kill -0 "$CHILD_PID" >/dev/null 2>&1; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "$CHILD_PID" >/dev/null 2>&1; then
            kill -KILL "$CHILD_PID" >/dev/null 2>&1 || true
        fi
    fi

    wait "$CHILD_PID" >/dev/null 2>&1 || true
    CHILD_PID=""
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    terminate_owned_child
    rm -rf "$TMP_DIR"
    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

cat > "$SCRIPT_FILE"

"$OSASCRIPT_EXECUTABLE" "$SCRIPT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
CHILD_PID=$!
TIMED_OUT=0
ELAPSED_TICKS=0
MAX_TICKS=$((TIMEOUT_SECONDS * 10))

while kill -0 "$CHILD_PID" >/dev/null 2>&1; do
    if [ "$ELAPSED_TICKS" -ge "$MAX_TICKS" ]; then
        TIMED_OUT=1
        break
    fi
    sleep 0.1
    ELAPSED_TICKS=$((ELAPSED_TICKS + 1))
done

if [ "$TIMED_OUT" -eq 1 ]; then
    terminate_owned_child
    cat "$STDERR_FILE" >&2
    echo "Finder automation timed out after ${TIMEOUT_SECONDS}s. Re-run in a logged-in GUI session with Finder Automation access." >&2
    exit 124
fi

set +e
wait "$CHILD_PID"
CHILD_STATUS=$?
set -e
CHILD_PID=""

cat "$STDOUT_FILE"
cat "$STDERR_FILE" >&2

if [ "$CHILD_STATUS" -ne 0 ]; then
    echo "Finder automation failed. Re-run in a logged-in GUI session and confirm Finder Automation access." >&2
    exit "$CHILD_STATUS"
fi
