#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LumiCue"
SCHEME="${SCHEME:-LumiCue}"
PROJECT="${PROJECT:-LumiCue.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/xcode-derived-data}"
SOURCE_PACKAGES_PATH="${SOURCE_PACKAGES_PATH:-$BUILD_DIR/source-packages}"
PACKAGE_CACHE_PATH="${PACKAGE_CACHE_PATH:-$BUILD_DIR/package-cache}"
HOME_OVERRIDE="${HOME_OVERRIDE:-$BUILD_DIR/home}"
STAGING_DIR="$BUILD_DIR/dmg-staging"

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION=$(
    HOME="$HOME_OVERRIDE" xcodebuild \
      -project "$ROOT_DIR/$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
      -packageCachePath "$PACKAGE_CACHE_PATH" \
      -disableAutomaticPackageResolution \
      -showBuildSettings 2>/dev/null \
      | awk '/MARKETING_VERSION/ { print $3; exit }' \
      || true
  )
fi
VERSION="${VERSION:-1.0.0}"

DMG_PATH="$BUILD_DIR/${APP_NAME}-v${VERSION}.dmg"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/${APP_NAME}.app"

info() { printf "info: %s\n" "$*"; }
fail() { printf "error: %s\n" "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_command xcodebuild
require_command hdiutil

mkdir -p "$BUILD_DIR"
mkdir -p "$HOME_OVERRIDE/Library/Caches/org.swift.swiftpm"

info "Building $APP_NAME ($CONFIGURATION)"
HOME="$HOME_OVERRIDE" xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH" \
  -packageCachePath "$PACKAGE_CACHE_PATH" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  SWIFT_STRICT_CONCURRENCY=minimal \
  build

[[ -d "$APP_PATH" ]] || fail "Built app not found: $APP_PATH"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  info "Signing app with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

info "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  info "Signing DMG with: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

info "Done: $DMG_PATH"
