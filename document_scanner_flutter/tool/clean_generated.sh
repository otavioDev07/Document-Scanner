#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"

cd "$project_dir"
"$flutter_bin" clean
cd "$project_dir/example"
"$flutter_bin" clean

# These are reproducible caches not always removed by `flutter clean`.
rm -rf \
  "$project_dir/.dart_tool" \
  "$project_dir/android/.cxx" \
  "$project_dir/android/.gradle" \
  "$project_dir/native/.build" \
  "$project_dir/example/.dart_tool" \
  "$project_dir/example/android/.gradle"

echo "Generated Flutter, Gradle, CMake and SwiftPM artifacts were removed."
