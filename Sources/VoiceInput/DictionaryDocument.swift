import Foundation

struct DictionaryDocumentImportResult: Equatable {
    let dictionary: [String: String]
    let rulesText: String
    let warnings: [DictionaryRuleIssue]
}

struct DictionaryDocumentExportResult: Equatable {
    let rulesText: String
    let warnings: [DictionaryRuleIssue]
}

enum DictionaryDocumentError: LocalizedError, Equatable {
    case invalidRules(String)

    var errorDescription: String? {
        switch self {
        case .invalidRules(let summary):
            return "字典规则无效：\(summary)"
        }
    }
}

enum DictionaryDocument {
    static func importText(_ text: String) throws -> DictionaryDocumentImportResult {
        let parseResult = DictionaryFilter.parse(text)
        guard parseResult.canSave else {
            throw DictionaryDocumentError.invalidRules(parseResult.summary())
        }

        return DictionaryDocumentImportResult(
            dictionary: parseResult.dictionary,
            rulesText: DictionaryFilter.serializeToText(parseResult.dictionary),
            warnings: parseResult.warnings
        )
    }

    static func exportText(_ rulesText: String) throws -> String {
        try export(rulesText).rulesText
    }

    static func export(_ rulesText: String) throws -> DictionaryDocumentExportResult {
        let parseResult = DictionaryFilter.parse(rulesText)
        guard parseResult.canSave else {
            throw DictionaryDocumentError.invalidRules(parseResult.summary())
        }

        return DictionaryDocumentExportResult(
            rulesText: DictionaryFilter.serializeToText(parseResult.dictionary),
            warnings: parseResult.warnings
        )
    }
}
