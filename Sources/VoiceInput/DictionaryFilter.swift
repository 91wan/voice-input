import Foundation
import os.log

private let logger = Logger(subsystem: "app.voiceinput.VoiceInput", category: "DictionaryFilter")

extension Notification.Name {
    static let dictionaryFilterActivityDidChange = Notification.Name("DictionaryFilterActivityDidChange")
}

struct DictionaryRuleIssue: Equatable {
    enum Severity {
        case warning
        case error
    }

    let severity: Severity
    let lineNumber: Int
    let message: String

    var displayText: String {
        "第 \(lineNumber) 行：\(message)"
    }
}

struct DictionaryParseResult: Equatable {
    let dictionary: [String: String]
    let issues: [DictionaryRuleIssue]

    var errors: [DictionaryRuleIssue] {
        issues.filter { $0.severity == .error }
    }

    var warnings: [DictionaryRuleIssue] {
        issues.filter { $0.severity == .warning }
    }

    var canSave: Bool {
        errors.isEmpty
    }

    func summary(limit: Int = 3) -> String {
        guard !issues.isEmpty else { return "规则格式正确" }

        let visibleIssues = issues.prefix(limit).map(\.displayText)
        var text = visibleIssues.joined(separator: "；")
        if issues.count > limit {
            text += "；另外还有 \(issues.count - limit) 条"
        }
        return text
    }
}

struct DictionaryMatch: Equatable {
    let source: String
    let replacement: String
    let count: Int

    var displayText: String {
        if count > 1 {
            return "\(source) → \(replacement) (\(count)x)"
        }
        return "\(source) → \(replacement)"
    }
}

struct DictionaryApplyResult: Equatable {
    let text: String
    let matches: [DictionaryMatch]

    var didChange: Bool {
        !matches.isEmpty
    }
}

enum DictionaryLoadResult: Equatable {
    case missing
    case success(entryCount: Int)
    case failure(String)
}

final class DictionaryFilter {
    static let shared = DictionaryFilter()

    private static let defaultBuiltinMap: [String: String] = [
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

    private let builtinMap: [String: String]
    private let notificationCenter: NotificationCenter
    private let dictionaryURLProvider: () -> URL

    private(set) var userMap: [String: String]
    private(set) var lastLoadIssue: String?
    private(set) var lastActivitySummary = "Dictionary: 暂无最近一次命中"

    init(
        builtinMap: [String: String] = DictionaryFilter.defaultBuiltinMap,
        userMap: [String: String] = [:],
        notificationCenter: NotificationCenter = .default,
        dictionaryURLProvider: @escaping () -> URL = DictionaryFilter.defaultDictionaryURL
    ) {
        self.builtinMap = builtinMap
        self.userMap = userMap
        self.notificationCenter = notificationCenter
        self.dictionaryURLProvider = dictionaryURLProvider
    }

    private var dictionaryURL: URL {
        dictionaryURLProvider()
    }

    private static func defaultDictionaryURL() -> URL {
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return applicationSupportURL
            .appendingPathComponent("VoiceInput/dictionary.json")
    }

    func apply(_ text: String) -> String {
        applying(text).text
    }

    func applying(_ text: String) -> DictionaryApplyResult {
        var resultText = text
        var matches: [DictionaryMatch] = []

        for (wrong, right) in orderedRules() {
            let count = matchCount(of: wrong, in: resultText)
            guard count > 0 else { continue }

            resultText = resultText.replacingOccurrences(of: wrong, with: right, options: [.caseInsensitive])
            matches.append(DictionaryMatch(source: wrong, replacement: right, count: count))
        }

        let result = DictionaryApplyResult(text: resultText, matches: matches)
        updateLastActivity(for: result, originalText: text)

        if result.didChange {
            logger.debug("Dictionary matched \(matches.count) rule(s): \(self.lastActivitySummary, privacy: .public)")
        }

        return result
    }

    @discardableResult
    func loadUserDictionary() -> DictionaryLoadResult {
        let url = dictionaryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            userMap = [:]
            lastLoadIssue = nil
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            let dict = try JSONDecoder().decode([String: String].self, from: data)
            let parseResult = Self.validateLoadedDictionary(dict)
            guard parseResult.canSave else {
                userMap = [:]
                let message = "读取 dictionary.json 失败：\(parseResult.summary())"
                lastLoadIssue = message
                logger.error("Dictionary load failed: \(message, privacy: .public)")
                return .failure(message)
            }

            userMap = parseResult.dictionary
            lastLoadIssue = nil
            logger.info("Loaded \(parseResult.dictionary.count) user dictionary entries")
            return .success(entryCount: parseResult.dictionary.count)
        } catch {
            userMap = [:]
            let message = "读取 dictionary.json 失败：\(error.localizedDescription)"
            lastLoadIssue = message
            logger.error("Dictionary load failed: \(message, privacy: .public)")
            return .failure(message)
        }
    }

    func saveUserDictionary(_ dict: [String: String]) throws {
        let url = dictionaryURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dict)
        try data.write(to: url, options: .atomic)
        userMap = dict
        lastLoadIssue = nil
        logger.info("Saved \(dict.count) user dictionary entries")
    }

    static func parse(_ text: String) -> DictionaryParseResult {
        var dict: [String: String] = [:]
        var issues: [DictionaryRuleIssue] = []
        var previousEntries: [String: (originalKey: String, value: String, lineNumber: Int)] = [:]

        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            guard let separatorRange = firstSeparatorRange(in: trimmed) else {
                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: "缺少分隔符，请使用 → 或 ->"
                ))
                continue
            }

            let key = String(trimmed[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            guard !key.isEmpty else {
                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: "左侧错误词不能为空"
                ))
                continue
            }

            guard !value.isEmpty else {
                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: "右侧正确词不能为空"
                ))
                continue
            }

            let normalizedKey = normalizeKey(key)
            if let previous = previousEntries[normalizedKey] {
                dict.removeValue(forKey: previous.originalKey)

                let message: String
                if previous.value == value {
                    message = "与第 \(previous.lineNumber) 行重复，保留最后一条"
                } else {
                    message = "与第 \(previous.lineNumber) 行冲突，将覆盖 “\(previous.originalKey) → \(previous.value)”"
                }

                issues.append(DictionaryRuleIssue(
                    severity: .warning,
                    lineNumber: lineNumber,
                    message: message
                ))
            }

            dict[key] = value
            previousEntries[normalizedKey] = (originalKey: key, value: value, lineNumber: lineNumber)
        }

        return DictionaryParseResult(dictionary: dict, issues: issues)
    }

    static func parseText(_ text: String) -> [String: String] {
        parse(text).dictionary
    }

    static func serializeToText(_ dict: [String: String]) -> String {
        dict.sorted { $0.key < $1.key }.map { "\($0.key) → \($0.value)" }.joined(separator: "\n")
    }

    private static func validateLoadedDictionary(_ dict: [String: String]) -> DictionaryParseResult {
        var sanitized: [String: String] = [:]
        var issues: [DictionaryRuleIssue] = []
        var previousEntries: [String: (originalKey: String, value: String, lineNumber: Int)] = [:]

        for (index, entry) in sortedEntries(dict).enumerated() {
            let lineNumber = index + 1
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty else {
                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: "左侧错误词不能为空"
                ))
                continue
            }

            guard !value.isEmpty else {
                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: "右侧正确词不能为空"
                ))
                continue
            }

            let normalizedKey = normalizeKey(key)
            if let previous = previousEntries[normalizedKey] {
                let message: String
                if previous.value == value {
                    message = "与第 \(previous.lineNumber) 行重复，请只保留一条"
                } else {
                    message = "与第 \(previous.lineNumber) 行冲突，请只保留 “\(previous.originalKey)” 或 “\(key)”"
                }

                issues.append(DictionaryRuleIssue(
                    severity: .error,
                    lineNumber: lineNumber,
                    message: message
                ))
                continue
            }

            sanitized[key] = value
            previousEntries[normalizedKey] = (originalKey: key, value: value, lineNumber: lineNumber)
        }

        return DictionaryParseResult(dictionary: sanitized, issues: issues)
    }

    private func orderedRules() -> [(key: String, value: String)] {
        var merged: [String: (key: String, value: String)] = [:]
        for (key, value) in builtinMap {
            merged[Self.normalizeKey(key)] = (key: key, value: value)
        }
        for (key, value) in userMap {
            merged[Self.normalizeKey(key)] = (key: key, value: value)
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.key.count != rhs.key.count {
                return lhs.key.count > rhs.key.count
            }
            let comparison = lhs.key.localizedCaseInsensitiveCompare(rhs.key)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.key < rhs.key
        }.map { (key: $0.key, value: $0.value) }
    }

    private func matchCount(of search: String, in text: String) -> Int {
        guard !search.isEmpty else { return 0 }
        let pattern = NSRegularExpression.escapedPattern(for: search)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func updateLastActivity(for result: DictionaryApplyResult, originalText: String) {
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if result.matches.isEmpty {
            lastActivitySummary = "Dictionary: 上一次输入未命中规则"
        } else if result.matches.count == 1, let match = result.matches.first {
            lastActivitySummary = "Dictionary: 命中 \(match.displayText)"
        } else if let firstMatch = result.matches.first {
            lastActivitySummary = "Dictionary: 命中 \(result.matches.count) 条规则（\(firstMatch.displayText) 等）"
        }

        notificationCenter.post(name: .dictionaryFilterActivityDidChange, object: self)
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func sortedEntries(_ dict: [String: String]) -> [(key: String, value: String)] {
        dict.sorted { lhs, rhs in
            let comparison = lhs.key.localizedCaseInsensitiveCompare(rhs.key)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.key < rhs.key
        }
    }

    private static func firstSeparatorRange(in line: String) -> Range<String.Index>? {
        let separators = ["→", "->"]
        return separators
            .compactMap { separator in line.range(of: separator).map { ($0, $0.lowerBound) } }
            .min { $0.1 < $1.1 }?
            .0
    }
}
