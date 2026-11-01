// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "apple-reminders-mcp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "RemindersCore"),
        .executableTarget(name: "reminders-bridge", dependencies: ["RemindersCore"]),
        .executableTarget(
            name: "apple-reminders-mcp",
            dependencies: ["RemindersCore", .product(name: "MCP", package: "swift-sdk")],
            exclude: ["Info.plist"],
            // Embeds Info.plist in the binary: its name and Reminders usage
            // reason are what macOS shows when asking for access, with no
            // app bundle needed.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", Context.packageDirectory + "/Sources/apple-reminders-mcp/Info.plist",
            ])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
