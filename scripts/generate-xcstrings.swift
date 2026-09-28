#!/usr/bin/env swift
import Foundation

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let translationsDir = projectDir.appendingPathComponent("Translations")
let outputPath = projectDir.appendingPathComponent("ClaudeMonitor/Generated/Translations/Localizable.xcstrings")
let lprojDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

/// `.plural` maps CLDR plural categories to text and is the key's entire value: no literal text can surround it.
enum LocalizedValue {
    case plain(String)
    case plural([String: String])
}

/// Malformed input must fail the whole run: a silently skipped key ships untranslated with no signal.
struct LocalizationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func loadJSON(_ url: URL) throws -> [String: LocalizedValue] {
    guard let data = try? Data(contentsOf: url) else {
        throw LocalizationError(message: "\(url.lastPathComponent): could not read file")
    }
    guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw LocalizationError(message: "\(url.lastPathComponent): not a valid JSON object of {key: value}")
    }
    var result: [String: LocalizedValue] = [:]
    for (key, value) in dict {
        if let s = value as? String {
            result[key] = .plain(s)
        } else if let categories = value as? [String: String] {
            guard !categories.isEmpty else {
                throw LocalizationError(message: "\(url.lastPathComponent): key \"\(key)\" is a plural object with no categories")
            }
            guard categories["other"] != nil else {
                throw LocalizationError(message: "\(url.lastPathComponent): key \"\(key)\" is a plural object missing the required \"other\" category")
            }
            result[key] = .plural(categories)
        } else {
            throw LocalizationError(message: "\(url.lastPathComponent): key \"\(key)\" has an unsupported value (expected a string, or a {category: string} plural object): \(value)")
        }
    }
    return result
}

// An absent _comments.json is a supported state; a present but broken one must fail, not silently drop comments.
func loadComments(_ url: URL) throws -> [String: String] {
    guard fm.fileExists(atPath: url.path) else { return [:] }
    guard let data = try? Data(contentsOf: url) else {
        throw LocalizationError(message: "\(url.lastPathComponent): could not read file")
    }
    guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        throw LocalizationError(message: "\(url.lastPathComponent): not a valid JSON object of {key: string}")
    }
    return dict
}

do {
    let comments = try loadComments(translationsDir.appendingPathComponent("_comments.json"))

    var languages: [String: [String: LocalizedValue]] = [:]
    for file in try fm.contentsOfDirectory(at: translationsDir, includingPropertiesForKeys: nil) {
        let name = file.lastPathComponent
        guard name.hasSuffix(".json"), !name.hasPrefix("_") else { continue }
        let dict = try loadJSON(file)
        guard !dict.isEmpty else { continue }
        languages[file.deletingPathExtension().lastPathComponent] = dict
    }

    guard !languages.isEmpty else {
        fputs("Error: no language files in Translations/\n", stderr)
        exit(1)
    }

    let allKeys = Set(languages.values.flatMap(\.keys)).sorted()

    var strings: [String: Any] = [
        "_GENERATED": [
            "comment": "DO NOT READ OR EDIT THIS FILE. Generated from Translations/*.json by scripts/generate-xcstrings.swift. To add or change translations, edit the JSON source files and run the generate script.",
        ] as [String: Any],
    ]
    for key in allKeys {
        var entry: [String: Any] = [:]
        if let c = comments[key] { entry["comment"] = c }
        var locs: [String: Any] = [:]
        for (lang, values) in languages {
            guard let value = values[key] else { continue }
            switch value {
            case .plain(let s):
                locs[lang] = ["stringUnit": ["state": "translated", "value": s]]
            case .plural(let categories):
                var pluralVariations: [String: Any] = [:]
                for (category, text) in categories {
                    pluralVariations[category] = ["stringUnit": ["state": "translated", "value": text]]
                }
                locs[lang] = ["variations": ["plural": pluralVariations]]
            }
        }
        if !locs.isEmpty { entry["localizations"] = locs }
        strings[key] = entry
    }

    var data = try JSONSerialization.data(
        withJSONObject: ["sourceLanguage": "en", "strings": strings, "version": "1.0"] as [String: Any],
        options: [.prettyPrinted, .sortedKeys]
    )
    data.append(contentsOf: "\n".utf8)
    try fm.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outputPath)
    print("Generated xcstrings: \(allKeys.count) keys × \(languages.count) languages")

    // Foundation can't read .xcstrings without Xcode compilation, so CLI builds get .lproj/.strings (+ .stringsdict for plurals).
    if let lprojDir {
        for (lang, values) in languages.sorted(by: { $0.key < $1.key }) {
            let dir = "\(lprojDir)/\(lang).lproj"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

            var stringsOut = ""
            var stringsdictPlist: [String: Any] = [:]
            for key in allKeys {
                guard let value = values[key] else { continue }
                switch value {
                case .plain(let s):
                    let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    stringsOut += "\"\(key)\" = \"\(escaped)\";\n"
                case .plural(let categories):
                    var variable: [String: String] = [
                        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                        "NSStringFormatValueTypeKey": "ld",
                    ]
                    for (category, text) in categories { variable[category] = text }
                    stringsdictPlist[key] = [
                        "NSStringLocalizedFormatKey": "%#@value@",
                        "value": variable,
                    ]
                }
            }
            try stringsOut.write(toFile: "\(dir)/Localizable.strings", atomically: true, encoding: .utf8)

            if !stringsdictPlist.isEmpty {
                let plistData = try PropertyListSerialization.data(fromPropertyList: stringsdictPlist, format: .xml, options: 0)
                try plistData.write(to: URL(fileURLWithPath: "\(dir)/Localizable.stringsdict"))
            }
        }
        print("Generated .strings for \(languages.count) languages")
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
