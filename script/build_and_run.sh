#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VividUpscaler"
BUNDLE_ID="com.ericcirone.VividUpscaler"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_RESOURCES="$APP_CONTENTS/Resources"
CLI_RESOURCES="$APP_RESOURCES/CLI"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/swiftpm-module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"
swift build --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build/swiftpm"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build/swiftpm" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$CLI_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# install.sh is the single source of truth for the CLI and its Python helper.
# Extract those payloads into the app so the GUI and terminal command execute
# the exact same implementation.
awk '/^cat > "\$INSTALL_ROOT\/vivid_upscale.py" <<'\''PY'\''$/ { copying=1; next } copying && /^PY$/ { exit } copying' \
  "$ROOT_DIR/install.sh" > "$CLI_RESOURCES/vivid_upscale.py"
awk '/^cat > "\$INSTALL_ROOT\/vivid_seedvr2.py" <<'\''PY'\''$/ { copying=1; next } copying && /^PY$/ { exit } copying' \
  "$ROOT_DIR/install.sh" > "$CLI_RESOURCES/vivid_seedvr2.py"
awk '/^cat > "\$INSTALL_ROOT\/vivid_codeformer.py" <<'\''PY'\''$/ { copying=1; next } copying && /^PY$/ { exit } copying' \
  "$ROOT_DIR/install.sh" > "$CLI_RESOURCES/vivid_codeformer.py"
awk '/^cat > "\$BIN_DIR\/vvd" <<'\''WRAPPER'\''$/ { copying=1; next } copying && /^WRAPPER$/ { exit } copying' \
  "$ROOT_DIR/install.sh" > "$CLI_RESOURCES/vvd"
cp "$ROOT_DIR/install.sh" "$CLI_RESOURCES/install.sh"
[[ -s "$CLI_RESOURCES/vvd" && -s "$CLI_RESOURCES/vivid_upscale.py" && -s "$CLI_RESOURCES/vivid_seedvr2.py" && -s "$CLI_RESOURCES/vivid_codeformer.py" ]] || {
  echo "Failed to extract the shared CLI payload from install.sh" >&2
  exit 1
}
chmod +x "$CLI_RESOURCES/vvd" "$CLI_RESOURCES/vivid_upscale.py" "$CLI_RESOURCES/vivid_seedvr2.py" "$CLI_RESOURCES/vivid_codeformer.py" "$CLI_RESOURCES/install.sh"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Vivid Upscaler</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  build) ;;
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *) echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
