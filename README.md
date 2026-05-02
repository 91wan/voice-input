# VoiceInput

### Hold `Fn` to dictate. Release to insert text.

> version-v1.0.1 | date-2026-05-02

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

VoiceInput is a small macOS menu bar speech-to-text app for people who write with mixed natural language and technical terms. Hold the `Fn` key, speak, release, and the recognized text is inserted at the current cursor position.

The core idea is simple: keep common corrections deterministic, and use an LLM only when it adds value.

```text
Audio -> Apple Speech -> DictionaryFilter -> optional LLMRefiner -> TextInjector
```

## Why VoiceInput?

- **Fast push-to-talk flow**: hold `Fn` to record, release to insert, with a 300 ms guard against accidental taps.
- **Native recognition**: uses Apple Speech on macOS, with no required cloud transcription provider.
- **Deterministic dictionary layer**: fixes predictable ASR mistakes before the text reaches an LLM.
- **Optional LLM refinement**: supports OpenAI-compatible APIs for grammar cleanup or prompt-building.
- **Cursor insertion fallback**: if paste-style insertion fails, the generated text stays on the clipboard instead of being lost.
- **Menu bar first**: no heavy window workflow; the main app lives in the macOS menu bar.

## Features

### Dictionary corrections

VoiceInput ships with a small built-in dictionary for common technical terms:

| Recognized text | Output |
| --- | --- |
| `open claw` | `OpenClaw` |
| `type script` | `TypeScript` |
| `java script` | `JavaScript` |
| `data base` | `database` |
| `配森` / `派森` | `Python` |
| `迪克耳` | `Docker` |
| `库伯内坦斯` | `Kubernetes` |
| `杰森` | `JSON` |
| `拉姆达` | `Lambda` |

Open **Menu Bar -> Dictionary...** to add your own rules:

```text
# One rule per line
type script -> TypeScript
open claw -> OpenClaw
my project -> MyProject
```

The user dictionary is saved at:

```text
~/Library/Application Support/VoiceInput/dictionary.json
```

### LLM refinement

Open **Menu Bar -> LLM Refinement -> Settings** to configure an OpenAI-compatible API.

- API keys are stored in macOS Keychain.
- Blank API Base URL and model values fall back to defaults.
- If LLM refinement is enabled without an API key, VoiceInput opens Settings and asks for one.
- **Precise Dictation** keeps the text close to what you said.
- **Prompt Builder** rewrites rough speech into a structured prompt for ChatGPT, Claude, Cursor, or similar tools.

## Quick Start

1. Download the latest `VoiceInput.dmg` from [Releases](../../releases/latest).
2. Drag `VoiceInput.app` to `/Applications`.
3. Launch the app.
4. Grant macOS permissions when requested:
   - Microphone
   - Speech Recognition
   - Accessibility
5. Put the cursor in any text field, hold `Fn`, speak, and release.

> Current builds are distributed as lightweight macOS app bundles. If macOS blocks the first launch, open **System Settings -> Privacy & Security** and allow the app, or right-click the app and choose **Open**.

## Menu Bar Controls

- **Language**: switch recognition locale.
- **Dictionary...**: edit deterministic correction rules.
- **LLM Refinement**: enable, disable, configure, and select refinement mode.
- **Quit**: stop VoiceInput.

## Supported Languages

Recognition locale can be switched from the menu bar:

- Chinese Simplified
- Chinese Traditional
- English
- Japanese
- Korean

## Build From Source

Requirements:

- macOS 14 Sonoma or newer
- Xcode Command Line Tools

Build the app bundle:

```bash
make build
```

Run locally:

```bash
make run
```

Run tests:

```bash
swift test --parallel
```

## Release Policy

- Add a matching `CHANGELOG.md` entry before every release, for example `## [v1.0.2] - YYYY-MM-DD`.
- Run `make version-bump VERSION=v1.0.2` to update version metadata and create the tag.
- Pushing a `v*` tag builds the macOS app, packages `VoiceInput.dmg`, and publishes GitHub Release notes from `CHANGELOG.md`.
- Major releases should update the README and product positioning.
- Patch and minor releases should still have clear GitHub Release notes.

## Project Structure

```text
Sources/VoiceInput/
  AppDelegate.swift          menu bar lifecycle and main orchestration
  KeyMonitor.swift           Fn key monitoring
  SpeechEngine.swift         Apple Speech recording and recognition
  DictionaryFilter.swift     deterministic correction layer
  LLMRefiner.swift           optional OpenAI-compatible refinement
  TextInjector.swift         cursor insertion and clipboard fallback
  DictionaryWindow.swift     user dictionary editor
  SettingsWindow.swift       LLM settings UI
```

## FAQ

### Does VoiceInput require an LLM?

No. Apple Speech and DictionaryFilter work without any LLM configuration.

### Where is my API key stored?

The API key is stored in macOS Keychain, not in plain `UserDefaults`.

### What happens if text insertion fails?

VoiceInput leaves the generated text on the clipboard so you can paste it manually.

### Does VoiceInput collect telemetry?

No telemetry service is included.

## License

MIT
