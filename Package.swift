// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Marknord",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Marknord", targets: ["Marknord"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MarknordCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Marknord",
            dependencies: ["MarknordCore"]
        ),
        .testTarget(
            name: "MarknordCoreTests",
            dependencies: ["MarknordCore"]
        ),
    ]
)
