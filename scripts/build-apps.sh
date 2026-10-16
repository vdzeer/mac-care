#!/bin/zsh
# Build Tidy and Ward, put them in ~/Applications and start them.
#
#   scripts/build-apps.sh               build, install, start both
#   scripts/build-apps.sh --no-start    build and install only
#   scripts/build-apps.sh --no-install  build into build/ only (for snapshots and checks)
#
# Signing: SIGN_IDENTITY names a certificate in your keychain. macOS ties Full Disk Access to
# the signature, so a fixed identity (an "Apple Development" one is enough) keeps the permission
# from one build to the next. Without SIGN_IDENTITY the apps are signed ad hoc and you grant the
# permission again after every build. A "Developer ID Application" identity also turns on the
# hardened runtime and a secure timestamp, as notarization requires (scripts/release.sh).

set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
MODE="${1:-}"
IDENTITY="${SIGN_IDENTITY:--}"
VERSION="1.0.0"

cd "$ROOT"
swift build -c release --product Tidy
swift build -c release --product Ward
BIN="$(swift build -c release --show-bin-path)"

assemble() {
  local exe="$1" icon="$2" bundle_id="$3"
  local app="$BUILD/$exe.app"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$BIN/$exe" "$app/Contents/MacOS/$exe"

  rm -rf "$BUILD/$exe.iconset"
  swift "$ROOT/scripts/make-icon.swift" "$icon" "$BUILD/$exe.iconset"
  iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$BUILD/$exe.iconset"

  sed -e "s/__EXE__/$exe/g" -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__VERSION__/$VERSION/g" \
    "$ROOT/Resources/Info.plist.in" > "$app/Contents/Info.plist"

  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$app"
  elif [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$app"
  else
    codesign --force --sign "$IDENTITY" "$app"
  fi
  codesign --verify --strict "$app"
}

assemble Tidy tidy com.vdzeer.tidy
assemble Ward ward com.vdzeer.ward

[[ "$MODE" == "--no-install" ]] && { echo "Built: $BUILD/Tidy.app, $BUILD/Ward.app"; exit 0; }

mkdir -p "$HOME/Applications"
for exe in Tidy Ward; do
  if pgrep -xq "$exe"; then
    # A normal Quit lets Ward stop its scanning engine; a kill would leave clamd running.
    osascript -e "quit app \"$exe\"" >/dev/null 2>&1 || true
    for _ in {1..100}; do pgrep -xq "$exe" || break; sleep 0.1; done
    pkill -x "$exe" || true
  fi
  rm -rf "$HOME/Applications/$exe.app"
  cp -R "$BUILD/$exe.app" "$HOME/Applications/$exe.app"
  echo "Installed: $HOME/Applications/$exe.app"
done

if [[ "$MODE" != "--no-start" ]]; then
  open "$HOME/Applications/Tidy.app" "$HOME/Applications/Ward.app"
fi
