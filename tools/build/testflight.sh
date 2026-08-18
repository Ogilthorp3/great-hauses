#!/usr/bin/env bash
# testflight.sh — build Great Hauses for iPad and ship it to TestFlight.
#
#   ./tools/build/testflight.sh                     # iOS: export + archive + .ipa
#   ./tools/build/testflight.sh --upload            # …and upload to TestFlight
#   ./tools/build/testflight.sh --visionos          # visionOS: archive + .ipa
#   ./tools/build/testflight.sh --visionos --upload # …and upload to TestFlight
#
# WHAT THIS NEEDS THAT A MAC BUILD DOES NOT
#
#   1. Xcode with the iOS DEVICE PLATFORM installed, not merely the SDK.
#      `xcodebuild -showsdks` listing "iOS 26.5" is NOT sufficient — the
#      archive fails with "iOS 26.5 is not installed. Please download and
#      install the platform from Xcode > Settings > Components", which reads
#      like a project error and is not one. Fix:
#          xcodebuild -downloadPlatform iOS      # 8.5 GB
#   2. A signing identity for team GJ994MN2YF. `security find-identity -v
#      -p codesigning` must list "Apple Distribution: Bertrand Nepveu".
#   3. An App Store Connect API key at
#      ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 — note the
#      private_keys/ subdirectory, which is where altool looks; the notarize
#      pipeline points at the parent and a symlink keeps both happy.
#   4. AN APP RECORD IN APP STORE CONNECT for the bundle id. This is the one
#      step no script can do here: creating it needs an Admin or App Manager
#      role and this key is a Developer key. Until that record exists, upload
#      fails with "no suitable application record was found".
#
# WHY THE BUNDLE ID IS haus.sanctum.*: this is a SANCTUM product, not a
# Triptyq one. The two lanes do not cross — the haus must not hang off the
# firm's identity, or the app is misfiled the day Bert leaves it. The rule
# (memory: haus-vs-product domains) is that anything a Sanctum USER touches
# lives at sanctum.haus / sanctum.run, which reverses to haus.sanctum.*;
# personal haus infrastructure would be nepveu.name. A chess game with a
# Sanctum cathedral and a Sanctum council in it is the product.
#
# WHY THE EXPORT METHOD MATTERS: TestFlight takes an APP STORE build.
# Ad-Hoc is signed to a fixed device list and App Store Connect rejects it.
# The preset carries method 0 (App Store) for release; do not "fix" it to
# Ad-Hoc because a device build was wanted — use --debug for that.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT/../great-hauses-dist/ios"
PRESET="iOS"
BUNDLE_ID="haus.sanctum.greathauses"
TEAM="GJ994MN2YF"
ASC_KEY_ID="DYWDH8NDH7"
ASC_ISSUER="bb24799c-61ce-4ae8-b07a-7138e06ec34c"

UPLOAD=0
CONFIG="release"
PLATFORM="ios"
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    --debug) CONFIG="debug" ;;
    --visionos) PLATFORM="visionos" ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\n[testflight] %s\n' "$*"; }

# ── visionOS ──────────────────────────────────────────────────────────────
# A DIFFERENT PIPELINE, not a flag on the iOS one. Godot's iOS exporter runs
# `xcodebuild archive` and `exportArchive` itself, so the iOS path below is
# one command. The visionOS exporter only writes the Xcode project — the
# archive and export are ours to drive, and they need the App Store method
# rather than the `debugging` method a device build leaves behind.
#
# THE BLOCKER YOU WILL HIT FIRST (2026-08-18): altool answers
#   "Cannot determine the Apple ID from Bundle ID 'haus.sanctum.greathauses'
#    and platform 'VISION_OS'"
# That is not a signing problem and not a build problem. It means the App
# Store Connect record has only the iOS platform on it. Adding visionOS is a
# one-time action in the App Store Connect UI (Apps -> Great Hauses Chess ->
# add the visionOS platform) and needs Account Holder / Admin / App Manager;
# a Developer-role API key is REFUSED (403 FORBIDDEN_ERROR, confirmed by
# POSTing an appStoreVersions record with platform VISION_OS). Once the
# platform exists, re-run this script and nothing else changes.
if [ "$PLATFORM" = "visionos" ]; then
  VDIST="$ROOT/../great-hauses-dist/visionos"
  ARCHIVE="$VDIST/GreatHauses-appstore.xcarchive"
  EXPORTED="$VDIST/appstore-export"

  if [ ! -d "$VDIST/GreatHauses.xcodeproj" ]; then
    echo "FAIL: no visionOS xcodeproj — run ./tools/build/build.sh visionos first" >&2
    exit 1
  fi
  if ! security find-identity -v -p codesigning | grep -q "$TEAM"; then
    echo "FAIL: no codesigning identity for team $TEAM" >&2; exit 1
  fi

  cat > "$VDIST/ExportOptions-appstore.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key><string>export</string>
	<key>method</key><string>app-store-connect</string>
	<key>signingStyle</key><string>automatic</string>
	<key>stripSwiftSymbols</key><true/>
	<key>teamID</key><string>$TEAM</string>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

  # THE iOS KEY IN A visionOS BUNDLE. Godot's visionOS exporter is derived
  # from the iOS one and stamps
  #     UIRequiredDeviceCapabilities = ["iphone-ipad-minimum-performance-a12"]
  # into the generated Info.plist. App Store Connect rejects the upload:
  #     "This bundle is invalid. The key UIRequiredDeviceCapabilities contains
  #      value 'iphone-ipad-minimum-performance-a12' which is incompatible with
  #      the MinimumOSVersion value of '26.0'. (90098)"
  # It is an iPhone/iPad chip-floor declaration and means nothing on a headset.
  # The export REGENERATES this file, so fixing the file by hand lasts exactly
  # until the next build — it has to be stripped here, at the point of use,
  # every time. Idempotent: absent key is not an error.
  VPLIST="$VDIST/GreatHauses/GreatHauses-Info.plist"
  if [ -f "$VPLIST" ] && /usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities" "$VPLIST" >/dev/null 2>&1; then
    say "stripping iOS-only UIRequiredDeviceCapabilities from the visionOS plist"
    /usr/libexec/PlistBuddy -c "Delete :UIRequiredDeviceCapabilities" "$VPLIST"
  fi

  say "archiving visionOS (generic/platform=visionOS)"
  rm -rf "$ARCHIVE" "$EXPORTED"
  xcodebuild -project "$VDIST/GreatHauses.xcodeproj" -scheme GreatHauses \
    -configuration Release -destination 'generic/platform=visionOS' \
    -archivePath "$ARCHIVE" archive

  say "exporting the archive (App Store method)"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORTED" \
    -exportOptionsPlist "$VDIST/ExportOptions-appstore.plist"

  VIPA="$EXPORTED/GreatHauses.ipa"
  [ -f "$VIPA" ] || { echo "FAIL: no .ipa at $VIPA" >&2; exit 1; }
  say "built: $VIPA ($(du -h "$VIPA" | cut -f1))"

  if [ "$UPLOAD" != "1" ]; then
    say "not uploading (pass --upload). Bundle: $BUNDLE_ID (visionOS)"
    exit 0
  fi
  KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [ -f "$KEY" ] || { echo "FAIL: ASC key not found at $KEY" >&2; exit 1; }

  say "validating with App Store Connect"
  xcrun altool --validate-app -f "$VIPA" -t visionos \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER"
  say "uploading to App Store Connect (TestFlight, visionOS)"
  xcrun altool --upload-app -f "$VIPA" -t visionos \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER"
  say "uploaded. TestFlight > visionOS builds for $BUNDLE_ID."
  exit 0
fi

# ── preflight, because every one of these failures is silent-ish ───────────
say "preflight"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "FAIL: no Xcode command line tools" >&2; exit 1
fi

# The platform, not the SDK. This is the check that would have saved an hour.
if ! xcodebuild -showdestinations -project "$DIST/GreatHauses.xcodeproj" \
      -scheme GreatHauses 2>/dev/null | grep -q "platform:iOS"; then
  if [ -d "$DIST/GreatHauses.xcodeproj" ]; then
    echo "WARN: no eligible iOS destination — is the iOS platform installed?" >&2
    echo "      xcodebuild -downloadPlatform iOS      # 8.5 GB" >&2
  fi
fi

if ! security find-identity -v -p codesigning | grep -q "$TEAM"; then
  echo "FAIL: no codesigning identity for team $TEAM" >&2; exit 1
fi
echo "  signing identities for $TEAM: ok"

KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [ "$UPLOAD" = "1" ] && [ ! -f "$KEY" ]; then
  echo "FAIL: ASC key not found at $KEY" >&2
  echo "      (the notarize pipeline keeps it one level up; symlink it here)" >&2
  exit 1
fi

# ── export ────────────────────────────────────────────────────────────────
# Godot's iOS exporter does the whole Apple dance itself: it writes the
# Xcode project, then runs `xcodebuild archive` and `exportArchive`. So a
# successful export leaves a signed .ipa and there is nothing further to
# assemble by hand.
mkdir -p "$DIST"
say "exporting preset '$PRESET' ($CONFIG) -> $DIST"
if [ "$CONFIG" = "release" ]; then
  godot --headless --path "$ROOT" --export-release "$PRESET" \
    "$DIST/GreatHauses.xcodeproj"
else
  godot --headless --path "$ROOT" --export-debug "$PRESET" \
    "$DIST/GreatHauses.xcodeproj"
fi

IPA="$(/usr/bin/find "$DIST" -name '*.ipa' -maxdepth 2 -print -quit 2>/dev/null || true)"
if [ -z "$IPA" ]; then
  echo "FAIL: export finished but produced no .ipa under $DIST" >&2
  exit 1
fi
say "built: $IPA ($(du -h "$IPA" | cut -f1))"

# ── upload ────────────────────────────────────────────────────────────────
if [ "$UPLOAD" != "1" ]; then
  say "not uploading (pass --upload). Bundle: $BUNDLE_ID"
  exit 0
fi

say "validating with App Store Connect before spending an upload"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER"

say "uploading to App Store Connect (TestFlight)"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER"

say "uploaded. Processing takes a few minutes; the build then appears under"
say "TestFlight > iOS builds for $BUNDLE_ID."
