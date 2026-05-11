#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BrewGraph"
SCHEME_NAME="HomebrewLens"
BUNDLE_ID="dev.local.brewgraph"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
RELEASE_APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
release_version() {
  if [[ -n "${RELEASE_VERSION:-}" ]]; then
    echo "$RELEASE_VERSION"
    return
  fi

  git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null \
    || git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null \
    || echo "local"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

build_app() {
  xcodebuild \
    -project "$ROOT_DIR/HomebrewLens.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    build
}

build_release_app() {
  xcodebuild \
    -project "$ROOT_DIR/HomebrewLens.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

package_release() {
  local version
  local release_zip
  version="$(release_version)"
  release_zip="$ROOT_DIR/build/$APP_NAME-$version.zip"

  build_release_app
  file "$RELEASE_APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "arm64"
  otool -l "$RELEASE_APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q "minos 14.0"
  codesign -dvvv --entitlements :- "$RELEASE_APP_BUNDLE" >/dev/null 2>&1
  mkdir -p "$ROOT_DIR/build"
  rm -f "$release_zip"
  ditto -c -k --keepParent "$RELEASE_APP_BUNDLE" "$release_zip"
  test -s "$release_zip"
  echo "$release_zip"
}

case "$MODE" in
  --release-package|release-package)
    package_release
    exit 0
    ;;
esac

build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --missing-brew|missing-brew)
    launchctl setenv BREWGRAPH_FORCE_MISSING_HOMEBREW 1
    trap 'launchctl unsetenv BREWGRAPH_FORCE_MISSING_HOMEBREW' EXIT
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--missing-brew|--release-package]" >&2
    exit 2
    ;;
esac
