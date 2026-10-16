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
# permission again after every build. A certificate also turns on the hardened runtime, as in
# releases; a "Developer ID Application" one adds a secure timestamp, as notarization requires
# (scripts/release.sh).

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
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
  cp "$BIN/$exe" "$app/Contents/MacOS/$exe"
  # Libraries load from the bundle only: the build may add search paths outside it, and a
  # library planted there would load into the app.
  local binary="$app/Contents/MacOS/$exe" rpath
  for rpath in ${(u)${(f)"$(otool -l "$binary" | awk '/LC_RPATH/ { getline; getline; print $2 }')"}}; do
    install_name_tool -delete_rpath "$rpath" "$binary"
  done
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$binary"
  # Sparkle, for updates. The apps are not sandboxed, so Sparkle's XPC services are left out.
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  ditto "$BIN/Sparkle.framework" "$sparkle"
  rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"

  rm -rf "$BUILD/$exe.iconset"
  swift "$ROOT/scripts/make-icon.swift" "$icon" "$BUILD/$exe.iconset"
  iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$BUILD/$exe.iconset"

  sed -e "s/__EXE__/$exe/g" -e "s/__BUNDLE_ID__/$bundle_id/g" -e "s/__VERSION__/$VERSION/g" \
    -e "s/__FEED__/${exe:l}-appcast.xml/g" "$ROOT/Resources/Info.plist.in" > "$app/Contents/Info.plist"

  # Inside out, never --deep: Sparkle's helpers, Sparkle, then the app.
  sign "$sparkle/Versions/B/Autoupdate"
  sign "$sparkle/Versions/B/Updater.app"
  sign "$sparkle"
  sign "$app"
  codesign --verify --strict --deep "$app"
}

sign() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$1"
  elif [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
  else
    codesign --force --options runtime --sign "$IDENTITY" "$1"
  fi
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
  # Moved, not copied: macOS lists every app bundle it finds, so a copy left in build/ would
  # show up in Spotlight and the app list as a second app.
  rm -rf "$HOME/Applications/$exe.app"
  mv "$BUILD/$exe.app" "$HOME/Applications/$exe.app"
  echo "Installed: $HOME/Applications/$exe.app"
done

if [[ "$MODE" != "--no-start" ]]; then
  open "$HOME/Applications/Tidy.app" "$HOME/Applications/Ward.app"
fi
