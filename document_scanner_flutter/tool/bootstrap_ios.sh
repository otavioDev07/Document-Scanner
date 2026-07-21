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

rm -rf "$DESTINATION/opencv2.xcframework"
unzip -q -o "$ARCHIVE" \
  'opencv/ios/opencv2.xcframework/Info.plist' \
  'opencv/ios/opencv2.xcframework/ios-arm64/*' \
  'opencv/ios/opencv2.xcframework/ios-arm64_x86_64-simulator/*' \
  -d "$DESTINATION/.extracting"
mv "$DESTINATION/.extracting/opencv/ios/opencv2.xcframework" "$DESTINATION/opencv2.xcframework"
rm -rf "$DESTINATION/.extracting"

echo "OpenCV ready at $DESTINATION/opencv2.xcframework"
