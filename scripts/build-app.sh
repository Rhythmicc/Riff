#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/dist/Riff.app"
typeset -a SWIFT_ARGS
SWIFT_ARGS=(-c "$CONFIGURATION")

if [[ "${RIFF_UNIVERSAL:-0}" == "1" ]]; then
    SWIFT_ARGS+=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
swift build "${SWIFT_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/Riff" "$APP/Contents/MacOS/Riff"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${RIFF_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${RIFF_VERSION#v}" "$APP/Contents/Info.plist"
fi
if [[ -n "${RIFF_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RIFF_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

SIGNING_IDENTITY="${RIFF_CODESIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # A plain ad-hoc signature uses the executable's changing cdhash as its
    # designated requirement. Keep a stable local requirement so Accessibility
    # and Keychain permissions survive rebuilds on this Mac.
    BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
    LOCAL_REQUIREMENT="=designated => identifier \"$BUNDLE_IDENTIFIER\""
    codesign --force --deep --sign - --requirements "$LOCAL_REQUIREMENT" "$APP"
    print -u2 "warning: Riff is locally signed with a stable designated requirement."
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
fi

echo "$APP"
