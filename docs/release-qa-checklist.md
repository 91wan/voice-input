# VoiceInput Release QA Checklist

Use this checklist before a stable public release such as `v1.2.0`.

## Stable Release Gate

- Install / first launch / permission / Fn / Option + Fn coverage must pass before tagging a stable public release.
- README and GitHub Release notes must document the full first-install path.
- README and GitHub Release notes must document the update permission recovery path.
- If any manual QA item fails, ship only a narrow fix or defer the release.

## Installation And First Launch

- Download the GitHub Release `VoiceInput.dmg`.
- Mount the DMG and confirm `VoiceInput.app` is on the left and `Applications` is on the right.
- Drag `VoiceInput.app` into `/Applications`.
- First launch from `/Applications/VoiceInput.app`.
- For unsigned builds, confirm the release notes explain that Developer ID signing and notarization are out of scope.

## Permission Recovery

- Fresh launch with no permissions granted.
- Accessibility enabled but Input Monitoring missing.
- Microphone missing.
- Speech Recognition missing.
- Permissions enabled after launch, then quit and reopen VoiceInput.
- Remove stale VoiceInput entries from Accessibility / Input Monitoring and add `/Applications/VoiceInput.app` again.
- Permission errors use the `Failed / Next / Reopen` format.

## Dictation Shortcuts

- Pure `Fn` starts dictation.
- `Option + Fn` starts Prompt Builder for the current dictation only.
- `Fn + normal key` does not start dictation.
- `Fn + Control` does not start dictation.

## Core Product Paths

- Insert into TextEdit.
- Insert into a browser text field.
- Insert into ChatGPT or Claude input.
- Recent Results opens, copies final text, and retries insertion.
- Dictionary test phrase works before save.
- LLM disabled still runs Apple Speech + DictionaryFilter.
- LLM enabled with a configured API key shows Ready state.
