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
                "ClaudeMonitor.entitlements",
            ],
            resources: [
                .process("Localizable.xcstrings"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
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
