#!/bin/zsh
# Make the disk images for a GitHub release: Tidy and Ward, each signed with Developer ID,
# notarized by Apple and stapled, so they open on any Mac without a warning.
#
#   scripts/release.sh           build/Tidy-<version>.dmg and build/Ward-<version>.dmg
#   scripts/release.sh --check   only check that signing and notarization are set up
#
# Needs, once per Mac:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application).
#   2. A notarytool profile in the keychain; the default name is "notary" (or set NOTARY_PROFILE):
#        xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id <team ID>
#      It asks for an app-specific password from account.apple.com.
#
# Ward's scanning engine, ClamAV, is not in the image: users install it with Homebrew.

set -euo pipefail

ROOT="${0:A:h:h}"
PROFILE="${NOTARY_PROFILE:-notary}"
cd "$ROOT"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
problems=()
[[ "$IDENTITY" == "Developer ID Application:"* ]] \
  || problems+=("No \"Developer ID Application\" certificate in the keychain.")
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || problems+=("No notarytool profile named \"$PROFILE\" (see the top of this script).")
if (( ${#problems} )); then
  printf '%s\n' "${problems[@]}" >&2
  exit 1
fi
if [[ "${1:-}" == "--check" ]]; then
  echo "Ready to release: $IDENTITY, notary profile \"$PROFILE\"."
  exit 0
fi

SIGN_IDENTITY="$IDENTITY" scripts/build-apps.sh --no-install

for name in Tidy Ward; do
  app="build/$name.app"
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
  dmg="build/$name-$version.dmg"
  stage="build/dmg-$name"
  rm -rf "$stage" "$dmg"
  mkdir -p "$stage"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "$name" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
  rm -rf "$stage"

  codesign --force --sign "$IDENTITY" --timestamp "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
  echo "Release: $ROOT/$dmg"
  shasum -a 256 "$dmg"
done
