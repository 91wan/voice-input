# VoiceInput Manual QA Log Template

Use this file as a copyable template for release candidates that require real app launch, Fn key, and macOS permission testing. The existence of this template does not mean manual QA has passed.

| Date | Build | macOS | Scenario | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Fresh launch with no permissions | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Accessibility enabled but Input Monitoring missing | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Microphone missing | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Speech Recognition missing | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Fn pure dictation | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Option + Fn prompt builder | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Fn + normal key does not start dictation | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Insert into TextEdit | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Insert into browser field | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Recent Results retry insert idle path | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | Recent Results retry insert busy path | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | LLM disabled basic dictation | Not run / Pass / Fail | |
| YYYY-MM-DD | `/Applications/VoiceInput.app` or DMG path | macOS version | LLM configured test request cancel/retry | Not run / Pass / Fail | |
