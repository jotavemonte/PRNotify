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

.PHONY: build clean run test

build:
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc $(SOURCES) \
		-sdk $(SDK) -target $(TARGET) \
		-framework AppKit -framework UserNotifications -framework ServiceManagement \
		-O -o $(BINARY)
	cp PRNotify/PRNotify-Info.plist $(PLIST)
	cp PRNotify/Assets/menubar-icon.svg $(RESOURCES)/
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

test:
	swiftc $(TEST_SOURCES) \
		-sdk $(SDK) -target $(TARGET) \
		-framework Foundation \
		-o /tmp/PRNotifyTests
	/tmp/PRNotifyTests

clean:
	rm -rf $(APP) /tmp/PRNotifyTests


run: build
	pkill -x PRNotify 2>/dev/null; $(BINARY) &
