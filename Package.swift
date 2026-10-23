// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TableGarden",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TableGarden", targets: ["TableGarden"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "GardenCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "TableGarden", dependencies: ["GardenCore"], resources: [.copy("Resources")]),
        .testTarget(name: "GardenCoreTests", dependencies: ["GardenCore", "CSQLite"])
    ],
    swiftLanguageModes: [.v5]
)
