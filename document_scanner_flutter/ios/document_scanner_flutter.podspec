#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint document_scanner_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'document_scanner_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Reusable Flutter document detection and perspective crop plugin.'
  s.description      = <<-DESC
Flutter extraction of the OSS DocumentScanner native processing pipeline.
                       DESC
  s.homepage         = 'https://github.com/Akylas/OSS-DocumentScanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'OSS DocumentScanner contributors' => 'opensource@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files = 'document_scanner_flutter/Sources/document_scanner_flutter/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'document_scanner_flutter_privacy' => ['document_scanner_flutter/Sources/document_scanner_flutter/PrivacyInfo.xcprivacy']}
end
