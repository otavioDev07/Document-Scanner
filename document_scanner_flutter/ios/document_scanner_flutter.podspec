#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint document_scanner_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'document_scanner_flutter'
  s.version          = '0.2.0'
  s.summary          = 'Reusable Flutter document detection and perspective crop plugin.'
  s.description      = <<-DESC
Flutter document scanner with a native image-processing pipeline.
                       DESC
  s.homepage         = 'https://github.com/otavioDev07/Document-Scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Document Scanner contributors' => 'opensource@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files = [
    'document_scanner_flutter/Sources/document_scanner_flutter/**/*.{swift}',
    '../native/DocumentDetector.cpp',
    '../native/apple/NativeDocumentProcessor.mm',
    '../native/include/*.{h,hpp}',
    '../native/internal/*.{h,hpp}'
  ]
  s.public_header_files = '../native/include/NativeDocumentProcessor.h'
  s.private_header_files = '../native/internal/DocumentDetector.h'
  s.vendored_frameworks = '../native/Frameworks/opencv2.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation', 'CoreMedia', 'CoreVideo', 'Foundation', 'UIKit'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../native/internal"'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'document_scanner_flutter_privacy' => ['document_scanner_flutter/Sources/document_scanner_flutter/PrivacyInfo.xcprivacy']}
end
