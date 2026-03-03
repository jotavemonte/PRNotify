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

.PHONY: build clean run

build:
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc $(SOURCES) \
		-sdk $(SDK) -target $(TARGET) \
		-framework AppKit -framework UserNotifications -framework ServiceManagement \
		-O -o $(BINARY)
	cp PRNotify/PRNotify-Info.plist $(PLIST)
	cp PRNotify/Assets/menubar-icon.svg $(RESOURCES)/
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	@echo "Built $(APP)"

clean:
	rm -rf $(APP)


run: build
	pkill -x PRNotify 2>/dev/null; $(BINARY) &
