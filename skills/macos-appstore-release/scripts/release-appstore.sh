#!/bin/bash
# Archive, sign, package, and upload a sandboxed Mac App Store build to App Store Connect.
#
# This bypasses `xcodebuild -exportArchive` entirely. See ../SKILL.md and
# ../references/exportarchive-bug.md for why: every archive this toolchain produces is missing
# ApplicationProperties from its Info.plist, which makes IDEDistributionMethodManager reject
# every distribution method — reproduced identically from a plain Terminal, Xcode's own
# Organizer, and Xcode Cloud's build servers. Not a signing/account/certificate problem, so no
# amount of -allowProvisioningUpdates or Xcode sign-in fixes it. Instead: productbuild signs a
# .pkg straight from the archived .app (no export step involved), and `altool --upload-package`
# is a completely separate upload path, unaffected by IDEDistributionMethodManager.
#
# ───────────────────────────────────────────────────────────────────────────────────────────
# SETUP — do this once, see ../SKILL.md's pre-flight checklist for the full walkthrough:
#   1. Register the bundle ID as an Identifier with every capability the app uses.
#   2. Create two certificates manually (via a Keychain Access CSR, NOT -allowProvisioningUpdates
#      alone — confirmed unreliable across three environments):
#        - Apple Distribution            (signs the app)
#        - Mac Installer Distribution    (signs the .pkg; shows as "3rd Party Mac Developer
#                                          Installer" in `security find-identity`)
#   3. Create a Mac App Store provisioning profile for the bundle ID using the Apple
#      Distribution cert; name it something you'll recognize.
#   4. In project.yml, give the App Store build config:
#        CODE_SIGN_STYLE: Manual
#        CODE_SIGN_IDENTITY: "Apple Distribution"
#        PROVISIONING_PROFILE_SPECIFIER: "<exact profile name from step 3>"
#      Without this, Xcode silently ad-hoc-signs the archive (CODE_SIGN_IDENTITY[sdk=macosx*] =
#      "-") and every step below will "succeed" while producing something Apple will never accept.
#   5. App Store Connect → Users and Access → Integrations → App Store Connect API → generate a
#      key with the App Manager role, then:
#        mkdir -p ~/.appstoreconnect/private_keys
#        cp ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
#      (altool ignores an explicit key-path argument for --upload-package — it only searches
#      that fixed location.)
#
# CONFIGURE — edit the variables in the block below for your project, then:
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# USAGE:
#   scripts/release-appstore.sh            # archive + sign + package + upload
#   scripts/release-appstore.sh --export   # archive + sign + package only, no upload
set -euo pipefail
cd "$(dirname "$0")/.."

# ── Edit these for your project ──────────────────────────────────────────────────────────────
PROJECT="YourApp.xcodeproj"
SCHEME="YourApp-AppStore"            # or whatever your App Store Connect scheme is named
CONFIGURATION="AppStore"
APP_NAME="YourApp"                   # matches Products/Applications/<APP_NAME>.app in the archive
BUNDLE_ID="com.example.YourApp"
APP_SIGNING_IDENTITY="Apple Distribution: Your Name (TEAMID)"
INSTALLER_SIGNING_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"
USES_XCODEGEN=true                   # set false to skip the `xcodegen generate` step
# ──────────────────────────────────────────────────────────────────────────────────────────────

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key ID)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect API issuer ID)}"

UPLOAD=1
if [[ "${1:-}" == "--export" ]]; then UPLOAD=0; fi

BUILD_DIR="build/appstore"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
PKG_PATH="$BUILD_DIR/pkg/$APP_NAME.pkg"
# App Store Connect rejects a re-used build number for the same version; a timestamp is always
# increasing without having to bump the project for every upload.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

if [[ "$USES_XCODEGEN" == "true" ]]; then
  echo "==> Regenerating Xcode project"
  xcodegen generate
fi

# App Store Connect refuses an upload whose bundle carries com.apple.quarantine on any file
# (easy to pick up from a resource saved out of a browser). Strip it at the source.
echo "==> Clearing quarantine attributes from the project"
xattr -cr Sources Resources 2>/dev/null || true

echo "==> Archiving ($CONFIGURATION, build $BUILD_NUMBER)"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "==> Verifying signing identity"
# Not `codesign ... | grep -q ...`: under `set -o pipefail`, grep -q exiting the instant it finds
# a match can SIGPIPE the still-writing codesign process, making the pipeline's exit status
# reflect that SIGPIPE rather than grep's success. Capture output first instead.
SIGNING_INFO="$(codesign -dvvv "$APP_PATH" 2>&1)"
echo "$SIGNING_INFO" | grep -q "Authority=Apple Distribution" \
  || { echo "error: archived app is not signed with an Apple Distribution identity — this is the XcodeGen signing trap, see SKILL.md. Current signing identity:" >&2
       echo "$SIGNING_INFO" | grep "Authority=" >&2
       exit 1; }

echo "==> Verifying sandbox entitlement"
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP_PATH" 2>&1)"
echo "$ENTITLEMENTS" | grep -q "com.apple.security.app-sandbox" \
  || { echo "error: archived app is not sandboxed — App Store Connect will reject it" >&2; exit 1; }

if xattr -lr "$APP_PATH" | grep -q "com.apple.quarantine"; then
  echo "error: archived app still contains com.apple.quarantine — App Store Connect will reject it:" >&2
  xattr -lr "$APP_PATH" | grep "com.apple.quarantine" >&2
  exit 1
fi

echo "==> Checking for an app icon"
[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" || -f "$APP_PATH/Contents/Resources/Assets.car" ]] \
  && /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP_PATH/Contents/Info.plist" >/dev/null 2>&1 \
  || { echo "error: no app icon in the archive — App Store Connect will reject the upload" >&2; exit 1; }

echo "==> Building the installer package"
mkdir -p "$BUILD_DIR/pkg"
productbuild --component "$APP_PATH" /Applications \
  --sign "$INSTALLER_SIGNING_IDENTITY" \
  "$PKG_PATH"

if [[ "$UPLOAD" == "0" ]]; then
  echo ""
  echo "Done: $PKG_PATH"
  exit 0
fi

echo "==> Uploading to App Store Connect"
xcrun altool --upload-package "$PKG_PATH" \
  --type macos \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID"

echo ""
echo "Done: uploaded build $BUILD_NUMBER — it appears in App Store Connect → TestFlight/Builds after processing."
