#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-VoiceInput.app}"
OUTPUT_DMG="${2:-VoiceInput.dmg}"
VOLUME_NAME="${3:-VoiceInput}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="${TMPDIR:-/tmp}/voiceinput-dmg-staging-$$"
RW_DMG="${TMPDIR:-/tmp}/voiceinput-dmg-rw-$$.dmg"
MOUNT_DIR="${TMPDIR:-/tmp}/voiceinput-dmg-mount-$$"
ATTACHED=0

detach_mounted_dmg() {
    if [ "$ATTACHED" -eq 0 ]; then
        return 0
    fi

    if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
        ATTACHED=0
        return 0
    fi
    if hdiutil detach -force "$MOUNT_DIR" >/dev/null 2>&1; then
        ATTACHED=0
        return 0
    fi

    echo "Failed to detach temporary DMG mount: $MOUNT_DIR" >&2
    return 1
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if ! detach_mounted_dmg && [ "$status" -eq 0 ]; then
        status=1
    fi
    rm -rf "$STAGING_DIR"
    if [ "$ATTACHED" -eq 0 ]; then
        rm -rf "$MOUNT_DIR"
        rm -f "$RW_DMG"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Missing app bundle: $APP_BUNDLE" >&2
    exit 1
fi

rm -f "$OUTPUT_DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING_DIR"
rm -rf "$MOUNT_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$MOUNT_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG"

hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" \
    "$RW_DMG" >/dev/null
ATTACHED=1

"$SCRIPT_DIR/run-finder-applescript.sh" <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to POSIX file "$MOUNT_DIR" as alias
    open dmgFolder
    set current view of container window of dmgFolder to icon view
    set toolbar visible of container window of dmgFolder to false
    set statusbar visible of container window of dmgFolder to false
    set bounds of container window of dmgFolder to {100, 100, 980, 620}
    set arrangement of icon view options of container window of dmgFolder to not arranged
    set icon size of icon view options of container window of dmgFolder to 160
    set position of item "VoiceInput.app" of dmgFolder to {260, 240}
    set position of item "Applications" of dmgFolder to {700, 240}
    update dmgFolder without registering applications
    delay 1
    close container window of dmgFolder
end tell
APPLESCRIPT

test -f "$MOUNT_DIR/.DS_Store"
sync
detach_mounted_dmg
rm -rf "$MOUNT_DIR"

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -o "$OUTPUT_DMG"
