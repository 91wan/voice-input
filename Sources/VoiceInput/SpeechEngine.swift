import AVFoundation
import Speech

final class SpeechEngine {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onLocaleUnavailable: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    var locale: Locale {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
            if speechRecognizer == nil {
                onLocaleUnavailable?("Speech recognition is not supported for \(locale.identifier). Please check that the language is downloaded in System Settings → General → Keyboard → Dictation.")
            }
        }
    }

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Permissions

    static func requestPermissions(completion: @escaping (Bool, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                completion(true, nil)
                            } else {
                                completion(false, "Microphone access denied.\nGrant in System Settings → Privacy & Security → Microphone.")
                            }
                        }
                    }
                case .denied, .restricted:
                    completion(false, "Speech recognition denied.\nGrant in System Settings → Privacy & Security → Speech Recognition.")
                case .notDetermined:
                    completion(false, "Speech recognition permission not determined.")
                @unknown default:
                    completion(false, "Unknown speech recognition authorization status.")
                }
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Speech recognizer not available for \(locale.identifier)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        // Boost recognition accuracy for common technical terms, brand names, and
        // Chinese homophones that Apple Speech frequently mishears.
        request.contextualStrings = [
            // Programming languages & runtimes
            "Python", "Swift", "Kotlin", "TypeScript", "JavaScript", "Rust", "Go",
            "Node.js", "Deno", "Bun", "WASM", "WebAssembly",
            // Frameworks & tools
            "SwiftUI", "React", "Vue", "Next.js", "Nuxt", "Vite", "Webpack",
            "Docker", "Kubernetes", "Terraform", "Ansible", "Helm",
            "Xcode", "VS Code", "Cursor", "Neovim",
            // AI / ML
            "OpenAI", "ChatGPT", "Claude", "Gemini", "Whisper", "LLaMA",
            "GPT-4", "GPT-4o", "Anthropic", "Mistral", "Ollama",
            "RAG", "embedding", "fine-tuning", "tokenizer", "transformer",
            "OpenClaw", "LangChain", "LlamaIndex",
            // Cloud & infra
            "AWS", "GCP", "Azure", "Cloudflare", "Vercel", "Railway",
            "S3", "EC2", "Lambda", "DynamoDB", "PostgreSQL", "Redis",
            "Nginx", "Caddy", "Traefik",
            // Protocols & formats
            "API", "REST", "GraphQL", "gRPC", "WebSocket", "OAuth",
            "JSON", "YAML", "TOML", "Markdown", "CSV",
            "HTTP", "HTTPS", "TCP", "UDP", "SSH", "TLS", "SSL",
            // Dev concepts
            "GitHub", "GitLab", "CI/CD", "PR", "commit", "rebase", "merge",
            "async", "await", "concurrency", "mutex", "coroutine",
            "debug", "breakpoint", "stack trace", "segfault",
            // Chinese tech terms frequently misheared
            "接口", "部署", "微服务", "容器", "镜像", "仓库", "分支",
            "回调", "异步", "并发", "缓存", "队列", "中间件",
            "前端", "后端", "全栈", "运维", "架构",
        ]
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error {
                let nsErr = error as NSError
                // 216 = kSFSpeechRecognitionErrorCanceled (user cancelled, silent)
                // 1110 = kSFSpeechRecognitionErrorNoSpeechDetected (single FN tap with no speech, silent)
                let silentCodes: Set<Int> = [216, 1110]
                if !silentCodes.contains(nsErr.code) {
                    self.onError?(error.localizedDescription)
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrtf(sum / Float(max(frameLength, 1)))
            let dB = 20 * log10(max(rms, 1e-6))
            let normalized = max(Float(0), min(Float(1), (dB + 50) / 40))
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            cleanup()
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    func cancel() {
        recognitionTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
    }
}
