import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let speechEngine = SpeechEngine()
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true
    private var isRecording = false
    private var lastPartialResult = ""
    private var finalResultTimer: Timer?
    private var fnHoldTimer: Timer?
    private var transcriptionSessions = SessionCounter()
    private var activeTranscriptionSessionID = 0
    /// Minimum hold duration (seconds) before Fn activates recording.
    private let fnHoldThreshold: TimeInterval = 0.3

    private var enableMenuItem: NSMenuItem!
    private var llmMenuItem: NSMenuItem!
    private var dictionaryStatusMenuItem: NSMenuItem!
    private lazy var settingsWindow = SettingsWindow()
    private lazy var dictionaryWindow = DictionaryWindow()
    private var languageItems: [NSMenuItem] = []
    private var selectedLocaleCode: String {
        get { UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLocaleCode") }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedCode = selectedLocaleCode
        if !savedCode.isEmpty {
            speechEngine.locale = Locale(identifier: savedCode)
        }

        let dictionaryLoadResult = DictionaryFilter.shared.loadUserDictionary()
        setupStatusBar()
        setupSpeechCallbacks()

        if case .failure(let message) = dictionaryLoadResult {
            showAlert(
                title: "Dictionary Unavailable",
                message: "\(message)\n\n可以在菜单栏 → Dictionary... 中修正后重新保存。"
            )
        }

        SpeechEngine.requestPermissions { [weak self] granted, errorMsg in
            if !granted, let msg = errorMsg {
                self?.showAlert(title: "Permission Required", message: msg)
            }
        }

        if !keyMonitor.start() {
            showAccessibilityAlert()
        }

        keyMonitor.onFnDown = { [weak self] in self?.fnDown() }
        keyMonitor.onFnUp = { [weak self] in self?.fnUp() }
    }

    // MARK: - Key events

    private func fnDown() {
        guard isEnabled, !isRecording else { return }
        // Start a hold timer — only activate recording after fnHoldThreshold.
        // This prevents single taps from triggering any UI or audio.
        fnHoldTimer?.invalidate()
        fnHoldTimer = Timer.scheduledTimer(withTimeInterval: fnHoldThreshold, repeats: false) { [weak self] _ in
            guard let self, self.isEnabled, !self.isRecording else { return }
            LLMRefiner.shared.cancel()
            let sessionID = self.transcriptionSessions.begin()
            self.activeTranscriptionSessionID = sessionID
            self.isRecording = true
            self.lastPartialResult = ""
            self.updateStatusIcon(recording: true)
            self.overlayPanel.show(text: "Listening...")
            NSSound(named: .init("Tink"))?.play()
            self.speechEngine.startRecording()
        }
    }

    private func fnUp() {
        // If released before the hold threshold fires, cancel silently — no UI, no sound.
        if let timer = fnHoldTimer, timer.isValid {
            timer.invalidate()
            fnHoldTimer = nil
            return
        }
        fnHoldTimer = nil

        guard isRecording else { return }
        isRecording = false

        updateStatusIcon(recording: false)
        speechEngine.stopRecording()
        let sessionID = activeTranscriptionSessionID

        finalResultTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.finishTranscription(sessionID: sessionID)
        }
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechEngine.onPartialResult = { [weak self] text in
            guard let self else { return }
            self.lastPartialResult = text
            self.overlayPanel.updateText(text)
        }

        speechEngine.onFinalResult = { [weak self] text in
            guard let self else { return }
            let sessionID = self.activeTranscriptionSessionID
            self.lastPartialResult = text
            self.finalResultTimer?.invalidate()
            self.finalResultTimer = nil
            self.finishTranscription(sessionID: sessionID)
        }

        speechEngine.onError = { [weak self] msg in
            guard let self else { return }
            self.overlayPanel.updateText("Error: \(msg)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.overlayPanel.dismiss()
            }
        }

        speechEngine.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }

        speechEngine.onLocaleUnavailable = { [weak self] msg in
            self?.showAlert(title: "Language Unavailable", message: msg)
        }
    }

    private func finishTranscription(sessionID: Int) {
        guard transcriptionSessions.isCurrent(sessionID) else { return }
        finalResultTimer?.invalidate()
        finalResultTimer = nil

        let text = lastPartialResult.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            overlayPanel.dismiss()
            lastPartialResult = ""
            return
        }

        let dictionaryResult = DictionaryFilter.shared.applying(text)
        let filtered = dictionaryResult.text
        updateDictionaryStatusMenuItem()
        let refiner = LLMRefiner.shared
        if refiner.isEnabled && refiner.isConfigured {
            overlayPanel.showRefining()
            refiner.refine(filtered) { [weak self] result in
                guard let self else { return }
                guard self.transcriptionSessions.isCurrent(sessionID) else { return }
                switch result {
                case .success(let refined):
                    let output = TranscriptionResolution.resolve(
                        filteredText: filtered,
                        refinedText: refined
                    )
                    if output.wasLLMRefined {
                        self.overlayPanel.updateText("✨ \(output.text)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            guard self.transcriptionSessions.isCurrent(sessionID) else { return }
                            self.overlayPanel.dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.performTextInjection(output.text, sessionID: sessionID)
                            }
                        }
                    } else {
                        self.overlayPanel.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.performTextInjection(output.text, sessionID: sessionID)
                        }
                    }
                case .failure(let error):
                    NSLog("[LLMRefiner] Refine failed: %@", error.localizedDescription)
                    let output = TranscriptionResolution.resolve(
                        filteredText: filtered,
                        refinedText: nil
                    )
                    self.overlayPanel.updateText("Refine failed, using dictionary result")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard self.transcriptionSessions.isCurrent(sessionID) else { return }
                        self.overlayPanel.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.performTextInjection(output.text, sessionID: sessionID)
                        }
                    }
                }
                self.lastPartialResult = ""
            }
        } else {
            overlayPanel.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performTextInjection(filtered, sessionID: sessionID)
            }
            lastPartialResult = ""
        }
    }

    private func performTextInjection(_ text: String, sessionID: Int) {
        guard transcriptionSessions.isCurrent(sessionID) else { return }
        switch textInjector.inject(text) {
        case .success:
            NSSound(named: .init("Pop"))?.play()
        case .failure(let failure):
            NSLog("[TextInjector] Inject failed: %@", failure.localizedDescription)
            overlayPanel.show(text: failure.localizedDescription)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.transcriptionSessions.isCurrent(sessionID) else { return }
                self.overlayPanel.dismiss()
            }

            if failure.shouldPromptForAccessibility {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, self.transcriptionSessions.isCurrent(sessionID) else { return }
                    self.showAccessibilityAlert()
                }
            }
        }
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(recording: false)

        let menu = NSMenu()

        enableMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let languages: [(String, String)] = [
            ("System Default", ""),
            ("English (US)", "en-US"),
            ("中文 (简体)", "zh-CN"),
            ("中文 (繁體)", "zh-TW"),
            ("日本語", "ja-JP"),
            ("한국어", "ko-KR"),
        ]
        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == selectedLocaleCode ? .on : .off
            languageItems.append(item)
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // LLM Refinement submenu
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        llmMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLM), keyEquivalent: "")
        llmMenuItem.target = self
        llmMenuItem.state = LLMRefiner.shared.isEnabled ? .on : .off
        llmMenu.addItem(llmMenuItem)

        llmMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openLLMSettings), keyEquivalent: "")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        let dictItem = NSMenuItem(title: "Dictionary...", action: #selector(openDictionary), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        dictionaryStatusMenuItem = NSMenuItem(title: DictionaryFilter.shared.lastActivitySummary, action: nil, keyEquivalent: "")
        dictionaryStatusMenuItem.isEnabled = false
        menu.addItem(dictionaryStatusMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VoiceInput", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusIcon(recording: Bool) {
        guard let button = statusItem.button else { return }
        let name = recording ? "mic.fill" : "mic"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Voice Input")
        button.contentTintColor = recording ? .systemRed : nil
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enableMenuItem.state = isEnabled ? .on : .off

        if isEnabled {
            if !keyMonitor.start() {
                showAccessibilityAlert()
            }
        } else {
            keyMonitor.stop()
            transcriptionSessions.invalidate()
            activeTranscriptionSessionID = transcriptionSessions.currentID
            finalResultTimer?.invalidate()
            finalResultTimer = nil
            LLMRefiner.shared.cancel()
            lastPartialResult = ""
            overlayPanel.dismiss()
            if isRecording {
                speechEngine.cancel()
                isRecording = false
                updateStatusIcon(recording: false)
            }
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        selectedLocaleCode = code
        speechEngine.locale = code.isEmpty ? .current : Locale(identifier: code)

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }
    }

    @objc private func toggleLLM() {
        let refiner = LLMRefiner.shared
        refiner.isEnabled.toggle()
        llmMenuItem.state = refiner.isEnabled ? .on : .off
    }

    @objc private func openLLMSettings() {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDictionary() {
        updateDictionaryStatusMenuItem()
        dictionaryWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            VoiceInput needs Accessibility permission to monitor the Fn key.

            1. Open System Settings → Privacy & Security → Accessibility
            2. Add and enable VoiceInput
            3. Restart the app
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func updateDictionaryStatusMenuItem() {
        dictionaryStatusMenuItem?.title = DictionaryFilter.shared.lastActivitySummary
    }
}
