APP_NAME := Sqliter
BUILD_DIR := build/macos/Build/Products/Release
INSTALL_DIR := /Applications

.PHONY: all build install clean run deps

all: install

deps:
	flutter pub get

build: deps
	@echo "Building $(APP_NAME) for macOS..."
	flutter build macos --release

install: build
	@echo "Installing $(APP_NAME) to $(INSTALL_DIR)..."
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -r "$(BUILD_DIR)/$(APP_NAME).app" "$(INSTALL_DIR)/"
	@echo "Installation complete!"

run:
	flutter run -d macos

clean:
	flutter clean
