#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="$ROOT/native/Frameworks"
ARCHIVE="${TMPDIR:-/tmp}/oss-document-scanner-ios.zip"
URL="https://github.com/ossappscollective/OSS-DocumentScanner/releases/download/dev_resources/ios.zip"
EXPECTED_SHA256="980a041077a8fcb44ef98e0f3a9710fe029e4458ebdbedb0d3d3b598129a651f"

mkdir -p "$DESTINATION"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -L "$URL" -o "$ARCHIVE"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Unexpected ios.zip checksum: $ACTUAL_SHA256" >&2
  exit 1
fi

rm -rf "$DESTINATION/opencv2.xcframework" "$DESTINATION/.extracting" "$DESTINATION/.shallow"
unzip -q -o "$ARCHIVE" \
  'opencv/ios/opencv2.xcframework/Info.plist' \
  'opencv/ios/opencv2.xcframework/ios-arm64/*' \
  'opencv/ios/opencv2.xcframework/ios-arm64_x86_64-simulator/*' \
  -d "$DESTINATION/.extracting"

# OpenCV distributes versioned (macOS-style) framework bundles for every Apple
# platform. Xcode 26 requires shallow bundles on iOS, so rebuild the two slices
# before handing the artifact to Swift Package Manager.
for SLICE in ios-arm64 ios-arm64_x86_64-simulator; do
  SOURCE="$DESTINATION/.extracting/opencv/ios/opencv2.xcframework/$SLICE/opencv2.framework/Versions/A"
  TARGET="$DESTINATION/.shallow/$SLICE/opencv2.framework"
  mkdir -p "$TARGET"
  cp "$SOURCE/opencv2" "$TARGET/opencv2"
  cp "$SOURCE/Resources/Info.plist" "$TARGET/Info.plist"
  cp -R "$SOURCE/Headers" "$TARGET/Headers"
  # The upstream framework plist omits CFBundleExecutable. Xcode can link the
  # static archive without it, but physical-device installation rejects any
  # copied framework bundle whose executable is not declared.
  /usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string opencv2' \
    "$TARGET/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable opencv2' \
      "$TARGET/Info.plist"
done

xcodebuild -create-xcframework \
  -framework "$DESTINATION/.shallow/ios-arm64/opencv2.framework" \
  -framework "$DESTINATION/.shallow/ios-arm64_x86_64-simulator/opencv2.framework" \
  -output "$DESTINATION/opencv2.xcframework"
rm -rf "$DESTINATION/.extracting" "$DESTINATION/.shallow"

echo "OpenCV ready at $DESTINATION/opencv2.xcframework"
