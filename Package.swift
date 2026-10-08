// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Jullia",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Jullia", targets: ["Jullia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(
            name: "JulliaCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Jullia",
            dependencies: ["JulliaCore"]
        ),
        .testTarget(
            name: "JulliaCoreTests",
            dependencies: ["JulliaCore"]
        ),
        .testTarget(
            name: "JulliaAppTests",
            dependencies: ["Jullia"]
        ),
    ]
)
