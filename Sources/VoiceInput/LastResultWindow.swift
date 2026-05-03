import AppKit

final class LastResultWindow: NSPanel {
    var result: LastTranscriptionResult? {
        didSet { refresh() }
    }

    var onRetryInsert: ((LastTranscriptionResult, @escaping (TextInjectionResult) -> Void) -> Void)?
    var onSaveDictionaryRule: ((String, String) throws -> Int)?

    private let resultPopup = NSPopUpButton()
    private let summaryLabel = NSTextField(labelWithString: "No transcription yet.")
    private let rawTextView = NSTextView()
    private let filteredTextView = NSTextView()
    private let refinedTextView = NSTextView()
    private let finalTextView = NSTextView()
    private let sourceField = NSTextField()
    private let replacementField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var previousActiveApplication: NSRunningApplication?
    private var results: [LastTranscriptionResult] = []
    private var statusResetWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Recent Results"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 640, height: 520)
        setupUI()
        refresh()
        center()
    }

    func present(result: LastTranscriptionResult?) {
        results = result.map { [$0] } ?? []
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousActiveApplication = frontmostApplication
        }

        self.result = result
        reloadResultPopup()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func present(results: [LastTranscriptionResult]) {
        self.results = results
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousActiveApplication = frontmostApplication
        }

        result = results.first
        reloadResultPopup()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(results: [LastTranscriptionResult], selected: LastTranscriptionResult?) {
        self.results = results
        result = selected ?? results.first
        reloadResultPopup(selecting: result)
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        cv.addSubview(stack)

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 3
        stack.addArrangedSubview(summaryLabel)

        stack.addArrangedSubview(makeSection(title: "Raw Apple Speech", textView: rawTextView, height: 62))
        stack.addArrangedSubview(makeSection(title: "After DictionaryFilter", textView: filteredTextView, height: 62))
        stack.addArrangedSubview(makeSection(title: "After LLMRefiner", textView: refinedTextView, height: 62))
        stack.addArrangedSubview(makeSection(title: "Final Text", textView: finalTextView, height: 86))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let copyButton = NSButton(title: "Copy Final", target: self, action: #selector(copyFinalText))
        copyButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(copyButton)

        let retryButton = NSButton(title: "Retry Insert", target: self, action: #selector(retryInsert))
        retryButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(retryButton)

        stack.addArrangedSubview(buttonRow)

        let correctionBox = NSBox()
        correctionBox.title = "Quick Dictionary Rule"
        correctionBox.translatesAutoresizingMaskIntoConstraints = false
        correctionBox.boxType = .primary
        let correctionContentView = NSView()
        correctionBox.contentView = correctionContentView

        let correctionStack = NSStackView()
        correctionStack.translatesAutoresizingMaskIntoConstraints = false
        correctionStack.orientation = .vertical
        correctionStack.spacing = 8
        correctionContentView.addSubview(correctionStack)

        let helpLabel = NSTextField(labelWithString: "Save a deterministic replacement for future dictation. Edit both fields before saving if the full sentence is too broad.")
        helpLabel.font = .systemFont(ofSize: 12)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.maximumNumberOfLines = 2
        correctionStack.addArrangedSubview(helpLabel)

        correctionStack.addArrangedSubview(makeFieldRow(label: "Recognized as", field: sourceField))
        correctionStack.addArrangedSubview(makeFieldRow(label: "Correct as", field: replacementField))

        let saveRuleButton = NSButton(title: "Save Rule", target: self, action: #selector(saveDictionaryRule))
        saveRuleButton.bezelStyle = .rounded
        correctionStack.addArrangedSubview(saveRuleButton)

        stack.addArrangedSubview(correctionBox)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -14),

            correctionBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            correctionStack.topAnchor.constraint(equalTo: correctionContentView.topAnchor, constant: 10),
            correctionStack.leadingAnchor.constraint(equalTo: correctionContentView.leadingAnchor, constant: 10),
            correctionStack.trailingAnchor.constraint(equalTo: correctionContentView.trailingAnchor, constant: -10),
            correctionStack.bottomAnchor.constraint(equalTo: correctionContentView.bottomAnchor, constant: -10),
        ])

        resultPopup.target = self
        resultPopup.action = #selector(selectResult)
        stack.insertArrangedSubview(resultPopup, at: 0)
    }

    private func makeSection(title: String, textView: NSTextView, height: CGFloat) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 12)
        container.addArrangedSubview(label)

        configureReadOnly(textView)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        container.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            scrollView.widthAnchor.constraint(equalTo: container.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: height),
        ])

        return container
    }

    private func configureReadOnly(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
    }

    private func makeFieldRow(label: String, field: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12)
        field.font = .systemFont(ofSize: 13)

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(field)

        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 96),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])

        return row
    }

    private func refresh() {
        guard let result else {
            resultPopup.isHidden = true
            summaryLabel.stringValue = "No transcription yet."
            rawTextView.string = ""
            filteredTextView.string = ""
            refinedTextView.string = ""
            finalTextView.string = ""
            sourceField.stringValue = ""
            replacementField.stringValue = ""
            showStatus("", style: .neutral, autoClear: false)
            return
        }

        resultPopup.isHidden = results.count <= 1
        let time = result.createdAt.formatted(date: .omitted, time: .standard)
        summaryLabel.stringValue = "\(time) | \(result.refinementSummary) | \(result.dictionarySummary) | \(result.injectionSummary)"
        rawTextView.string = result.rawText
        filteredTextView.string = result.filteredText
        refinedTextView.string = result.refinedText ?? "No LLM refinement used."
        finalTextView.string = result.finalText

        if let draft = result.defaultRuleDraft {
            sourceField.stringValue = draft.source
            replacementField.stringValue = draft.replacement
        } else {
            sourceField.stringValue = ""
            replacementField.stringValue = ""
        }
    }

    private func reloadResultPopup(selecting selectedResult: LastTranscriptionResult? = nil) {
        resultPopup.removeAllItems()
        for (index, result) in results.enumerated() {
            let time = result.createdAt.formatted(date: .omitted, time: .standard)
            let text = result.finalText.replacingOccurrences(of: "\n", with: " ")
            let preview = text.count > 48 ? "\(text.prefix(48))..." : text
            resultPopup.addItem(withTitle: "\(index + 1). \(time) - \(preview)")
        }
        resultPopup.isHidden = results.count <= 1
        if let selectedResult,
           let index = results.firstIndex(where: { $0.hasSameIdentity(as: selectedResult) }) {
            resultPopup.selectItem(at: index)
        } else if !results.isEmpty {
            resultPopup.selectItem(at: 0)
        }
    }

    @objc private func selectResult() {
        let index = resultPopup.indexOfSelectedItem
        guard results.indices.contains(index) else { return }
        result = results[index]
    }

    @objc private func copyFinalText() {
        guard let text = result?.finalText.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            showStatus("No final text to copy.", style: .warning, autoClear: true)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showStatus("Copied final text to clipboard.", style: .success, autoClear: true)
    }

    @objc private func retryInsert() {
        guard let selectedResult = result else {
            showStatus("No final text to insert.", style: .warning, autoClear: true)
            return
        }
        guard !selectedResult.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStatus("No final text to insert.", style: .warning, autoClear: true)
            return
        }
        guard let onRetryInsert else {
            showStatus("Retry handler is unavailable.", style: .error, autoClear: false)
            return
        }

        guard let targetApplication = previousActiveApplication else {
            showStatus("No previous app to return to. Focus the target app, then open Recent Results again.", style: .warning, autoClear: false)
            return
        }

        orderOut(nil)
        targetApplication.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            onRetryInsert(selectedResult) { [weak self] injectionResult in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let updatedResult = selectedResult.withInjectionResult(injectionResult)
                    self.updateDisplayedResult(updatedResult)
                    self.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    switch injectionResult {
                    case .success:
                        self.showStatus("Retried insertion.", style: .success, autoClear: true)
                    case .failure(let failure):
                        self.showStatus(failure.localizedDescription, style: .error, autoClear: false)
                    }
                }
            }
        }
    }

    private func updateDisplayedResult(_ updatedResult: LastTranscriptionResult) {
        if let index = results.firstIndex(where: { $0.hasSameIdentity(as: updatedResult) }) {
            results[index] = updatedResult
            result = updatedResult
            reloadResultPopup(selecting: updatedResult)
        } else {
            result = updatedResult
        }
    }

    @objc private func saveDictionaryRule() {
        let source = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !replacement.isEmpty else {
            showStatus("Both recognized and correct text are required.", style: .warning, autoClear: true)
            return
        }
        guard let onSaveDictionaryRule else {
            showStatus("Dictionary save handler is unavailable.", style: .error, autoClear: false)
            return
        }

        do {
            let count = try onSaveDictionaryRule(source, replacement)
            showStatus("Saved dictionary rule. Total user rules: \(count).", style: .success, autoClear: true)
        } catch {
            showStatus("Save failed: \(error.localizedDescription)", style: .error, autoClear: false)
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
