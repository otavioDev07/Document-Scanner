# OpenCV Apple artifact

`opencv2.xcframework` is generated and intentionally excluded from Git because
it is a third-party binary. Run `../../tool/bootstrap_ios.sh` from the Flutter
plugin root before the first iOS build. The script downloads the same
`dev_resources/ios.zip` artifact used by the legacy CI and extracts only the
iOS device and simulator slices.
