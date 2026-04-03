import AppKit

final class DictionaryWindow: NSPanel {
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

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
        center()
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
        statusLabel.lineBreakMode = .byTruncatingTail
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

            scrollView.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -8),

            saveButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
        ])
    }

    private func loadEntries() {
        let dict = DictionaryFilter.shared.userMap
        if dict.isEmpty {
            textView.string = "# 示例（删除后写入你自己的规则）\n# 格式：错误识别词 → 正确词\nexample app → ExampleApp\nopen claw → OpenClaw"
        } else {
            textView.string = DictionaryFilter.serializeToText(dict)
        }
    }

    @objc private func save() {
        let dict = DictionaryFilter.parseText(textView.string)
        do {
            try DictionaryFilter.shared.saveUserDictionary(dict)
            showStatus("已保存 \(dict.count) 条规则 ✓", success: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showStatus("", success: nil)
            }
        } catch {
            showStatus("保存失败: \(error.localizedDescription)", success: false)
        }
    }

    private func showStatus(_ text: String, success: Bool?) {
        statusLabel.stringValue = text
        switch success {
        case .some(true):  statusLabel.textColor = .systemGreen
        case .some(false): statusLabel.textColor = .systemRed
        case .none:        statusLabel.textColor = .secondaryLabelColor
        }
    }
}
