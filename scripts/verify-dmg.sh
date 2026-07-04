#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-VoiceInput.dmg}"
EXPECTED_VERSION="${2:-}"
VOLUME_NAME="${3:-VoiceInput}"
MOUNT_DIR="${TMPDIR:-/tmp}/voiceinput-dmg-verify-$$"
ATTACHED=0

cleanup() {
    if [ "$ATTACHED" -eq 1 ]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

if [ ! -f "$DMG_PATH" ]; then
    echo "Missing DMG: $DMG_PATH" >&2
    exit 1
fi

if [ -z "$EXPECTED_VERSION" ]; then
    echo "Missing expected app version." >&2
    exit 1
fi

mkdir -p "$MOUNT_DIR"

hdiutil attach \
    -nobrowse \
    -readonly \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" \
    "$DMG_PATH" >/dev/null
ATTACHED=1

test -d "$MOUNT_DIR/VoiceInput.app"
test -L "$MOUNT_DIR/Applications"
test "$(readlink "$MOUNT_DIR/Applications")" = "/Applications"
test -f "$MOUNT_DIR/.DS_Store"
test -s "$MOUNT_DIR/VoiceInput.app/Contents/Resources/AppIcon.icns"

./scripts/verify-dmg-layout.sh "$MOUNT_DIR"

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_DIR/VoiceInput.app/Contents/Info.plist")
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MOUNT_DIR/VoiceInput.app/Contents/Info.plist")
test "$SHORT_VERSION" = "$EXPECTED_VERSION"
test "$BUNDLE_VERSION" = "$EXPECTED_VERSION"

codesign --verify --deep --strict "$MOUNT_DIR/VoiceInput.app"

SPCTL_OUTPUT="$MOUNT_DIR/../voiceinput-spctl-$$.txt"
set +e
spctl -a -vvv -t execute "$MOUNT_DIR/VoiceInput.app" > "$SPCTL_OUTPUT" 2>&1
SPCTL_STATUS=$?
set -e
cat "$SPCTL_OUTPUT"
test "$SPCTL_STATUS" -ne 0
grep -qi "rejected" "$SPCTL_OUTPUT"
rm -f "$SPCTL_OUTPUT"

echo "Verified $VOLUME_NAME DMG: version=$SHORT_VERSION unsigned_gatekeeper=expected_rejected"
