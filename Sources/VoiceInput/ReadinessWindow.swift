import AppKit

final class ReadinessWindow: NSPanel {
    var onAction: ((ReadinessAction) -> Void)?

    private let stack = NSStackView()
    private var actionsByTag: [Int: ReadinessAction] = [:]
    private var nextActionTag = 1

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "VoiceInput Readiness"
        isReleasedWhenClosed = false
        setupUI()
        center()
    }

    func present(_ diagnostics: ReadinessDiagnostics) {
        render(diagnostics)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let cv = contentView else { return }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        cv.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -18),
        ])
    }

    private func render(_ diagnostics: ReadinessDiagnostics) {
        actionsByTag.removeAll()
        nextActionTag = 1
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let titleLabel = NSTextField(labelWithString: diagnostics.title)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.textColor = diagnostics.isReady ? .systemGreen : .systemOrange
        stack.addArrangedSubview(titleLabel)

        let helpLabel = NSTextField(labelWithString: "Readiness checks are passive. VoiceInput will not request permissions from this panel.")
        helpLabel.font = .systemFont(ofSize: 12)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(helpLabel)

        for item in diagnostics.items {
            stack.addArrangedSubview(makeRow(for: item))
        }
    }

    private func makeRow(for item: ReadinessItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let status = NSTextField(labelWithString: symbol(for: item.state))
        status.font = .systemFont(ofSize: 15)
        status.textColor = color(for: item.state)
        row.addArrangedSubview(status)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let title = NSTextField(labelWithString: item.title)
        title.font = .boldSystemFont(ofSize: 13)
        textStack.addArrangedSubview(title)

        let detail = NSTextField(labelWithString: item.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(detail)

        row.addArrangedSubview(textStack)

        if let action = item.action {
            let button = NSButton(title: titleForAction(action), target: self, action: #selector(runAction(_:)))
            button.bezelStyle = .rounded
            button.tag = nextActionTag
            actionsByTag[nextActionTag] = action
            nextActionTag += 1
            row.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 470),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])

        return row
    }

    @objc private func runAction(_ sender: NSButton) {
        guard let action = actionsByTag[sender.tag] else { return }
        onAction?(action)
    }

    private func symbol(for state: ReadinessState) -> String {
        switch state {
        case .ready:
            return "●"
        case .attention:
            return "▲"
        case .optional:
            return "○"
        }
    }

    private func color(for state: ReadinessState) -> NSColor {
        switch state {
        case .ready:
            return .systemGreen
        case .attention:
            return .systemOrange
        case .optional:
            return .secondaryLabelColor
        }
    }

    private func titleForAction(_ action: ReadinessAction) -> String {
        switch action {
        case .openAccessibilitySettings, .openInputMonitoringSettings, .openMicrophoneSettings, .openSpeechSettings:
            return "Open Settings"
        case .openLLMSettings:
            return "Open LLM"
        case .openDictionary:
            return "Open Dictionary"
        }
    }
}
