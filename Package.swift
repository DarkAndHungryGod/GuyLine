// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GuyLine",
    platforms: [
        // macOS 14 for SwiftUI's `newDocument` action ("New from Example").
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuantityKernel", targets: ["QuantityKernel"]),
        .library(name: "GraphEngine", targets: ["GraphEngine"]),
        .executable(name: "GuyLineApp", targets: ["GuyLineApp"])
    ],
    dependencies: [
        // Pointed at our fork's branch for the extensible-Quantity work (the `Money`
        // dimension). Switch back to a tagged upstream release once the PR merges:
        //   .package(url: "https://github.com/NeedleInAJayStack/Units.git", from: "1.2.0")
        .package(
            url: "https://github.com/DarkAndHungryGod/Units.git",
            branch: "feat/extensible-quantity"
        )
    ],
    targets: [
        .target(
            name: "QuantityKernel",
            dependencies: [
                .product(name: "Units", package: "Units")
            ]
        ),
        .testTarget(
            name: "QuantityKernelTests",
            dependencies: ["QuantityKernel"]
        ),
        .target(
            name: "GraphEngine",
            dependencies: ["QuantityKernel"],
            resources: [.copy("Examples")]
        ),
        .testTarget(
            name: "GraphEngineTests",
            dependencies: ["GraphEngine", "QuantityKernel"]
        ),
        .executableTarget(
            name: "GuyLineApp",
            dependencies: ["GraphEngine", "QuantityKernel"],
            // SwiftUI's document APIs (`ReferenceFileDocument`, `newDocument`) aren't
            // yet fully Sendable-annotated for Swift 6 strict concurrency; the app
            // target builds in Swift 5 mode while the engine stays in Swift 6.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
