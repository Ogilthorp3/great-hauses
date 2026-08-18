#!/usr/bin/env bash
# testflight.sh — build Great Hauses for iPad and ship it to TestFlight.
#
#   ./tools/build/testflight.sh            # export + archive + .ipa, no upload
#   ./tools/build/testflight.sh --upload   # …and upload to App Store Connect
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
# WHY THE EXPORT METHOD MATTERS: TestFlight takes an APP STORE build.
# Ad-Hoc is signed to a fixed device list and App Store Connect rejects it.
# The preset carries method 0 (App Store) for release; do not "fix" it to
# Ad-Hoc because a device build was wanted — use --debug for that.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT/../great-hauses-dist/ios"
PRESET="iOS"
BUNDLE_ID="vc.triptyq.greathauses"
TEAM="GJ994MN2YF"
ASC_KEY_ID="DYWDH8NDH7"
ASC_ISSUER="bb24799c-61ce-4ae8-b07a-7138e06ec34c"

UPLOAD=0
CONFIG="release"
for arg in "$@"; do
  case "$arg" in
    --upload) UPLOAD=1 ;;
    --debug) CONFIG="debug" ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '\n[testflight] %s\n' "$*"; }

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
