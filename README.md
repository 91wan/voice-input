# VoiceInput

### Hold `Fn` to dictate. Release to insert text.

> version-v1.6.0 | date-2026-05-03

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
- **Mode shortcut**: `Fn` uses the selected LLM mode; `Option + Fn` runs Prompt Builder for the current dictation only.
- **Readiness panel**: passively checks Accessibility, Input Monitoring, Microphone, Speech Recognition, LLM configuration, and dictionary loading.
- **Cursor insertion fallback**: if paste-style insertion fails, the generated text stays on the clipboard instead of being lost.
- **Recent Results review**: inspect the current session's latest 10 results; copy final text, retry insertion, or save a quick dictionary rule.
- **Dictionary Workbench**: test a phrase against the current dictionary rules before saving changes.
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

The Dictionary window also includes a **Test Phrase** workbench. Type a sample sentence to preview the filtered output and see which dictionary rules match. Use **Import...** to load editable rules from a text file for review, and **Export...** to save the current rules as a portable text file. Imported rules are not written to the saved dictionary until you click **Save**. Invalid rule formats block saving/exporting and are shown before they can silently affect dictation.

### LLM refinement

Open **Menu Bar -> LLM Refinement -> Settings** to configure an OpenAI-compatible API.

- API keys are stored in macOS Keychain.
- Blank API Base URL and model values fall back to defaults.
- Settings shows the current state: `Not configured`, `Ready`, or `Test failed`.
- If no API key is configured, normal `Fn` dictation still uses Apple Speech and DictionaryFilter without extra LLM failure noise.
- **Precise Dictation** keeps the text close to what you said.
- **Prompt Builder** rewrites rough speech into a structured prompt for ChatGPT, Claude, Cursor, or similar tools.
- Hold `Fn` for the selected default mode. Option + Fn uses Prompt Builder once without changing the default.
- If LLM is disabled or not configured, ordinary Fn still uses Apple Speech + DictionaryFilter without extra errors.

## Quick Start

1. Download the latest `VoiceInput.dmg` from [Releases](../../releases/latest).
2. Open the DMG, then drag `VoiceInput.app` from the left side onto `Applications` on the right side.
3. Launch `/Applications/VoiceInput.app`.
4. Grant macOS permissions when requested:
   - Microphone
   - Speech Recognition
   - Accessibility
   - Input Monitoring
5. Put the cursor in any text field, hold `Fn`, speak, and release. Use `Option + Fn` when you want a one-off Prompt Builder dictation.

If Accessibility is already enabled but VoiceInput still reports a permission failure, use **Readiness... -> Fix Permission**. Permission messages now use a **Failed / Next / Reopen** format so you can see the failed permission, the next recovery action, and whether VoiceInput must be reopened. If it still fails after an update, remove the old VoiceInput entry from Accessibility / Input Monitoring, then add `/Applications/VoiceInput.app` again.

For updates, replace the old app in `/Applications`, quit any running VoiceInput instance, and reopen it from `/Applications/VoiceInput.app`. If macOS keeps an old permission record after updating, remove the stale VoiceInput entry from Accessibility and Input Monitoring, then add the current `/Applications/VoiceInput.app` again.

> Current GitHub DMGs are **unsigned / not notarized** builds. This means macOS Gatekeeper may block the first launch even when the download is valid.

Automated release gates verify the unsigned DMG layout, app version, `.DS_Store`, `/Applications` shortcut, ad-hoc codesign validity, and expected `spctl rejected` Gatekeeper result before publishing.

If macOS shows "Apple could not verify VoiceInput":

1. Keep `VoiceInput.app` in `/Applications`.
2. Right-click `VoiceInput.app` and choose **Open**.
3. Confirm **Open** again in the system dialog.

Alternative: open **System Settings -> Privacy & Security**, allow VoiceInput near the bottom of the page, then launch it again.

## Menu Bar Controls

- **Language**: switch recognition locale.
- **Readiness...**: inspect Accessibility, Input Monitoring, Microphone, Speech Recognition, current dictation mode, LLM, and Dictionary status without requesting new permissions.
- **Dictionary...**: edit deterministic correction rules.
- **Recent Results...**: review the current session's latest 10 transcriptions and add a quick dictionary correction.
- **LLM Refinement**: enable, disable, configure, select the default refinement mode, and see the `Fn` / `Option + Fn` shortcuts.
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
- `Resources/AppIcon.icns` is a required build input

Run the local CI gate used by PRs and main pushes:

```bash
make ci
```

Run the local release gate, including DMG packaging and verification:

```bash
make release-check VERSION=1.6.0 DMG_PATH=/tmp/VoiceInput-test.dmg
```

Build the app bundle:

```bash
make build
```

Run locally:

```bash
make run
```

Run unit tests only:

```bash
swift test --parallel
```

## Release Policy

- Add a matching `CHANGELOG.md` entry before every release, for example `## [v1.1.0] - YYYY-MM-DD`.
- Run `make version-bump VERSION=v1.1.0` to update version metadata, validate release notes, run the local release gate, stage `README.md`, `Info.plist`, and `CHANGELOG.md`, and create the tag.
- Before `make version-bump`, only `CHANGELOG.md` may be dirty. All source/test/script/workflow changes must be committed first.
- `make version-bump` must run from the configured release branch, default `main`, and local HEAD must match `origin/main` before metadata mutation.
- For custom remotes or branches, run `make version-bump VERSION=vX.Y.Z REMOTE=upstream RELEASE_BRANCH=main`.
- `make version-bump` checks local and remote tag collisions before creating a tag.
- Pushing a `v*` tag builds the macOS app, packages `VoiceInput.dmg`, and publishes GitHub Release notes from `CHANGELOG.md`.
- Before a stable public release, run the manual QA coverage in `docs/release-qa-checklist.md`; `make release-check` does not replace real Fn, permission, or first-launch QA.
- Major releases should update the README and product positioning.
- Patch and minor releases should still have clear GitHub Release notes.

## Project Structure

```text
Sources/VoiceInput/
  AppDelegate.swift          menu bar lifecycle and main orchestration
  KeyMonitor.swift           Fn key monitoring
  SpeechEngine.swift         Apple Speech recording and recognition
  DictionaryFilter.swift     deterministic correction layer
  DictionaryDocument.swift   dictionary import/export normalization
  DictionaryWorkbench.swift  dictionary test phrase evaluation
  LLMRefiner.swift           optional OpenAI-compatible refinement
  TextInjector.swift         cursor insertion and clipboard fallback
  DictionaryWindow.swift     user dictionary editor
  LastResultWindow.swift     current-session recent result review
  ReadinessWindow.swift      passive setup and readiness checks
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
