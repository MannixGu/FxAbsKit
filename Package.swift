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
            url: "https://github.com/MannixGu/FxAbsKit/releases/download/1.0.0/abs.xcframework_1.0.0.zip",
            checksum: "173d3c9737a2266bfa3584ffa20147b01e8d0cf83a0c35f5ebecfb45668cdf86"
        ),
    ]
)
