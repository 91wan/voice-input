APP_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
APP_ICON_SOURCE := Resources/AppIcon.icns
APP_ICON := $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
DMG_PATH ?= VoiceInput.dmg
VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)

.PHONY: build clean install run ci package-dmg verify-dmg release-artifact release-check

build:
	@set -e; \
	test -s "$(APP_ICON_SOURCE)" || { \
		echo "❌ Missing or empty $(APP_ICON_SOURCE)"; \
		exit 1; \
	}; \
	swift build -c release; \
	BUILD_DIR=$$(swift build -c release --show-bin-path); \
	mkdir -p $(APP_BUNDLE)/Contents/MacOS; \
	mkdir -p $(APP_BUNDLE)/Contents/Resources; \
	cp "$$BUILD_DIR/$(APP_NAME)" $(APP_BUNDLE)/Contents/MacOS/; \
	cp Info.plist $(APP_BUNDLE)/Contents/; \
	cp "$(APP_ICON_SOURCE)" "$(APP_ICON)"; \
	codesign --force --sign - $(APP_BUNDLE)
	@echo "\n✅ Built $(APP_BUNDLE)"

ci:
	@set -e; \
	test -s "$(APP_ICON_SOURCE)"; \
	test -x scripts/package-dmg.sh; \
	test -x scripts/verify-dmg.sh; \
	test -x scripts/extract-release-notes.sh; \
	test -x scripts/check-version-bump-source-state.sh; \
	test -x scripts/check-version-bump-tag-state.sh; \
	swift test --parallel; \
	swift build -Xswiftc -warnings-as-errors; \
	$(MAKE) build

package-dmg: build
	./scripts/package-dmg.sh "$(APP_BUNDLE)" "$(DMG_PATH)" "$(APP_NAME)"

verify-dmg:
	@test -n "$(VERSION)" || { echo "❌ Missing VERSION"; exit 1; }
	./scripts/verify-dmg.sh "$(DMG_PATH)" "$(VERSION)" "$(APP_NAME)"

release-artifact:
	@set -e; \
	$(MAKE) package-dmg DMG_PATH="$(DMG_PATH)"; \
	$(MAKE) verify-dmg VERSION="$(VERSION)" DMG_PATH="$(DMG_PATH)"

release-check: ci
	$(MAKE) release-artifact VERSION="$(VERSION)" DMG_PATH="$(DMG_PATH)"

run: build
	-pkill -x $(APP_NAME) 2>/dev/null || true
	open -n $(APP_BUNDLE)

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME).dmg

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

## version-bump VERSION=v1.x.x: 验证 release notes，更新版本元数据，运行 release-check，打 tag
version-bump:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ 缺少版本号，用法: make version-bump VERSION=v1.x.x"; \
		exit 1; \
	fi; \
	case "$(VERSION)" in v*) ;; *) \
		echo "❌ VERSION 必须以 v 开头，才能触发 v* release workflow"; \
		exit 1; \
		;; \
		esac; \
	printf '%s\n' "$(VERSION)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$' || { \
		echo "❌ VERSION 格式必须是 v1.2.3"; \
		exit 1; \
	}
	@./scripts/check-version-bump-source-state.sh pre
	@./scripts/check-version-bump-tag-state.sh "$(VERSION)" origin
	@./scripts/extract-release-notes.sh CHANGELOG.md "$(VERSION)" >/dev/null
	@set -e; \
	VERSION_NO_V=$${VERSION#v}; \
	echo "🔖 Bumping to $(VERSION)..."; \
	sed -i '' -e 's/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g' README.md; \
	sed -i '' -e 's/date-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/date-$(shell date +%Y-%m-%d)/g' README.md; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION_NO_V" Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION_NO_V" Info.plist
	@VERSION_NO_V=$${VERSION#v}; \
	"$${MAKE:-make}" release-check VERSION="$$VERSION_NO_V" DMG_PATH="/tmp/VoiceInput-$(VERSION).dmg"
	@./scripts/check-version-bump-source-state.sh post
	@git add README.md Info.plist CHANGELOG.md
	@git commit -m "chore: bump version to $(VERSION)"
	@git tag $(VERSION)
	@echo "✅ 完成。执行以下命令触发自动构建与发布:"
	@echo "   git push origin main $(VERSION)"

.PHONY: version-bump
