APP_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
APP_ICON_SOURCE := Resources/AppIcon.icns
APP_ICON := $(APP_BUNDLE)/Contents/Resources/AppIcon.icns

.PHONY: build clean install run ci

build:
	@set -e; \
	swift build -c release; \
	BUILD_DIR=$$(swift build -c release --show-bin-path); \
	mkdir -p $(APP_BUNDLE)/Contents/MacOS; \
	mkdir -p $(APP_BUNDLE)/Contents/Resources; \
	cp "$$BUILD_DIR/$(APP_NAME)" $(APP_BUNDLE)/Contents/MacOS/; \
	cp Info.plist $(APP_BUNDLE)/Contents/; \
	if [ -f "$(APP_ICON_SOURCE)" ]; then \
		cp $(APP_ICON_SOURCE) $(APP_ICON); \
	else \
		echo "⚠️  Missing $(APP_ICON_SOURCE); app will build without a custom icon."; \
	fi; \
	codesign --force --sign - $(APP_BUNDLE)
	@echo "\n✅ Built $(APP_BUNDLE)"

ci:
	@set -e; \
	test -s $(APP_ICON_SOURCE); \
	swift test --parallel; \
	swift build -Xswiftc -warnings-as-errors; \
	$(MAKE) build

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

## version-bump VERSION=v1.x.x: 更新 README 版本号+日期，打 tag，一键触发 CI 发布
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
	@awk -v tag="$(VERSION)" '\
		/^## / { \
			heading = $$0; \
			sub(/^##[[:space:]]+\[/, "", heading); \
			sub(/^##[[:space:]]+/, "", heading); \
			sub(/\].*$$/, "", heading); \
			sub(/[[:space:]].*$$/, "", heading); \
			if (heading == tag) { found = 1; exit } \
		} \
		END { exit found ? 0 : 1 } \
	' CHANGELOG.md || { \
		echo "❌ CHANGELOG.md 缺少 $(VERSION) 条目，请先添加 release notes"; \
		exit 1; \
	}
	@set -e; \
	VERSION_NO_V=$${VERSION#v}; \
	echo "🔖 Bumping to $(VERSION)..."; \
	sed -i '' -e 's/version-v[0-9][0-9a-z._-]*/version-$(VERSION)/g' README.md; \
	sed -i '' -e 's/date-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/date-$(shell date +%Y-%m-%d)/g' README.md; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION_NO_V" Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION_NO_V" Info.plist
	@git add README.md Info.plist
	@git commit -m "chore: bump version to $(VERSION)"
	@git tag $(VERSION)
	@echo "✅ 完成。执行以下命令触发自动构建与发布:"
	@echo "   git push origin main $(VERSION)"

.PHONY: version-bump
