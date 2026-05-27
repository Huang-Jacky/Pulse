#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="Pulse"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist"
DEFAULT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_TEMPLATE")"
VERSION="${1:-$DEFAULT_VERSION}"
BUILD_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_DIR/$PRODUCT_NAME-$VERSION.app"
STAGING_DIR="$BUILD_DIR/staging-$VERSION"
PAYLOAD_ROOT="$STAGING_DIR/pkg-root"
PAYLOAD_APP_DIR="$PAYLOAD_ROOT/Applications/$PRODUCT_NAME.app"
PKG_PATH="$BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"
DMG_STAGING_DIR="$STAGING_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/$PRODUCT_NAME-$VERSION.dmg"
APP_ICON_PATH="$ROOT_DIR/Packaging/AppIcon.icns"
LOCAL_HOME="$ROOT_DIR/.build/local-home"
LOCAL_CLANG_CACHE="$ROOT_DIR/.build/clang-module-cache"
LOCAL_SWIFT_MODULE_CACHE="$ROOT_DIR/.build/swift-module-cache"

mkdir -p "$BUILD_DIR" "$LOCAL_HOME" "$LOCAL_CLANG_CACHE" "$LOCAL_SWIFT_MODULE_CACHE"

rm -rf "$APP_DIR" "$STAGING_DIR" "$PKG_PATH" "$DMG_PATH"

if [[ ! -s "$APP_ICON_PATH" ]]; then
  echo "Missing app icon: $APP_ICON_PATH" >&2
  exit 1
fi

echo "==> Building release binary"
env \
  HOME="$LOCAL_HOME" \
  CLANG_MODULE_CACHE_PATH="$LOCAL_CLANG_CACHE" \
  SWIFT_MODULECACHE_PATH="$LOCAL_SWIFT_MODULE_CACHE" \
  swift build -c release
BIN_DIR="$(
  env \
    HOME="$LOCAL_HOME" \
    CLANG_MODULE_CACHE_PATH="$LOCAL_CLANG_CACHE" \
    SWIFT_MODULECACHE_PATH="$LOCAL_SWIFT_MODULE_CACHE" \
    swift build -c release --show-bin-path
)"
EXECUTABLE_PATH="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Release binary not found: $EXECUTABLE_PATH" >&2
  exit 1
fi

echo "==> Assembling app bundle"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$INFO_PLIST_TEMPLATE" "$APP_DIR/Contents/Info.plist"
cp "$APP_ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
  echo "==> Signing app bundle"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP_DIR"
fi

echo "==> Building installer package"
mkdir -p "$PAYLOAD_ROOT/Applications"
ditto "$APP_DIR" "$PAYLOAD_APP_DIR"

PKGBUILD_ARGS=(
  --root "$PAYLOAD_ROOT"
  --identifier "com.pulse.pkg"
  --version "$VERSION"
  --install-location /
  "$PKG_PATH"
)
if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
  PKGBUILD_ARGS=(--sign "$DEVELOPER_ID_INSTALLER" "${PKGBUILD_ARGS[@]}")
fi
pkgbuild "${PKGBUILD_ARGS[@]}"

echo "==> Building disk image"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_DIR" "$DMG_STAGING_DIR/$PRODUCT_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Artifacts ready:"
echo "  $APP_DIR"
echo "  $PKG_PATH"
echo "  $DMG_PATH"
