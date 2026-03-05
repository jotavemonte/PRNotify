APP       = PRNotify.app
BINARY    = $(APP)/Contents/MacOS/PRNotify
PLIST     = $(APP)/Contents/Info.plist
RESOURCES = $(APP)/Contents/Resources
SDK     = $(shell xcrun --show-sdk-path --sdk macosx)
TARGET  = arm64-apple-macosx14.0
SOURCES = \
	PRNotify/main.swift \
	PRNotify/AppDelegate.swift \
	PRNotify/Models/PullRequest.swift \
	PRNotify/Models/Settings.swift \
	PRNotify/Services/GitHubService.swift \
	PRNotify/Services/NotificationService.swift \
	PRNotify/UI/MenuBuilder.swift \
	PRNotify/UI/SettingsWindowController.swift \
	PRNotify/Storage/RecentPRsStore.swift \
	PRNotify/Storage/PRActivityStore.swift

TEST_SOURCES = \
	PRNotify/Models/PullRequest.swift \
	PRNotify/Models/Settings.swift \
	PRNotify/Storage/RecentPRsStore.swift \
	PRNotify/Storage/PRActivityStore.swift \
	Tests/TestRunner.swift \
	Tests/PullRequestTests.swift \
	Tests/SettingsTests.swift \
	Tests/StoreTests.swift \
	Tests/main.swift

VERSION ?= 0.0.1

.PHONY: build clean run test dmg

build:
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc $(SOURCES) \
		-sdk $(SDK) -target $(TARGET) \
		-framework AppKit -framework UserNotifications -framework ServiceManagement \
		-O -o $(BINARY)
	cp PRNotify/PRNotify-Info.plist $(PLIST)
	cp PRNotify/Assets/menubar-icon.svg $(RESOURCES)/
	cp PRNotify/Assets/PRNotify.icns $(RESOURCES)/
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

test:
	swiftc $(TEST_SOURCES) \
		-sdk $(SDK) -target $(TARGET) \
		-framework Foundation \
		-o /tmp/PRNotifyTests
	/tmp/PRNotifyTests

dmg: build
	rm -f PRNotify-$(VERSION).dmg
	create-dmg \
		--volname "PRNotify" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "PRNotify.app" 175 190 \
		--hide-extension "PRNotify.app" \
		--app-drop-link 425 190 \
		"PRNotify-$(VERSION).dmg" \
		"PRNotify.app"
	@echo "Created PRNotify-$(VERSION).dmg"

clean:
	rm -rf $(APP) /tmp/PRNotifyTests PRNotify-*.dmg

run: build
	pkill -x PRNotify 2>/dev/null; $(BINARY) &
