#!/usr/bin/env swift
import Foundation

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let translationsDir = projectDir.appendingPathComponent("Translations")
let outputPath = projectDir.appendingPathComponent("ClaudeMonitor/Localizable.xcstrings")
let lprojDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

func loadJSON(_ url: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: url),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else { return [:] }
    return dict
}

do {
    let comments = loadJSON(translationsDir.appendingPathComponent("_comments.json"))

    var languages: [String: [String: String]] = [:]
    for file in try fm.contentsOfDirectory(at: translationsDir, includingPropertiesForKeys: nil) {
        let name = file.lastPathComponent
        guard name.hasSuffix(".json"), !name.hasPrefix("_") else { continue }
        let dict = loadJSON(file)
        guard !dict.isEmpty else { continue }
        languages[file.deletingPathExtension().lastPathComponent] = dict
    }

    guard !languages.isEmpty else {
        fputs("Error: no language files in Translations/\n", stderr)
        exit(1)
    }

    let allKeys = Set(languages.values.flatMap(\.keys)).sorted()

    // Build xcstrings
    var strings: [String: Any] = [:]
    for key in allKeys {
        var entry: [String: Any] = [:]
        if let c = comments[key] { entry["comment"] = c }
        var locs: [String: Any] = [:]
        for (lang, s) in languages where s[key] != nil {
            locs[lang] = ["stringUnit": ["state": "translated", "value": s[key]!]]
        }
        if !locs.isEmpty { entry["localizations"] = locs }
        strings[key] = entry
    }

    var data = try JSONSerialization.data(
        withJSONObject: ["sourceLanguage": "en", "strings": strings, "version": "1.0"] as [String: Any],
        options: [.prettyPrinted, .sortedKeys]
    )
    data.append(contentsOf: "\n".utf8)
    try data.write(to: outputPath)
    print("Generated xcstrings: \(allKeys.count) keys × \(languages.count) languages")

    // Write .lproj/.strings for CLI builds
    if let lprojDir {
        for (lang, langStrings) in languages.sorted(by: { $0.key < $1.key }) {
            let dir = "\(lprojDir)/\(lang).lproj"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var out = ""
            for key in allKeys {
                guard let value = langStrings[key] else { continue }
                let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                out += "\"\(key)\" = \"\(escaped)\";\n"
            }
            try out.write(toFile: "\(dir)/Localizable.strings", atomically: true, encoding: .utf8)
        }
        print("Generated .strings for \(languages.count) languages")
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
