import AppKit

final class DictionaryWindow: NSPanel {
    private let textView = NSTextView()
    private let activityLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var activityObserver: NSObjectProtocol?
    private var statusResetWorkItem: DispatchWorkItem?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
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
        scrollView.documentView = textView
        cv.addSubview(scrollView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        cv.addSubview(statusLabel)

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
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            statusLabel.topAnchor.constraint(greaterThanOrEqualTo: scrollView.bottomAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -8),

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
        } catch {
            showStatus("保存失败：\(error.localizedDescription)", style: .error, autoClear: false)
        }
    }

    private func refreshActivityLabel() {
        activityLabel.stringValue = DictionaryFilter.shared.lastActivitySummary
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
