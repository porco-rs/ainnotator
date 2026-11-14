#!/bin/bash
# Assemble and sign AInnotator.app from a SwiftPM release binary.
# Usage: tools/build-app-bundle.sh <release-binary> <out-dir>
# Signing identity: $AI_SIGN_IDENTITY, defaulting to a Developer ID Application identity when the keychain holds one,
# otherwise ad hoc signing (`AI_SIGN_IDENTITY=-`). A stable identity keeps the Screen Recording and Automation grants
# across rebuilds; an ad hoc signature changes with every build, so macOS asks again.
# $AI_TEAM_ID, when set, makes the script verify that the signature belongs to that team.
# RELEASE=1 requires AI_TEAM_ID and a real identity.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'usage: %s <release-binary> <out-dir>\n' "$0" >&2
    exit 64
fi

SOURCE_BINARY=$1
OUTPUT_DIR=$2
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
INFO_PLIST="$ROOT/Bundle/Info.plist"
ENTITLEMENTS="$ROOT/Bundle/AInnotator.entitlements"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)
[[ -n "$BUNDLE_ID" ]] || { printf 'CFBundleIdentifier missing or empty in %s\n' "$INFO_PLIST" >&2; exit 1; }
TEAM_ID=${AI_TEAM_ID:-}
if [[ -n ${AI_SIGN_IDENTITY:-} ]]; then
    SIGN_IDENTITY=$AI_SIGN_IDENTITY
    printf 'Signing identity: %s\n' "$([[ $SIGN_IDENTITY == - ]] && printf 'ad hoc' || printf 'explicit identity')"
elif [[ $(security find-identity -v -p codesigning 2>/dev/null || true) == *'Developer ID Application:'* ]]; then
    SIGN_IDENTITY="Developer ID Application"
    printf 'Signing identity: Developer ID Application (found in the keychain)\n'
else
    SIGN_IDENTITY=-
    printf 'Signing identity: ad hoc (no Developer ID Application identity found; macOS will ask for permissions again after each build)\n'
fi
if [[ ${RELEASE:-0} == 1 && ( -z $TEAM_ID || $SIGN_IDENTITY == - ) ]]; then
    printf 'release signing requires AI_TEAM_ID and a non-ad-hoc identity\n' >&2
    exit 1
fi
TIMESTAMP=--timestamp=none
if [[ ${RELEASE:-0} == 1 ]]; then TIMESTAMP=--timestamp; fi

[[ -x "$SOURCE_BINARY" ]] || { printf 'release binary missing or not executable: %s\n' "$SOURCE_BINARY" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { printf 'Info.plist missing: %s\n' "$INFO_PLIST" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd -P)
BUNDLE="$OUTPUT_DIR/AInnotator.app"
STAGING="$OUTPUT_DIR/.AInnotator.app.$$.new"
BACKUP="$OUTPUT_DIR/.AInnotator.app.$$.old"

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    [[ -e "$STAGING" ]] && rm -rf "$STAGING"
    [[ -e "$BACKUP" && ! -e "$BUNDLE" ]] && mv "$BACKUP" "$BUNDLE"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$SOURCE_BINARY" "$STAGING/Contents/MacOS/AInnotator"
# Debug symbols name the folder the app was built in, so shipped binaries carry none.
/usr/bin/strip -S -x "$STAGING/Contents/MacOS/AInnotator" 2>/dev/null
chmod 0755 "$STAGING/Contents/MacOS/AInnotator"
cp "$INFO_PLIST" "$STAGING/Contents/Info.plist"
cp "$ROOT/Bundle/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"
# The language folders make the system report its language to Bundle.main, and carry the permission texts.
for LANGUAGE_DIR in "$ROOT"/Bundle/*.lproj; do
    [[ -d "$LANGUAGE_DIR" ]] || continue
    cp -R "$LANGUAGE_DIR" "$STAGING/Contents/Resources/$(basename "$LANGUAGE_DIR")"
done
# License texts travel with the binary.
mkdir -p "$STAGING/Contents/Resources/licenses"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$STAGING/Contents/Resources/licenses/"

codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" --options runtime \
    --entitlements "$ENTITLEMENTS" "$TIMESTAMP" "$STAGING"
codesign --verify --deep --strict "$STAGING"
if [[ -n $TEAM_ID ]]; then
    codesign -v -R="anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\" and identifier \"$BUNDLE_ID\"" \
        "$STAGING"
fi

if [[ -e "$BUNDLE" || -L "$BUNDLE" ]]; then
    mv "$BUNDLE" "$BACKUP"
fi
mv "$STAGING" "$BUNDLE"
rm -rf "$BACKUP"
trap - EXIT HUP INT TERM
printf '%s\n' "$BUNDLE"
