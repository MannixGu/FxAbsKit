// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FxAbsKit",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "abs",
            targets: ["abs"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .binaryTarget(
            name: "abs",
            url: "https://github.com/MannixGu/FxAbsKit/releases/download/1.1.1/abs.xcframework_1.1.1.zip",
            checksum: "10c140cceb0d696200fe1ec245ab8853ddf5b2c486efb5bfa5ab5715236259fe"
        ),
    ]
)
