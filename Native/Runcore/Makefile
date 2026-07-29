SHELL := /bin/zsh

ROOT := $(abspath .)
FLUTTER_DIR := $(ROOT)/flutter
MACOS_DIR := $(FLUTTER_DIR)/macos
IOS_DIR := $(FLUTTER_DIR)/ios
MACOS_WORKSPACE := $(MACOS_DIR)/Runner.xcworkspace
MACOS_SCHEME := Runner
MACOS_DERIVED_DATA := $(ROOT)/.build/macos
MACOS_APP := $(MACOS_DERIVED_DATA)/Build/Products/Debug/Runcore.app
FRAMEWORKS_SCRIPT := $(ROOT)/flutter/native/apple/Frameworks/build.sh
IOS_SIM_NAME ?= iPhone 17

.DEFAULT_GOAL := macos-run

.PHONY: help macos-bootstrap macos-framework macos-pods macos-open macos-build macos-run ios-bootstrap ios-framework ios-pods ios-run ios go-run clean-flutter

help:
	@echo "Targets:"
	@echo "  make macos-bootstrap  # flutter pub get + pod install + build macOS libruncore"
	@echo "  make macos-open       # prepare macOS host and open Runner.xcworkspace in Xcode"
	@echo "  make macos-build      # build macOS app via xcodebuild into .build/macos"
	@echo "  make macos-run        # full flow: build app and open the built .app"
	@echo "  make ios-bootstrap    # flutter pub get + pod install + build iOS Runcore.xcframework"
	@echo "  make ios-run          # full flow: boot Simulator and run Flutter iOS app"
	@echo "  make ios              # alias for ios-run"
	@echo "  make go-run           # run standalone Go daemon"
	@echo "  make clean-flutter    # flutter clean"

macos-bootstrap: macos-framework
	cd $(FLUTTER_DIR) && flutter pub get
	cd $(MACOS_DIR) && pod install

macos-framework:
	cd $(ROOT)/flutter/native/apple/Frameworks && ./build.sh macos

ios-framework:
	cd $(ROOT)/flutter/native/apple/Frameworks && ./build.sh ios

macos-pods:
	cd $(FLUTTER_DIR) && flutter pub get
	cd $(MACOS_DIR) && pod install

ios-pods:
	cd $(FLUTTER_DIR) && flutter pub get
	cd $(IOS_DIR) && pod install

ios-bootstrap: ios-framework
	cd $(FLUTTER_DIR) && flutter pub get
	cd $(IOS_DIR) && pod install

macos-open: macos-bootstrap
	open $(MACOS_WORKSPACE)

macos-build: macos-bootstrap
	mkdir -p $(MACOS_DERIVED_DATA)
	xcodebuild -workspace $(MACOS_WORKSPACE) -scheme $(MACOS_SCHEME) -configuration Debug -derivedDataPath $(MACOS_DERIVED_DATA) build

macos-run: macos-build
	open $(MACOS_APP)

ios-run: ios-bootstrap
	open -a Simulator
	xcrun simctl boot "$(IOS_SIM_NAME)" || true
	cd $(FLUTTER_DIR) && flutter run -d "$$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/{print $$2; exit}')"

ios: ios-run

go-run:
	cd $(ROOT) && go run ./cmd/runcore

clean-flutter:
	cd $(FLUTTER_DIR) && flutter clean
