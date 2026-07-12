#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN_ICON_SIZE=160
MIN_WINDOW_WIDTH=880
MIN_WINDOW_HEIGHT=500
MIN_HORIZONTAL_GAP=360

die() {
    echo "DMG Finder layout verification failed: $*" >&2
    exit 1
}

is_integer() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

require_integer() {
    local label="$1"
    local value="$2"

    is_integer "$value" || die "$label must be an integer, got '$value'"
}

parse_pair() {
    local label="$1"
    local csv="$2"
    local first second extra

    IFS=, read -r first second extra <<< "$csv"
    [ -n "${first:-}" ] && [ -n "${second:-}" ] && [ -z "${extra:-}" ] || die "$label must use x,y format, got '$csv'"
    require_integer "$label x" "$first"
    require_integer "$label y" "$second"

    printf '%s %s\n' "$first" "$second"
}

parse_bounds() {
    local csv="$1"
    local left top right bottom extra

    IFS=, read -r left top right bottom extra <<< "$csv"
    [ -n "${left:-}" ] && [ -n "${top:-}" ] && [ -n "${right:-}" ] && [ -n "${bottom:-}" ] && [ -z "${extra:-}" ] || \
        die "bounds must use left,top,right,bottom format, got '$csv'"
    require_integer "bounds left" "$left"
    require_integer "bounds top" "$top"
    require_integer "bounds right" "$right"
    require_integer "bounds bottom" "$bottom"

    printf '%s %s %s %s\n' "$left" "$top" "$right" "$bottom"
}

validate_layout_values() {
    local icon_size="$1"
    local bounds_csv="$2"
    local app_position_csv="$3"
    local applications_position_csv="$4"
    local left top right bottom app_x app_y applications_x applications_y
    local width height horizontal_gap

    require_integer "icon size" "$icon_size"
    read -r left top right bottom < <(parse_bounds "$bounds_csv")
    read -r app_x app_y < <(parse_pair "VoiceInput.app position" "$app_position_csv")
    read -r applications_x applications_y < <(parse_pair "Applications position" "$applications_position_csv")

    width=$((right - left))
    height=$((bottom - top))
    horizontal_gap=$((applications_x - app_x))

    if [ "$icon_size" -lt "$MIN_ICON_SIZE" ]; then
        die "icon size too small: expected >=${MIN_ICON_SIZE}, got ${icon_size}"
    fi
    if [ "$width" -lt "$MIN_WINDOW_WIDTH" ]; then
        die "window width too small: expected >=${MIN_WINDOW_WIDTH}, got ${width}"
    fi
    if [ "$height" -lt "$MIN_WINDOW_HEIGHT" ]; then
        die "window height too small: expected >=${MIN_WINDOW_HEIGHT}, got ${height}"
    fi
    if [ "$app_x" -ge "$applications_x" ]; then
        die "positions invalid: VoiceInput.app must be left of Applications"
    fi
    if [ "$horizontal_gap" -lt "$MIN_HORIZONTAL_GAP" ]; then
        die "horizontal gap too small: expected >=${MIN_HORIZONTAL_GAP}, got ${horizontal_gap}"
    fi

    echo "Verified DMG Finder layout: iconSize=${icon_size} bounds={${left},${top},${right},${bottom}} VoiceInput.app={${app_x},${app_y}} Applications={${applications_x},${applications_y}} horizontalGap=${horizontal_gap}"
}

read_mounted_layout() {
    local mount_dir="$1"

    "$SCRIPT_DIR/run-finder-applescript.sh" <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to POSIX file "$mount_dir" as alias
    open dmgFolder
    set current view of container window of dmgFolder to icon view
    set iconSizeValue to icon size of icon view options of container window of dmgFolder
    set boundsValue to bounds of container window of dmgFolder
    set appPosition to position of item "VoiceInput.app" of dmgFolder
    set applicationsPosition to position of item "Applications" of dmgFolder
    set boundsText to (item 1 of boundsValue as text) & "," & (item 2 of boundsValue as text) & "," & (item 3 of boundsValue as text) & "," & (item 4 of boundsValue as text)
    set appPositionText to (item 1 of appPosition as text) & "," & (item 2 of appPosition as text)
    set applicationsPositionText to (item 1 of applicationsPosition as text) & "," & (item 2 of applicationsPosition as text)
    close container window of dmgFolder
    return "iconSize=" & iconSizeValue & linefeed & "bounds=" & boundsText & linefeed & "appPosition=" & appPositionText & linefeed & "applicationsPosition=" & applicationsPositionText
end tell
APPLESCRIPT
}

if [ "${1:-}" = "--validate-values" ]; then
    [ "$#" -eq 5 ] || die "usage: $0 --validate-values ICON_SIZE BOUNDS APP_POSITION APPLICATIONS_POSITION"
    validate_layout_values "$2" "$3" "$4" "$5"
    exit 0
fi

MOUNT_DIR="${1:-}"
[ -n "$MOUNT_DIR" ] || die "missing mounted DMG directory"
[ -d "$MOUNT_DIR" ] || die "mounted DMG directory does not exist: $MOUNT_DIR"
[ -d "$MOUNT_DIR/VoiceInput.app" ] || die "missing VoiceInput.app in mounted DMG"
[ -L "$MOUNT_DIR/Applications" ] || die "missing Applications symlink in mounted DMG"
[ "$(readlink "$MOUNT_DIR/Applications")" = "/Applications" ] || die "Applications symlink must point to /Applications"
[ -f "$MOUNT_DIR/.DS_Store" ] || die "missing .DS_Store Finder layout metadata"

LAYOUT_OUTPUT="$(read_mounted_layout "$MOUNT_DIR")" || die "unable to read mounted DMG Finder layout"
ICON_SIZE="$(printf '%s\n' "$LAYOUT_OUTPUT" | awk -F= '$1 == "iconSize" { print $2 }')"
BOUNDS="$(printf '%s\n' "$LAYOUT_OUTPUT" | awk -F= '$1 == "bounds" { print $2 }')"
APP_POSITION="$(printf '%s\n' "$LAYOUT_OUTPUT" | awk -F= '$1 == "appPosition" { print $2 }')"
APPLICATIONS_POSITION="$(printf '%s\n' "$LAYOUT_OUTPUT" | awk -F= '$1 == "applicationsPosition" { print $2 }')"

[ -n "$ICON_SIZE" ] || die "unable to read icon size"
[ -n "$BOUNDS" ] || die "unable to read bounds"
[ -n "$APP_POSITION" ] || die "unable to read VoiceInput.app position"
[ -n "$APPLICATIONS_POSITION" ] || die "unable to read Applications position"

validate_layout_values "$ICON_SIZE" "$BOUNDS" "$APP_POSITION" "$APPLICATIONS_POSITION"
