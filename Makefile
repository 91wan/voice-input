APP_NAME := VoiceInput
APP_BUNDLE := $(APP_NAME).app
APP_ICON := $(APP_BUNDLE)/Contents/Resources/AppIcon.icns

.PHONY: build clean install run

build:
	@set -e; \
	swift build -c release; \
	BUILD_DIR=$$(swift build -c release --show-bin-path); \
	mkdir -p $(APP_BUNDLE)/Contents/MacOS; \
	mkdir -p $(APP_BUNDLE)/Contents/Resources; \
	cp "$$BUILD_DIR/$(APP_NAME)" $(APP_BUNDLE)/Contents/MacOS/; \
	cp Info.plist $(APP_BUNDLE)/Contents/; \
	if [ ! -f "$(APP_ICON)" ]; then \
		echo "⚠️  Missing $(APP_ICON); app will build without a custom icon."; \
	fi; \
	codesign --force --sign - $(APP_BUNDLE)
	@echo "\n✅ Built $(APP_BUNDLE)"

run: build
	-pkill -x $(APP_NAME) 2>/dev/null || true
	open -n $(APP_BUNDLE)

clean:
	swift package clean
	rm -f $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

install: build
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/
	@echo "✅ Installed to /Applications/$(APP_BUNDLE)"

## version-bump VERSION=v1.x.x: 更新 README 版本号+日期，打 tag，一键触发 CI 发布
version-bump:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ 缺少版本号，用法: make version-bump VERSION=v1.x.x"; \
		exit 1; \
	fi
	@VERSION_NO_V=$${VERSION#v}; \
	echo "🔖 Bumping to $(VERSION)..."; \
	sed -i '' -e 's/version-[0-9a-z._-]*/version-$(VERSION)/g' README.md; \
	sed -i '' -e 's/date-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/date-$(shell date +%Y-%m-%d)/g' README.md; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION_NO_V" Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION_NO_V" Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION_NO_V" VoiceInput.app/Contents/Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION_NO_V" VoiceInput.app/Contents/Info.plist
	@git add README.md Info.plist VoiceInput.app/Contents/Info.plist
	@git commit -m "chore: bump version to $(VERSION)"
	@git tag $(VERSION)
	@echo "✅ 完成。执行以下命令触发自动构建与发布:"
	@echo "   git push origin main $(VERSION)"

.PHONY: version-bump
