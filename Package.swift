// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftApiAdapter",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SwiftApiAdapter",
            targets: ["SwiftApiAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup", .upToNextMajor(from: "2.7.2")),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", .upToNextMajor(from: "5.0.2"))
    ],
    targets: [
        .target(
            name: "SwiftApiAdapter",
            dependencies: ["SwiftSoup","SwiftyJSON"]
        ),
        .testTarget(
            name: "SwiftApiAdapterTests",
            dependencies: ["SwiftApiAdapter"]),
    ]
)
