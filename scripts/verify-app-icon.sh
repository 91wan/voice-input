#!/bin/bash
set -euo pipefail

ICNS_PATH="${1:-Resources/AppIcon.icns}"
MASTER_PATH="${2:-Resources/AppIcon-master.png}"

fail() {
    echo "App icon verification failed: $*" >&2
    exit 1
}

validate_image() {
    local path="$1"
    local expected_format="$2"
    local expected_width="$3"
    local expected_height="$4"
    local properties
    local format
    local width
    local height

    test -s "$path" || fail "missing or empty file: $path"
    properties="$(sips -g format -g pixelWidth -g pixelHeight "$path" 2>/dev/null)"
    format="$(printf '%s\n' "$properties" | awk '/format:/ { print $2; exit }')"
    width="$(printf '%s\n' "$properties" | awk '/pixelWidth:/ { print $2; exit }')"
    height="$(printf '%s\n' "$properties" | awk '/pixelHeight:/ { print $2; exit }')"

    test "$format" = "$expected_format" || fail "$path format is $format, expected $expected_format"
    test "$width" = "$expected_width" || fail "$path width is $width, expected $expected_width"
    test "$height" = "$expected_height" || fail "$path height is $height, expected $expected_height"
}

test -s "$ICNS_PATH" || fail "missing or empty ICNS: $ICNS_PATH"
validate_image "$MASTER_PATH" png 1024 1024

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceinput-app-icon.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
ICONSET_PATH="$TMP_DIR/AppIcon.iconset"
ROUNDTRIP_PATH="$TMP_DIR/AppIcon-roundtrip.icns"

iconutil --convert iconset "$ICNS_PATH" --output "$ICONSET_PATH"

while read -r filename width height; do
    validate_image "$ICONSET_PATH/$filename" png "$width" "$height"
done <<'REPRESENTATIONS'
icon_16x16.png 16 16
icon_16x16@2x.png 32 32
icon_32x32.png 32 32
icon_32x32@2x.png 64 64
icon_128x128.png 128 128
icon_128x128@2x.png 256 256
icon_256x256.png 256 256
icon_256x256@2x.png 512 512
icon_512x512.png 512 512
icon_512x512@2x.png 1024 1024
REPRESENTATIONS

iconutil --convert icns "$ICONSET_PATH" --output "$ROUNDTRIP_PATH"
test -s "$ROUNDTRIP_PATH" || fail "iconutil round-trip produced an empty ICNS"

if ! cmp -s "$MASTER_PATH" "$ICONSET_PATH/icon_512x512@2x.png"; then
    shasum -a 256 "$MASTER_PATH" "$ICONSET_PATH/icon_512x512@2x.png" >&2
    fail "canonical master differs from the ICNS 1024px representation"
fi

echo "App icon verified: ICNS parsed, 10 representations validated, round-trip succeeded."
