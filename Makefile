export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: run run-macos build-macos build-release analyze test verify-all launch

run:
	flutter run

run-macos:
	flutter run -d macos

build-macos:
	flutter build macos --debug

build-release:
	flutter build macos --release

launch:
	open build/macos/Build/Products/Debug/Sqliter.app

analyze:
	flutter analyze

test:
	flutter test test/database_service_test.dart test/ui_test.dart test/home_persistence_test.dart test/exporter_test.dart test/dataflare_feature_flow_test.dart test/heavy_database_interactive_test.dart test/heavy_ui_e2e_test.dart

verify-all: analyze test build-macos
	@echo "All checks passed!"
