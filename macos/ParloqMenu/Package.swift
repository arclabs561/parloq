// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParloqMenu",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ParloqMenuCore", targets: ["ParloqMenuCore"]),
        .executable(name: "ParloqMenu", targets: ["ParloqMenu"]),
    ],
    targets: [
        .systemLibrary(name: "CIOKitHID"),
        .target(name: "ParloqMenuCore"),
        .executableTarget(
            name: "ParloqMenu",
            dependencies: ["CIOKitHID", "ParloqMenuCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "ParloqMenuCoreTests",
            dependencies: ["ParloqMenuCore"]
        ),
    ]
)
