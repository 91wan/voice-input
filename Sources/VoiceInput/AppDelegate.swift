import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let defaultLocaleCode = "zh-CN"
    static let supportedLanguages: [(name: String, code: String)] = [
        ("System Default", ""),
        ("English (US)", "en-US"),
        ("中文 (简体)", "zh-CN"),
        ("中文 (繁體)", "zh-TW"),
        ("日本語", "ja-JP"),
        ("한국어", "ko-KR"),
    ]

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
        get { Self.normalizedLocaleCode(UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? Self.defaultLocaleCode) }
        set { UserDefaults.standard.set(Self.normalizedLocaleCode(newValue), forKey: "selectedLocaleCode") }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedCode = selectedLocaleCode
        selectedLocaleCode = savedCode
        speechEngine.locale = Self.locale(forSelectedLocaleCode: savedCode)

        let dictionaryLoadResult = DictionaryFilter.shared.loadUserDictionary()
        syncLLMEnabledState()
        setupStatusBar()
        setupSpeechCallbacks()

        if case .failure(let message) = dictionaryLoadResult {
            showAlert(
                title: "Dictionary Unavailable",
                message: "\(message)\n\n可以在菜单栏 → Dictionary... 中修正后重新保存。"
            )
        }

        SpeechEngine.requestPermissions { [weak self] granted, issue in
            if !granted, let issue {
                self?.showPermissionAlert(issue)
            }
        }

        keyMonitor.onFnDown = { [weak self] in self?.fnDown() }
        keyMonitor.onFnUp = { [weak self] in self?.fnUp() }
        settingsWindow.onSettingsSaved = { [weak self] in
            self?.syncLLMEnabledState()
            self?.updateLLMMenuItemState()
        }

        if !keyMonitor.start() {
            disableForMissingAccessibilityPermission()
        }
    }

    // MARK: - Key events

    private func fnDown() {
        guard isEnabled, !isRecording else { return }
        // Start a hold timer — only activate recording after fnHoldThreshold.
        // This prevents single taps from triggering any UI or audio.
        fnHoldTimer?.invalidate()
        fnHoldTimer = Self.scheduleOneShotTimer(interval: fnHoldThreshold) { [weak self] _ in
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

        finalResultTimer = Self.scheduleOneShotTimer(interval: 2.0) { [weak self] _ in
            self?.finishTranscription(sessionID: sessionID)
        }
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechEngine.onPartialResult = { [weak self] text in
            guard let self else { return }
            guard Self.shouldAcceptSpeechCallback(
                activeSessionID: self.activeTranscriptionSessionID,
                sessions: self.transcriptionSessions
            ) else { return }
            self.lastPartialResult = text
            self.overlayPanel.updateText(text)
        }

        speechEngine.onFinalResult = { [weak self] text in
            guard let self else { return }
            guard Self.shouldAcceptSpeechCallback(
                activeSessionID: self.activeTranscriptionSessionID,
                sessions: self.transcriptionSessions
            ) else { return }
            let sessionID = self.activeTranscriptionSessionID
            self.lastPartialResult = text
            self.finalResultTimer?.invalidate()
            self.finalResultTimer = nil
            self.finishTranscription(sessionID: sessionID)
        }

        speechEngine.onError = { [weak self] msg in
            guard let self else { return }
            guard Self.shouldAcceptSpeechCallback(
                activeSessionID: self.activeTranscriptionSessionID,
                sessions: self.transcriptionSessions
            ) else { return }
            self.resetActiveTranscriptionState()
            let resetSessionID = self.transcriptionSessions.currentID
            self.overlayPanel.updateText("Error: \(msg)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.transcriptionSessions.isCurrent(resetSessionID) else { return }
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
        guard transcriptionSessions.claimCurrent(sessionID) else { return }
        finalResultTimer?.invalidate()
        finalResultTimer = nil

        let text = lastPartialResult.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            transcriptionSessions.invalidate()
            activeTranscriptionSessionID = transcriptionSessions.currentID
            speechEngine.cancel()
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

    private func resetActiveTranscriptionState() {
        fnHoldTimer?.invalidate()
        fnHoldTimer = nil
        finalResultTimer?.invalidate()
        finalResultTimer = nil
        transcriptionSessions.invalidate()
        activeTranscriptionSessionID = transcriptionSessions.currentID
        LLMRefiner.shared.cancel()
        speechEngine.cancel()
        isRecording = false
        lastPartialResult = ""
        updateStatusIcon(recording: false)
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
        for (name, code) in Self.supportedLanguages {
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
                disableForMissingAccessibilityPermission()
            }
        } else {
            keyMonitor.stop()
            resetActiveTranscriptionState()
            overlayPanel.dismiss()
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        selectedLocaleCode = code
        speechEngine.locale = Self.locale(forSelectedLocaleCode: code)

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }
    }

    @objc private func toggleLLM() {
        let refiner = LLMRefiner.shared
        if refiner.isEnabled {
            refiner.isEnabled = false
            refiner.cancel()
            updateLLMMenuItemState()
            return
        }

        guard refiner.isConfigured else {
            refiner.isEnabled = false
            updateLLMMenuItemState()
            settingsWindow.present(
                message: "Add an API key before enabling LLM refinement.",
                success: false,
                focusAPIKey: true
            )
            return
        }

        refiner.isEnabled = true
        updateLLMMenuItemState()
    }

    @objc private func openLLMSettings() {
        settingsWindow.present()
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
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(
                url
            )
        }
    }

    private func disableForMissingAccessibilityPermission() {
        isEnabled = false
        enableMenuItem?.state = .off
        keyMonitor.stop()
        showAccessibilityAlert()
    }

    private func showPermissionAlert(_ issue: SpeechPermissionIssue) {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = issue.message
        alert.alertStyle = .warning

        if issue.settingsURL != nil {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = issue.settingsURL {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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

    private func syncLLMEnabledState() {
        let refiner = LLMRefiner.shared
        if refiner.isEnabled && !refiner.isConfigured {
            refiner.isEnabled = false
            refiner.cancel()
        }
    }

    private func updateLLMMenuItemState() {
        llmMenuItem?.state = LLMRefiner.shared.isEnabled ? .on : .off
    }

    static func locale(forSelectedLocaleCode code: String) -> Locale {
        let normalizedCode = normalizedLocaleCode(code)
        return normalizedCode.isEmpty ? .current : Locale(identifier: normalizedCode)
    }

    static func normalizedLocaleCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportedCodes = Set(supportedLanguages.map(\.code))
        return supportedCodes.contains(trimmed) ? trimmed : defaultLocaleCode
    }

    static func shouldAcceptSpeechCallback(activeSessionID: Int, sessions: SessionCounter) -> Bool {
        sessions.isCurrent(activeSessionID) && !sessions.isClaimed(activeSessionID)
    }

    static func scheduleOneShotTimer(interval: TimeInterval, handler: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
