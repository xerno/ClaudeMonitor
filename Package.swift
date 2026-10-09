// swift-tools-version: 6.2
import Foundation
import PackageDescription

// From the active toolchain so the Testing framework matches the compiler (SDK mismatch on CI runners).
let developerDirectory: String? = {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    task.arguments = ["-p"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0,
          let devDir = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !devDir.isEmpty else { return nil }
    return devDir
}()

let testingLibraryPaths: (frameworks: String, interop: String) = {
    if let developerDirectory {
        let xcodeDeveloper = developerDirectory + "/Platforms/MacOSX.platform/Developer"
        if FileManager.default.fileExists(atPath: xcodeDeveloper + "/Library/Frameworks") {
            return (xcodeDeveloper + "/Library/Frameworks", xcodeDeveloper + "/usr/lib")
        }
        let cltDeveloper = developerDirectory + "/Library/Developer"
        if FileManager.default.fileExists(atPath: cltDeveloper + "/Frameworks") {
            return (cltDeveloper + "/Frameworks", cltDeveloper + "/usr/lib")
        }
    }
    let fallbackDeveloper = "/Library/Developer/CommandLineTools/Library/Developer"
    return (fallbackDeveloper + "/Frameworks", fallbackDeveloper + "/usr/lib")
}()

let testingMacrosPluginFlags: [String] = {
    let pluginDirectory = (developerDirectory ?? "/Library/Developer/CommandLineTools")
        + "/usr/lib/swift/host/plugins/testing"
    guard FileManager.default.fileExists(atPath: pluginDirectory) else { return [] }
    return ["-plugin-path", pluginDirectory]
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
                "Generated/Translations/Localizable.xcstrings",
            ],
            resources: [
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
                    "-F", testingLibraryPaths.frameworks,
                    "-Xfrontend", "-disable-cross-import-overlays",
                ] + testingMacrosPluginFlags),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingLibraryPaths.frameworks,
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingLibraryPaths.frameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingLibraryPaths.interop,
                ]),
            ]
        ),
    ]
)
