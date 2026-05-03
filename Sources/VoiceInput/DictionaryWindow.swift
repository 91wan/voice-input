import AppKit
import UniformTypeIdentifiers

final class DictionaryWindow: NSPanel, NSTextViewDelegate, NSTextFieldDelegate {
    private let textView = NSTextView()
    private let testPhraseField = NSTextField()
    private let workbenchOutputLabel = NSTextField(labelWithString: "")
    private let workbenchMatchesLabel = NSTextField(labelWithString: "")
    private let activityLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var activityObserver: NSObjectProtocol?
    private var statusResetWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "User Dictionary"
        isReleasedWhenClosed = false
        setupUI()
        loadEntries()
        startObservingActivity()
        center()
    }

    deinit {
        if let activityObserver {
            NotificationCenter.default.removeObserver(activityObserver)
        }
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        let helpLabel = NSTextField(labelWithString: "每行一条规则，格式：错误词 → 正确词（支持 → 或 ->）\n以 # 开头的行为注释，大小写不敏感。")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = .systemFont(ofSize: 12)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.isSelectable = false
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.maximumNumberOfLines = 2
        cv.addSubview(helpLabel)

        activityLabel.translatesAutoresizingMaskIntoConstraints = false
        activityLabel.font = .systemFont(ofSize: 12)
        activityLabel.textColor = .secondaryLabelColor
        activityLabel.lineBreakMode = .byTruncatingTail
        cv.addSubview(activityLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        scrollView.documentView = textView
        cv.addSubview(scrollView)

        let workbenchBox = NSBox()
        workbenchBox.translatesAutoresizingMaskIntoConstraints = false
        workbenchBox.title = "Test Phrase"
        workbenchBox.boxType = .primary
        let workbenchContentView = NSView()
        workbenchBox.contentView = workbenchContentView
        cv.addSubview(workbenchBox)

        let workbenchStack = NSStackView()
        workbenchStack.translatesAutoresizingMaskIntoConstraints = false
        workbenchStack.orientation = .vertical
        workbenchStack.spacing = 6
        workbenchContentView.addSubview(workbenchStack)

        testPhraseField.placeholderString = "Type a phrase to preview dictionary filtering"
        testPhraseField.delegate = self
        workbenchStack.addArrangedSubview(testPhraseField)

        workbenchOutputLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        workbenchOutputLabel.lineBreakMode = .byWordWrapping
        workbenchOutputLabel.maximumNumberOfLines = 2
        workbenchStack.addArrangedSubview(workbenchOutputLabel)

        workbenchMatchesLabel.font = .systemFont(ofSize: 12)
        workbenchMatchesLabel.textColor = .secondaryLabelColor
        workbenchMatchesLabel.lineBreakMode = .byWordWrapping
        workbenchMatchesLabel.maximumNumberOfLines = 2
        workbenchStack.addArrangedSubview(workbenchMatchesLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        cv.addSubview(statusLabel)

        let importButton = NSButton(title: "Import...", target: self, action: #selector(importDictionary))
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.bezelStyle = .rounded
        cv.addSubview(importButton)

        let exportButton = NSButton(title: "Export...", target: self, action: #selector(exportDictionary))
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        exportButton.bezelStyle = .rounded
        cv.addSubview(exportButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        cv.addSubview(saveButton)

        NSLayoutConstraint.activate([
            helpLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            helpLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            helpLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),

            activityLabel.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 6),
            activityLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            activityLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: activityLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: workbenchBox.topAnchor, constant: -12),

            workbenchBox.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            workbenchBox.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            workbenchBox.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
            workbenchStack.topAnchor.constraint(equalTo: workbenchContentView.topAnchor, constant: 8),
            workbenchStack.leadingAnchor.constraint(equalTo: workbenchContentView.leadingAnchor, constant: 8),
            workbenchStack.trailingAnchor.constraint(equalTo: workbenchContentView.trailingAnchor, constant: -8),
            workbenchStack.bottomAnchor.constraint(equalTo: workbenchContentView.bottomAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: exportButton.trailingAnchor, constant: 12),
            statusLabel.topAnchor.constraint(greaterThanOrEqualTo: scrollView.bottomAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -8),

            importButton.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            importButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),

            exportButton.leadingAnchor.constraint(equalTo: importButton.trailingAnchor, constant: 8),
            exportButton.centerYAnchor.constraint(equalTo: importButton.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
        ])
    }

    private func loadEntries() {
        let dict = DictionaryFilter.shared.userMap
        if dict.isEmpty {
            textView.string = "# 示例（删除 # 后可启用规则，或直接写入你自己的规则）\n# 格式：错误识别词 → 正确词\n# type script → TypeScript\n# open claw → OpenClaw"
        } else {
            textView.string = DictionaryFilter.serializeToText(dict)
        }

        refreshActivityLabel()
        refreshWorkbench()

        if let loadIssue = DictionaryFilter.shared.lastLoadIssue {
            showStatus("当前词典未成功加载：\(loadIssue)", style: .error, autoClear: false)
        } else {
            showStatus("", style: .neutral, autoClear: false)
        }
    }

    @objc private func save() {
        let parseResult = DictionaryFilter.parse(textView.string)
        guard parseResult.canSave else {
            showStatus("未保存。\(parseResult.summary())", style: .error, autoClear: false)
            return
        }

        do {
            try DictionaryFilter.shared.saveUserDictionary(parseResult.dictionary)

            if parseResult.warnings.isEmpty {
                showStatus("已保存 \(parseResult.dictionary.count) 条规则 ✓", style: .success, autoClear: true)
            } else {
                showStatus(
                    "已保存 \(parseResult.dictionary.count) 条规则。注意：\(parseResult.summary())",
                    style: .warning,
                    autoClear: true
                )
            }
            refreshWorkbench()
        } catch {
            showStatus("保存失败：\(error.localizedDescription)", style: .error, autoClear: false)
        }
    }

    @objc private func importDictionary() {
        let panel = NSOpenPanel()
        panel.title = "Import Dictionary"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]

        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadImportedDictionary(from: url)
        }
    }

    @objc private func exportDictionary() {
        let exportResult: DictionaryDocumentExportResult
        do {
            exportResult = try DictionaryDocument.export(textView.string)
        } catch {
            showStatus("导出失败：\(error.localizedDescription)", style: .error, autoClear: false)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Dictionary"
        panel.nameFieldStringValue = "voiceinput-dictionary.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writeExportedDictionary(exportResult, to: url)
        }
    }

    func textDidChange(_ notification: Notification) {
        refreshWorkbench()
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshWorkbench()
    }

    private func refreshActivityLabel() {
        activityLabel.stringValue = DictionaryFilter.shared.lastActivitySummary
    }

    private func refreshWorkbench() {
        let evaluation = DictionaryWorkbench.evaluate(
            phrase: testPhraseField.stringValue,
            rulesText: textView.string
        )
        workbenchOutputLabel.stringValue = evaluation.outputText.isEmpty
            ? "Output: -"
            : "Output: \(evaluation.outputText)"
        workbenchMatchesLabel.stringValue = evaluation.matchSummary
        workbenchMatchesLabel.textColor = evaluation.canEvaluate ? .secondaryLabelColor : .systemRed
    }

    private func startObservingActivity() {
        refreshActivityLabel()
        activityObserver = NotificationCenter.default.addObserver(
            forName: .dictionaryFilterActivityDidChange,
            object: DictionaryFilter.shared,
            queue: .main
        ) { [weak self] _ in
            self?.refreshActivityLabel()
        }
    }

    private func loadImportedDictionary(from url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let importResult = try DictionaryDocument.importText(text)
            textView.string = importResult.rulesText
            refreshWorkbench()

            if importResult.warnings.isEmpty {
                showStatus(
                    "已导入 \(importResult.dictionary.count) 条规则。请检查后点击 Save。",
                    style: .success,
                    autoClear: false
                )
            } else {
                let summary = DictionaryParseResult(
                    dictionary: importResult.dictionary,
                    issues: importResult.warnings
                ).summary()
                showStatus(
                    "已导入 \(importResult.dictionary.count) 条规则。注意：\(summary)。请检查后点击 Save。",
                    style: .warning,
                    autoClear: false
                )
            }
        } catch {
            showStatus("导入失败：\(error.localizedDescription)", style: .error, autoClear: false)
        }
    }

    private func writeExportedDictionary(_ exportResult: DictionaryDocumentExportResult, to url: URL) {
        do {
            try exportResult.rulesText.write(to: url, atomically: true, encoding: .utf8)
            if exportResult.warnings.isEmpty {
                showStatus("已导出词典到 \(url.lastPathComponent)", style: .success, autoClear: true)
            } else {
                let summary = DictionaryParseResult(dictionary: [:], issues: exportResult.warnings).summary()
                showStatus(
                    "已导出词典到 \(url.lastPathComponent)。注意：\(summary)",
                    style: .warning,
                    autoClear: false
                )
            }
        } catch {
            showStatus("导出失败：\(error.localizedDescription)", style: .error, autoClear: false)
        }
    }

    private enum StatusStyle {
        case neutral
        case success
        case warning
        case error
    }

    private func showStatus(_ text: String, style: StatusStyle, autoClear: Bool) {
        statusResetWorkItem?.cancel()
        statusLabel.stringValue = text

        switch style {
        case .neutral:
            statusLabel.textColor = .secondaryLabelColor
        case .success:
            statusLabel.textColor = .systemGreen
        case .warning:
            statusLabel.textColor = .systemOrange
        case .error:
            statusLabel.textColor = .systemRed
        }

        guard autoClear, !text.isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.showStatus("", style: .neutral, autoClear: false)
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
