// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeMonitor",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "ClaudeMonitor",
            path: "ClaudeMonitor",
            exclude: [
                "AppDelegate.swift",
                "Assets.xcassets",
            ],
            resources: [
                .process("Localizable.xcstrings"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("MemberImportVisibility"),
                // Enable @testable import for the TestRunner executable target.
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        // TestRunner is an executable that calls Testing.__swiftPMEntryPoint() directly.
        // On macOS 26 beta, swift test's bundle-based runner doesn't work; this bypasses it.
        .executableTarget(
            name: "ClaudeMonitorTestRunner",
            dependencies: ["ClaudeMonitor"],
            path: ".",
            exclude: [
                "build.sh",
                "CLAUDE.md",
                "ClaudeMonitor",
                "ClaudeMonitor.xcodeproj",
                "LICENSE",
                "README.md",
                "Translations",
                "docs",
                "install.sh",
                "scripts",
                "test.sh",
            ],
            sources: ["ClaudeMonitorTests", "TestRunner"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("MemberImportVisibility"),
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
