import AppKit

enum SettingsValidationError: LocalizedError, Equatable {
    case invalidAPIBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidAPIBaseURL:
            return "Invalid API base URL. Use a full http(s) base URL, for example https://api.openai.com/v1."
        }
    }
}

final class SettingsWindow: NSPanel {
    struct ValidatedSettings: Equatable {
        let apiBaseURL: String
        let model: String
    }

    private let apiBaseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let defaultStatusText = "API key is stored in your macOS Keychain."
    private var statusGeneration = 0
    private let testController = LLMSettingsTestController()
    private var testState: LLMSettingsTestState = .notRun
    var onSettingsSaved: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "LLM Refinement Settings"
        isReleasedWhenClosed = false
        setupUI()
        loadSettings()
        center()
    }

    private func setupUI() {
        guard let cv = contentView else { return }

        apiBaseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "sk-..."
        modelField.placeholderString = "gpt-4o-mini"

        let labels = ["API Base URL:", "API Key:", "Model:"].map { text -> NSTextField in
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            return label
        }

        let grid = NSGridView(views: [
            [labels[0], apiBaseURLField],
            [labels[1], apiKeyField],
            [labels[2], modelField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 12
        grid.columnSpacing = 8

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = defaultStatusText

        let testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [statusLabel, testButton, saveButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        cv.addSubview(grid)
        cv.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            apiBaseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            modelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            buttonRow.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 20),
            buttonRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
        ])

        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func loadSettings() {
        let refiner = LLMRefiner.shared
        apiBaseURLField.stringValue = refiner.apiBaseURL
        apiKeyField.stringValue = refiner.apiKey
        modelField.stringValue = refiner.model
        testState = .notRun
        refreshConfigurationStatus()
    }

    func present(message: String? = nil, success: Bool? = nil, focusAPIKey: Bool = false) {
        statusGeneration += 1
        loadSettings()
        if let message {
            showStatus(message, success: success)
        } else {
            refreshConfigurationStatus()
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if focusAPIKey {
            makeFirstResponder(apiKeyField)
        }
    }

    override func close() {
        testController.cancelActiveTest()
        super.close()
    }

    @objc private func test() {
        statusGeneration += 1
        let generation = testController.beginAttempt()
        testState = .notRun

        do {
            try applyFields()
            onSettingsSaved?()
        } catch {
            showStatus(error.localizedDescription, success: false)
            return
        }

        let refiner = LLMRefiner.shared
        guard refiner.isConfigured else {
            showStatus("API key is empty", success: false)
            return
        }

        testState = .testing
        refreshConfigurationStatus()

        let request = refiner.refine("Hello, this is a test.", force: true) { [weak self] result in
            guard let self, self.testController.finishTest(generation: generation) else { return }
            switch result {
            case .success(let text):
                self.testState = .succeeded(text)
                self.refreshConfigurationStatus()
            case .failure(let error):
                if case LLMRefiner.RefinerError.cancelled = error {
                    self.testState = .notRun
                    self.showStatus("Test cancelled.", success: nil)
                    return
                }
                self.testState = .failed(error.localizedDescription)
                self.refreshConfigurationStatus()
            }
        }
        testController.setActiveRequest(request, generation: generation)
    }

    @objc private func save() {
        statusGeneration += 1
        testController.cancelActiveTest()
        do {
            try applyFields()
            onSettingsSaved?()
            testState = .notRun
            refreshConfigurationStatus(prefix: "Saved. ")
        } catch {
            showStatus(error.localizedDescription, success: false)
            return
        }
        close()
    }

    private func applyFields() throws {
        let settings = try Self.validatedSettings(
            apiBaseURL: apiBaseURLField.stringValue,
            model: modelField.stringValue
        )
        let refiner = LLMRefiner.shared
        try refiner.updateAPIKey(apiKeyField.stringValue)
        refiner.apiBaseURL = settings.apiBaseURL
        refiner.model = settings.model
    }

    private func refreshConfigurationStatus(prefix: String = "") {
        let refiner = LLMRefiner.shared
        let status = LLMSettingsStatus.make(
            isConfigured: refiner.isConfigured,
            apiBaseURL: refiner.apiBaseURL,
            model: refiner.model,
            mode: refiner.mode,
            testState: testState
        )
        showStatus(prefix + status.displayText, success: status.isReady ? true : nil)
    }

    static func validatedSettings(apiBaseURL: String, model: String) throws -> ValidatedSettings {
        let normalizedBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedBaseURL.isEmpty, LLMRefiner.chatCompletionsURL(from: normalizedBaseURL) == nil {
            throw SettingsValidationError.invalidAPIBaseURL
        }

        return ValidatedSettings(apiBaseURL: normalizedBaseURL, model: normalizedModel)
    }

    private func showStatus(_ text: String, success: Bool?) {
        statusLabel.stringValue = text
        switch success {
        case .some(true):
            statusLabel.textColor = .systemGreen
        case .some(false):
            statusLabel.textColor = .systemRed
        case .none:
            statusLabel.textColor = .secondaryLabelColor
        }
    }
}
