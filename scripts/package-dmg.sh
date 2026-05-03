#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:-VoiceInput.app}"
OUTPUT_DMG="${2:-VoiceInput.dmg}"
VOLUME_NAME="${3:-VoiceInput}"
STAGING_DIR="${TMPDIR:-/tmp}/voiceinput-dmg-staging-$$"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Missing app bundle: $APP_BUNDLE" >&2
    exit 1
fi

rm -f "$OUTPUT_DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"
