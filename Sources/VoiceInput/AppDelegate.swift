import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private let recentResults = RecentTranscriptionStore(capacity: 10)
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true
    private var dictationPhase: DictationPhase = .idle
    private var lastPartialResult = ""
    private var finalResultTimer: Timer?
    private var fnHoldTimer: Timer?
    private var activeLLMRequest: CancellableRequest?
    private var transcriptionSessions = SessionCounter()
    private var activeTranscriptionSessionID = 0
    private var activeShortcutMode: DictationShortcutMode = .defaultMode
    /// Minimum hold duration (seconds) before Fn activates recording.
    private let fnHoldThreshold: TimeInterval = 0.3

    private var enableMenuItem: NSMenuItem!
    private var permissionStatusMenuItem: NSMenuItem!
    private var eventMonitorStartFailed = false
    private var llmMenuItem: NSMenuItem!
    private var llmModeItems: [NSMenuItem] = []
    private var defaultShortcutMenuItem: NSMenuItem!
    private var promptBuilderShortcutMenuItem: NSMenuItem!
    private var dictationStatusMenuItem: NSMenuItem!
    private var dictionaryStatusMenuItem: NSMenuItem!
    private var lastResultMenuItem: NSMenuItem!
    private lazy var settingsWindow = SettingsWindow()
    private lazy var dictionaryWindow = DictionaryWindow()
    private lazy var lastResultWindow = LastResultWindow()
    private lazy var readinessWindow = ReadinessWindow()
    private var lastTranscriptionResult: LastTranscriptionResult? {
        didSet {
            lastResultWindow.update(results: recentResults.results, selected: lastTranscriptionResult)
            updateLastResultMenuItem()
        }
    }
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

        keyMonitor.onFnDown = { [weak self] mode in self?.fnDown(shortcutMode: mode) }
        keyMonitor.onFnUp = { [weak self] in self?.fnUp() }
        settingsWindow.onSettingsSaved = { [weak self] in
            self?.syncLLMEnabledState()
            self?.updateLLMMenuItemState()
        }
        readinessWindow.onAction = { [weak self] action in
            self?.handleReadinessAction(action)
        }
        lastResultWindow.onRetryInsert = { [weak self] selectedResult, completion in
            guard let self else {
                completion(.failure(.pasteCommandFailed))
                return
            }
            let injectionResult = Self.retryInsertResult(
                finalText: selectedResult.finalText,
                phase: self.dictationPhase
            ) { text in
                self.textInjector.inject(text)
            }
            self.recordRetryInjectionResult(injectionResult, for: selectedResult)
            completion(injectionResult)
        }
        lastResultWindow.onCanRetryInsert = { [weak self] in
            Self.retryInsertAvailability(phase: self?.dictationPhase ?? .idle)
        }
        lastResultWindow.onSaveDictionaryRule = { [weak self] source, replacement in
            var dict = DictionaryFilter.shared.userMap
            dict[source] = replacement
            try DictionaryFilter.shared.saveUserDictionary(dict)
            self?.updateDictionaryStatusMenuItem()
            return DictionaryFilter.shared.userMap.count
        }

        startKeyMonitorOrDisable()
    }

    // MARK: - Key events

    private func fnDown(shortcutMode: DictationShortcutMode) {
        guard isEnabled else { return }
        guard Self.shouldStartNewDictation(isEnabled: isEnabled, phase: dictationPhase) else {
            showBusyDictationHint()
            return
        }
        guard dictationPhase.fnDown() == .startHold else {
            showBusyDictationHint()
            return
        }
        // Start a hold timer — only activate recording after fnHoldThreshold.
        // This prevents single taps from triggering any UI or audio.
        fnHoldTimer?.invalidate()
        fnHoldTimer = Self.scheduleOneShotTimer(interval: fnHoldThreshold) { [weak self] _ in
            guard let self, self.isEnabled, self.dictationPhase == .holding else { return }
            let sessionID = self.transcriptionSessions.begin()
            guard self.dictationPhase.holdThresholdReached(sessionID: sessionID) == .startRecording(sessionID: sessionID) else {
                self.transcriptionSessions.invalidate()
                self.activeTranscriptionSessionID = self.transcriptionSessions.currentID
                return
            }
            self.activeTranscriptionSessionID = sessionID
            self.activeShortcutMode = shortcutMode
            self.lastPartialResult = ""
            self.updateStatusIcon(recording: true)
            let prompt = shortcutMode == .promptBuilder ? "Listening... Prompt Builder" : "Listening..."
            self.overlayPanel.show(text: prompt)
            NSSound(named: .init("Tink"))?.play()
            self.speechEngine.startRecording()
        }
    }

    private func fnUp() {
        // If released before the hold threshold fires, cancel silently — no UI, no sound.
        if let timer = fnHoldTimer, timer.isValid {
            timer.invalidate()
            fnHoldTimer = nil
            _ = dictationPhase.reset()
            return
        }
        fnHoldTimer = nil

        guard case .stopRecording(let sessionID) = dictationPhase.fnUp() else { return }

        updateStatusIcon(recording: false)
        speechEngine.stopRecording()

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
            _ = dictationPhase.reset()
            overlayPanel.dismiss()
            lastPartialResult = ""
            activeShortcutMode = .defaultMode
            return
        }

        speechEngine.finishAfterResultConsumed()

        let dictionaryResult = DictionaryFilter.shared.applying(text)
        let filtered = dictionaryResult.text
        updateDictionaryStatusMenuItem()
        let refiner = LLMRefiner.shared
        let refinementMode = Self.refinementMode(
            for: activeShortcutMode,
            defaultMode: refiner.mode
        )
        if refiner.isEnabled && refiner.isConfigured {
            overlayPanel.showRefining()
            activeLLMRequest = refiner.refine(filtered, mode: refinementMode) { [weak self] result in
                guard let self else { return }
                guard Self.shouldAcceptTranscriptionCompletion(
                    activeSessionID: sessionID,
                    sessions: self.transcriptionSessions
                ) else { return }
                self.activeLLMRequest = nil
                switch result {
                case .success(let refined):
                    let output = TranscriptionResolution.resolve(
                        filteredText: filtered,
                        refinedText: refined
                    )
                    self.recordLastResult(
                        rawText: text,
                        dictionaryResult: dictionaryResult,
                        output: output,
                        refinedText: refined,
                        dictationMode: refinementMode,
                        refinementMode: refinementMode
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
                    NSLog("[LLMRefiner] Refine failed: %@", Self.llmFailureLogSummary(for: error))
                    let output = TranscriptionResolution.resolve(
                        filteredText: filtered,
                        refinedText: nil
                    )
                    self.recordLastResult(
                        rawText: text,
                        dictionaryResult: dictionaryResult,
                        output: output,
                        refinedText: nil,
                        dictationMode: refinementMode,
                        refinementMode: refinementMode
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
                self.activeShortcutMode = .defaultMode
            }
        } else {
            let output = TranscriptionResolution.resolve(
                filteredText: filtered,
                refinedText: nil
            )
            recordLastResult(
                rawText: text,
                dictionaryResult: dictionaryResult,
                output: output,
                refinedText: nil,
                dictationMode: refinementMode,
                refinementMode: nil
            )
            overlayPanel.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performTextInjection(filtered, sessionID: sessionID)
            }
            lastPartialResult = ""
            activeShortcutMode = .defaultMode
        }
    }

    private func recordLastResult(
        rawText: String,
        dictionaryResult: DictionaryApplyResult,
        output: TranscriptionResolution.Output,
        refinedText: String?,
        dictationMode: LLMRefinementMode?,
        refinementMode: LLMRefinementMode?
    ) {
        let result = LastTranscriptionResult.make(
            rawText: rawText,
            dictionaryResult: dictionaryResult,
            resolvedOutput: output,
            refinedText: refinedText,
            dictationMode: dictationMode,
            refinementMode: refinementMode,
            injectionResult: nil
        )
        recentResults.record(result)
        lastTranscriptionResult = result
    }

    private func recordInjectionResult(_ result: TextInjectionResult) {
        recentResults.updateMostRecentInjectionResult(result)
        lastTranscriptionResult = lastTranscriptionResult?.withInjectionResult(result)
    }

    private func recordRetryInjectionResult(_ injectionResult: TextInjectionResult, for selectedResult: LastTranscriptionResult) {
        recentResults.updateInjectionResult(injectionResult, for: selectedResult)
        if lastTranscriptionResult?.hasSameIdentity(as: selectedResult) == true {
            lastTranscriptionResult = lastTranscriptionResult?.withInjectionResult(injectionResult)
        }
    }

    private func performTextInjection(_ text: String, sessionID: Int) {
        guard transcriptionSessions.isCurrent(sessionID) else { return }
        guard dictationPhase.beginInjection(sessionID: sessionID) == .beginInjecting(sessionID: sessionID) else { return }
        let injectionResult = textInjector.inject(text)
        recordInjectionResult(injectionResult)
        _ = dictationPhase.finishInjection(sessionID: sessionID)

        switch injectionResult {
        case .success:
            NSSound(named: .init("Pop"))?.play()
        case .failure(let failure):
            NSLog("[TextInjector] Inject failed: %@", Self.textInjectionFailureLogSummary(for: failure))
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
        activeShortcutMode = .defaultMode
        cancelActiveLLMRequest()
        speechEngine.cancel()
        _ = dictationPhase.reset()
        lastPartialResult = ""
        updateStatusIcon(recording: false)
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(recording: false)

        let menu = NSMenu()
        menu.delegate = self

        enableMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        permissionStatusMenuItem = NSMenuItem(
            title: ReadinessDiagnostics.capture().menuTitle,
            action: nil,
            keyEquivalent: ""
        )
        permissionStatusMenuItem.isEnabled = false
        menu.addItem(permissionStatusMenuItem)

        dictationStatusMenuItem = NSMenuItem(
            title: Self.dictationWorkflowStatus().menuSummary,
            action: nil,
            keyEquivalent: ""
        )
        dictationStatusMenuItem.isEnabled = false
        menu.addItem(dictationStatusMenuItem)

        let permissionsItem = NSMenuItem(title: "Readiness...", action: #selector(openPermissionDiagnostics), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

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

        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in LLMRefinementMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(changeLLMMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == LLMRefiner.shared.mode ? .on : .off
            llmModeItems.append(item)
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        llmMenu.addItem(modeItem)

        defaultShortcutMenuItem = NSMenuItem(
            title: Self.defaultShortcutMenuTitle(defaultMode: LLMRefiner.shared.mode),
            action: nil,
            keyEquivalent: ""
        )
        defaultShortcutMenuItem.isEnabled = false
        llmMenu.addItem(defaultShortcutMenuItem)

        promptBuilderShortcutMenuItem = NSMenuItem(
            title: Self.promptBuilderShortcutMenuTitle(),
            action: nil,
            keyEquivalent: ""
        )
        promptBuilderShortcutMenuItem.isEnabled = false
        llmMenu.addItem(promptBuilderShortcutMenuItem)

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

        lastResultMenuItem = NSMenuItem(title: "Recent Results...", action: #selector(openLastResult), keyEquivalent: "")
        lastResultMenuItem.target = self
        lastResultMenuItem.isEnabled = false
        menu.addItem(lastResultMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VoiceInput", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionStatusMenuItem()
        updateDictionaryStatusMenuItem()
        updateLLMModeMenuItemStates()
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
            startKeyMonitorOrDisable()
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
            cancelActiveLLMRequest()
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

    @objc private func changeLLMMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = LLMRefinementMode(rawValue: rawValue)
        else { return }

        LLMRefiner.shared.mode = mode
        updateLLMModeMenuItemStates()
    }

    @objc private func openLLMSettings() {
        settingsWindow.present()
    }

    @objc private func openDictionary() {
        updateDictionaryStatusMenuItem()
        dictionaryWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLastResult() {
        lastResultWindow.present(results: recentResults.results)
    }

    @objc private func openPermissionDiagnostics() {
        readinessWindow.present(ReadinessDiagnostics.capture(eventMonitorStartFailed: eventMonitorStartFailed))
        updatePermissionStatusMenuItem()
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let guidance = PermissionRecoveryGuidance.make(
            diagnostics: PermissionDiagnostics.capture(),
            eventMonitorStartFailed: eventMonitorStartFailed
        )
        let alert = NSAlert()
        alert.messageText = guidance.title
        alert.informativeText = guidance.detail
        alert.alertStyle = .warning
        if guidance.primarySettingsURL != nil {
            alert.addButton(withTitle: "Fix Permission")
        }
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let url = guidance.primarySettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func startKeyMonitorOrDisable() {
        if keyMonitor.start() {
            eventMonitorStartFailed = false
            updatePermissionStatusMenuItem()
        } else {
            disableForInputPermissionIssue()
        }
    }

    private func disableForInputPermissionIssue() {
        eventMonitorStartFailed = true
        isEnabled = false
        enableMenuItem?.state = .off
        keyMonitor.stop()
        updatePermissionStatusMenuItem()
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

    private func updatePermissionStatusMenuItem() {
        permissionStatusMenuItem?.title = ReadinessDiagnostics.capture(
            eventMonitorStartFailed: eventMonitorStartFailed
        ).menuTitle
    }

    private func updateLastResultMenuItem() {
        lastResultMenuItem?.isEnabled = !recentResults.results.isEmpty
    }

    private func syncLLMEnabledState() {
        let refiner = LLMRefiner.shared
        if refiner.isEnabled && !refiner.isConfigured {
            refiner.isEnabled = false
            cancelActiveLLMRequest()
        }
    }

    private func updateLLMMenuItemState() {
        llmMenuItem?.state = LLMRefiner.shared.isEnabled ? .on : .off
        let status = Self.dictationWorkflowStatus()
        dictationStatusMenuItem?.title = status.menuSummary
        defaultShortcutMenuItem?.title = status.defaultShortcutTitle
        promptBuilderShortcutMenuItem?.title = status.promptBuilderShortcutTitle
    }

    private func updateLLMModeMenuItemStates() {
        let currentMode = LLMRefiner.shared.mode
        for item in llmModeItems {
            guard let rawValue = item.representedObject as? String else { continue }
            item.state = rawValue == currentMode.rawValue ? .on : .off
        }
        let status = Self.dictationWorkflowStatus()
        dictationStatusMenuItem?.title = status.menuSummary
        defaultShortcutMenuItem?.title = status.defaultShortcutTitle
        promptBuilderShortcutMenuItem?.title = status.promptBuilderShortcutTitle
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

    static func shouldAcceptTranscriptionCompletion(activeSessionID: Int, sessions: SessionCounter) -> Bool {
        sessions.isCurrent(activeSessionID)
    }

    static func shouldStartNewDictation(isEnabled: Bool, phase: DictationPhase) -> Bool {
        isEnabled && phase.isIdle
    }

    static func refinementMode(
        for shortcutMode: DictationShortcutMode,
        defaultMode: LLMRefinementMode
    ) -> LLMRefinementMode {
        switch shortcutMode {
        case .defaultMode:
            return defaultMode
        case .promptBuilder:
            return .promptBuilder
        }
    }

    static func defaultShortcutMenuTitle(defaultMode: LLMRefinementMode) -> String {
        DictationWorkflowStatus.make(
            defaultMode: defaultMode,
            isLLMEnabled: true,
            isLLMConfigured: true
        ).defaultShortcutTitle
    }

    static func promptBuilderShortcutMenuTitle() -> String {
        DictationWorkflowStatus.make(
            defaultMode: .precise,
            isLLMEnabled: true,
            isLLMConfigured: true
        ).promptBuilderShortcutTitle
    }

    static func llmFailureLogSummary(for error: Error) -> String {
        LLMRefinementError.safeLogSummary(for: error)
    }

    static func textInjectionFailureLogSummary(for failure: TextInjectionFailure) -> String {
        switch failure {
        case .emptyText:
            return "empty_text"
        case .accessibilityPermissionMissing:
            return "accessibility_permission_missing"
        case .pasteboardWriteFailed:
            return "pasteboard_write_failed"
        case .pasteCommandFailed:
            return "paste_command_failed"
        case .dictationBusy:
            return "dictation_busy"
        }
    }

    static func retryInsertAvailability(phase: DictationPhase) -> RetryInsertAvailability {
        RetryInsertPolicy.availability(phase: phase)
    }

    static func retryInsertResult(
        finalText: String,
        phase: DictationPhase,
        inject: (String) -> TextInjectionResult
    ) -> TextInjectionResult {
        switch retryInsertAvailability(phase: phase) {
        case .allowed:
            return inject(finalText)
        case .busy:
            return .failure(.dictationBusy)
        }
    }

    static func dictationWorkflowStatus() -> DictationWorkflowStatus {
        DictationWorkflowStatus.make(
            defaultMode: LLMRefiner.shared.mode,
            isLLMEnabled: LLMRefiner.shared.isEnabled,
            isLLMConfigured: LLMRefiner.shared.isConfigured
        )
    }

    static func scheduleOneShotTimer(interval: TimeInterval, handler: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false, block: handler)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func cancelActiveLLMRequest() {
        activeLLMRequest?.cancel()
        activeLLMRequest = nil
    }

    private func showBusyDictationHint() {
        guard BusyDictationHintPolicy.shouldShowTransient(
            phase: dictationPhase,
            isOverlayVisible: overlayPanel.isVisible
        ) else { return }

        overlayPanel.showTransient(text: "Finishing previous dictation...", duration: 0.8)
    }

    private func handleReadinessAction(_ action: ReadinessAction) {
        switch action {
        case .openAccessibilitySettings:
            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .openInputMonitoringSettings:
            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .openMicrophoneSettings:
            if let url = SpeechPermissionIssue.microphoneDenied.settingsURL {
                NSWorkspace.shared.open(url)
            }
        case .openSpeechSettings:
            if let url = SpeechPermissionIssue.speechRecognitionDenied.settingsURL {
                NSWorkspace.shared.open(url)
            }
        case .openLLMSettings:
            settingsWindow.present()
        case .openDictionary:
            openDictionary()
        }
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
