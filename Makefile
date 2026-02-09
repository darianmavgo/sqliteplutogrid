.PHONY: run run-macos build-macos analyze test verify-all

run:
	flutter run

run-macos:
	flutter run -d macos

build-macos:
	flutter build macos --debug

analyze:
	flutter analyze

test:
	flutter test

verify-all: analyze test build-macos
	@echo "All checks passed!"
