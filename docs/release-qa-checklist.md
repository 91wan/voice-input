# VoiceInput Release QA Checklist

Use this checklist before a stable public release such as `v1.2.0`.

## Stable Release Gate

- Install / first launch / permission / Fn / Option + Fn coverage must pass before tagging a stable public release.
- README and GitHub Release notes must document the full first-install path.
- README and GitHub Release notes must document the update permission recovery path.
- If any manual QA item fails, ship only a narrow fix or defer the release.

## Automated Release Gate

- PR/main gate: `make ci` runs the local CI gate used by GitHub Actions on pull requests and main/tag pushes.
- `swift test --parallel`.
- `swift build -Xswiftc -warnings-as-errors`.
- `make build`.
- App icon asset gate: `iconutil` extraction/round-trip succeeds and all required icon representations have the expected pixel dimensions.
- Local release gate: `make release-check VERSION=<version> DMG_PATH=/tmp/VoiceInput-test.dmg`.
- The release gate includes DMG packaging and `./scripts/verify-dmg.sh`.
- Automated DMG layout gate: `make release-check` mounts the DMG and verifies Finder layout values: icon size, bounds, app position, and Applications position.
- DMG artifact check: mounted DMG contains `VoiceInput.app`, `Applications -> /Applications`, `.DS_Store`, and a non-empty app icon without launching the app.
- Version bump gate: `make version-bump VERSION=vX.Y.Z` validates release notes, runs the local release gate before commit/tag, and stages `README.md`, `Info.plist`, and `CHANGELOG.md` for the bump commit.
- Version bump source gate: only `CHANGELOG.md` may be dirty before `make version-bump`; source/test/script/workflow changes must be committed before `make version-bump`.
- Version bump branch gate: `make version-bump` must run on the configured release branch, default `main`, and local HEAD must match `origin/main` before metadata mutation.
- Version bump tag gate: `make version-bump` checks local and remote tag collisions before creating a tag.
- `codesign --verify --deep --strict VoiceInput.app`.
- `spctl -a -vvv -t execute VoiceInput.app` returns rejected for unsigned / not notarized builds.
- Release workflow verifies the published DMG layout before creating the GitHub Release.

## Manual Permission And Fn QA

These checks require launching the app and interacting with macOS permissions, so they stay outside automated CI unless explicitly re-authorized.

Automated `make release-check` does not replace manual QA for real app launch, permission recovery, `Fn`, or `Option + Fn` behavior.

Record manual QA evidence in `docs/manual-qa-log-template.md`. Do not treat the template itself as passed QA.

Optional human visual confirmation can be recorded in `docs/manual-qa-log-template.md`. A screenshot is useful evidence, but the automated DMG layout gate is the required release artifact check.

Automated icon verification checks file format, dimensions, ICNS parsing, round-trip conversion, and bundle inclusion. It does not replace human review of appearance or small-size readability.

## Manual App Icon QA

- Review the icon at 16, 32, 64, 128, 256, and 512 pixels on both light and dark backgrounds.
- Confirm the 160pt DMG icon is sharp, centered, and not clipped.
- Confirm highlights, shadows, and transparent edges do not create light/dark halos.
- Record visual approval separately from the automated asset gate; neither check replaces the other.

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
- Menu and Readiness both show the default `Fn` mode and that `Option + Fn` is one-shot.
- Recent Results shows the mode used for the selected result.
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
