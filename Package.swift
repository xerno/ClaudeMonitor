// swift-tools-version: 6.2
import Foundation
import PackageDescription

// From the active toolchain so the Testing framework matches the compiler (SDK mismatch on CI runners).
let testingFrameworkPath: String = {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    task.arguments = ["-p"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    if task.terminationStatus == 0,
       let devDir = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !devDir.isEmpty {
        let xcodeFrameworks = devDir + "/Platforms/MacOSX.platform/Developer/Library/Frameworks"
        if FileManager.default.fileExists(atPath: xcodeFrameworks) { return xcodeFrameworks }
        let cltFrameworks = devDir + "/Library/Developer/Frameworks"
        if FileManager.default.fileExists(atPath: cltFrameworks) { return cltFrameworks }
    }
    return "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
}()

// Keep in sync with scripts/build-config.sh.
let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility"),
]

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
                .process("Generated/Translations/Localizable.xcstrings"),
                .process("Resources/DemoSamples.json"),
            ],
            swiftSettings: commonSwiftSettings + [
                // Lets the TestRunner target use @testable import.
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        // Calls Testing.__swiftPMEntryPoint() directly: swift test's bundle-based runner doesn't work on macOS 26 beta.
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
            swiftSettings: commonSwiftSettings + [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingFrameworkPath,
                ]),
            ]
        ),
    ]
)
