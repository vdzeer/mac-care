#!/bin/zsh
# Make the disk images for a GitHub release: Tidy and Ward, each signed with Developer ID,
# notarized by Apple and stapled, so they open on any Mac without a warning.
#
#   scripts/release.sh           build/Tidy-<version>.dmg, build/Ward-<version>.dmg and their update
#                                feeds build/tidy-appcast.xml and build/ward-appcast.xml
#   scripts/release.sh --check   only check that signing, notarization and the update key are set up
#
# Attach all four files to one GitHub release tagged v<version>: installed copies read their feed
# from the latest release and update themselves (Sparkle). The version is VERSION in
# scripts/build-apps.sh; raise it before a release.
#
# Needs, once per Mac:
#   1. A "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application).
#   2. A notarytool profile in the keychain; the default name is "notary" (or set NOTARY_PROFILE):
#        xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id <team ID>
#      It asks for an app-specific password from account.apple.com.
#   3. The update signing key in the login keychain, the one whose public half is SUPublicEDKey in
#      Resources/Info.plist.in. Made once with .build/artifacts/sparkle/Sparkle/bin/generate_keys;
#      keep a copy (generate_keys -x <file>) somewhere safe: without it no update can reach
#      installed copies.
#
# Ward's scanning engine, ClamAV, is not in the image: users install it with Homebrew.

set -euo pipefail

ROOT="${0:A:h:h}"
REPO="https://github.com/vdzeer/mac-care"
PROFILE="${NOTARY_PROFILE:-notary}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
cd "$ROOT"
swift package resolve >/dev/null

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
problems=()
[[ "$IDENTITY" == "Developer ID Application:"* ]] \
  || problems+=("No \"Developer ID Application\" certificate in the keychain.")
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || problems+=("No notarytool profile named \"$PROFILE\" (see the top of this script).")
PUBLIC_KEY="$(sed -n 's/.*<key>SUPublicEDKey<\/key><string>\([^<]*\)<.*/\1/p' Resources/Info.plist.in)"
[[ -n "$PUBLIC_KEY" && "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$PUBLIC_KEY" ]] \
  || problems+=("The update signing key in the keychain does not match SUPublicEDKey in Resources/Info.plist.in.")
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
  [[ "$version" =~ '^[0-9]+(\.[0-9]+)*$' ]] || { echo "Odd version: $version" >&2; exit 1; }
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

  # The update feed: one item, this version. Sparkle checks the EdDSA signature before installing.
  feed="build/${name:l}-appcast.xml"
  signature="$("$SPARKLE_BIN/sign_update" "$dmg")"
  minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$app/Contents/Info.plist")"
  cat > "$feed" <<FEED
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$name</title>
    <item>
      <title>$name $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO/releases/tag/v$version</sparkle:fullReleaseNotesLink>
      <enclosure url="$REPO/releases/download/v$version/$name-$version.dmg" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
FEED
  # The feed itself is signed too (SURequireSignedFeed): sign_update embeds the signature in it.
  "$SPARKLE_BIN/sign_update" "$feed"
  echo "Release: $ROOT/$dmg and $ROOT/$feed"
  shasum -a 256 "$dmg"
done
echo "Publish: gh release create v$version build/Tidy-$version.dmg build/Ward-$version.dmg build/tidy-appcast.xml build/ward-appcast.xml"
