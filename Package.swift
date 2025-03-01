// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "FSCheckoutSheet",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "FSCheckoutSheet", targets: ["FSCheckoutSheet"])
    ],
    targets: [
        .target(name: "FSCheckoutSheet")
    ]
)
