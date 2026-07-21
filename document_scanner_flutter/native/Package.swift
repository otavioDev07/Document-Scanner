// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DocumentScannerNative",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "DocumentScannerNative", targets: ["DocumentScannerNative"])
    ],
    targets: [
        .binaryTarget(
            name: "opencv2",
            path: "Frameworks/opencv2.xcframework"
        ),
        .target(
            name: "DocumentScannerNative",
            dependencies: ["opencv2"],
            path: ".",
            exclude: ["Frameworks", "Package.swift"],
            sources: ["DocumentDetector.cpp", "apple/NativeDocumentProcessor.mm"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("internal")
            ],
            linkerSettings: [
                .linkedFramework("CoreVideo"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit")
            ]
        )
    ],
    cxxLanguageStandard: .cxx20
)
