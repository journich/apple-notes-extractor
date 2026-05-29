// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "notes2myicor",
    products: [
        .executable(name: "notes2myicor", targets: ["notes2myicor"]),
        .library(name: "Notes2MyICORCore", targets: ["Notes2MyICORCore"]),
    ],
    targets: [
        .target(
            name: "Notes2MyICORCore"
        ),
        .executableTarget(
            name: "notes2myicor",
            dependencies: ["Notes2MyICORCore"]
        ),
        .testTarget(
            name: "Notes2MyICORCoreTests",
            dependencies: ["Notes2MyICORCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
