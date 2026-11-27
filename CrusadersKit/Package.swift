// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CrusadersKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CrusadersKit", targets: ["CrusadersKit"])
    ],
    targets: [
        .target(name: "CrusadersKit", resources: [.process("Resources")]),
        .testTarget(name: "CrusadersKitTests", dependencies: ["CrusadersKit"])
    ]
)
