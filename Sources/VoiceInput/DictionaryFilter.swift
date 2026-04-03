import Foundation
import os.log

private let logger = Logger(subsystem: "app.voiceinput.VoiceInput", category: "DictionaryFilter")

final class DictionaryFilter {
    static let shared = DictionaryFilter()

    private let builtinMap: [String: String] = [
        "open claw": "OpenClaw",
        "example app": "ExampleApp",
        "example app": "ExampleApp",
        "example app": "ExampleApp",
        "type script": "TypeScript",
        "java script": "JavaScript",
        "data base": "database",
        "杰森": "JSON",
        "配森": "Python",
        "派森": "Python",
        "迪克耳": "Docker",
        "库伯内坦斯": "Kubernetes",
        "拉姆达": "Lambda",
    ]

    private(set) var userMap: [String: String] = [:]

    private var dictionaryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("VoiceInput/dictionary.json")
    }

    func apply(_ text: String) -> String {
        var result = text
        let merged = builtinMap.merging(userMap) { _, user in user }
        for (wrong, right) in merged {
            result = result.replacingOccurrences(of: wrong, with: right, options: [.caseInsensitive])
        }
        if result != text {
            logger.debug("Dictionary: '\(text)' -> '\(result)'")
        }
        return result
    }

    func loadUserDictionary() {
        let url = dictionaryURL
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        userMap = dict
        logger.info("Loaded \(dict.count) user dictionary entries")
    }

    func saveUserDictionary(_ dict: [String: String]) throws {
        let url = dictionaryURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(dict)
        try data.write(to: url)
        userMap = dict
        logger.info("Saved \(dict.count) user dictionary entries")
    }

    static func parseText(_ text: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            for sep in ["→", "->"] {
                if let range = trimmed.range(of: sep) {
                    let key = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !key.isEmpty && !value.isEmpty {
                        dict[key] = value
                        break
                    }
                }
            }
        }
        return dict
    }

    static func serializeToText(_ dict: [String: String]) -> String {
        dict.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: "\n")
    }
}
