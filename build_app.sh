#!/bin/bash
#
# Builds Offloadly.app from source using the Swift compiler directly
# (no Xcode project needed) and assembles + ad-hoc-signs a runnable .app bundle.
# Public source builds do not bundle yt-dlp or ffmpeg; install them separately
# with Homebrew. Optional local binaries in Resources/ are copied if present.
#
# Requires full Xcode (SwiftUI uses compiler macros whose plugin ships only
# inside Xcode.app). After installing Xcode:
#     sudo xcode-select --switch /Applications/Xcode.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build-app"
DIST="$ROOT/dist"
APP="$DIST/Offloadly.app"

# --- 0. Toolchain check ---------------------------------------------------
DEVDIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVDIR" == *"CommandLineTools"* || -z "$DEVDIR" ]]; then
  echo "ERROR: Full Xcode is required to build the SwiftUI UI."
  echo "       Current developer dir: ${DEVDIR:-none}"
  echo
  echo "Install Xcode from the App Store, then run:"
  echo "    sudo xcode-select --switch /Applications/Xcode.app"
  echo "(use /Applications/Xcode-beta.app for the beta) and re-run this script."
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14"
echo "Using developer dir: $DEVDIR"
echo "Using SDK:           $SDK"

# --- 1. Compile -----------------------------------------------------------
mkdir -p "$BUILD"
echo "Compiling Swift sources…"
# Collect sources null-delimited so paths containing spaces survive.
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done \
  < <(find "$ROOT/Sources" -name '*.swift' -print0)
xcrun swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -swift-version 5 \
  "${SOURCES[@]}" \
  -o "$BUILD/Offloadly"

# --- 2. Assemble the .app bundle -----------------------------------------
echo "Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD/Offloadly"        "$APP/Contents/MacOS/Offloadly"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Optional local binaries. The public repo intentionally does not include these;
# BinaryLocator falls back to Homebrew/system copies at runtime.
for bin in yt-dlp ffmpeg; do
  if [[ -f "$ROOT/Resources/$bin" ]]; then
    cp "$ROOT/Resources/$bin" "$APP/Contents/Resources/$bin"
    chmod +x "$APP/Contents/Resources/$bin"
  else
    echo "WARNING: Resources/$bin not found — the app will fall back to a"
    echo "         system $bin on PATH if one exists."
  fi
done

# --- 3. Ad-hoc sign (required to run on Apple Silicon) --------------------
echo "Ad-hoc signing…"
for bin in yt-dlp ffmpeg; do
  [[ -f "$APP/Contents/Resources/$bin" ]] && \
    codesign --force --sign - "$APP/Contents/Resources/$bin"
done
codesign --force --sign - "$APP/Contents/MacOS/Offloadly"
codesign --force --sign - "$APP"

echo
echo "Built: $APP"
echo "Run:   open \"$APP\""
