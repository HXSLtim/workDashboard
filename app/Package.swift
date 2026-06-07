// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "NotchApp",
            dependencies: [
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit")
            ]
        )
    ]
)
