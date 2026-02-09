# Project Dependencies (pubspec.yaml)

This document summarizes the external dependencies used in the SQLiter project and their purpose within the codebase.

## Core Dependencies

| Dependency | Purpose | Key Usage |
| :--- | :--- | :--- |
| **flutter** | The core Flutter SDK. | Provides the application framework and Material/Cupertino widgets. |
| **cupertino_icons** | iOS-style icons. | Used for various UI elements throughout the application. |

## UI & Styling

| Dependency | Purpose | Key Usage |
| :--- | :--- | :--- |
| **macos_ui** | Native macOS design system for Flutter. | Provides the `MacosApp` container, toolbar, and Apple-styled widgets. |
| **trina_grid** | High-performance data grid. | Powers the `DatabaseGridView` for displaying large SQLite table results efficiently with pagination. |
| **window_manager** | Desktop window management. | Used in `main.dart` to configure window size, title bar style (hidden), and initial positioning. |

## Backend & Networking

| Dependency | Purpose | Key Usage |
| :--- | :--- | :--- |
| **pocketbase** | Client library for PocketBase. | powers `FlightService` to interact with the backend for banquet links and query styles. |
| **http** | Composable HTTP client. | Used in `FlightService` for raw API calls to the Flight3 server (`/sqliter/rows`, etc.). |

## Database & Storage

| Dependency | Purpose | Key Usage |
| :--- | :--- | :--- |
| **sqflite_common_ffi** | SQLite FFI for desktop/server. | Powers `DatabaseService` to interact with local SQLite databases on macOS. |
| **path** | File path manipulation. | Utility for handling file and directory paths across different platforms. |
| **path_provider** | Platform-agnostic file system paths. | Used to find standard locations for storing data (temp, application documents). |
| **shared_preferences** | Key-value storage. | Typically used for persisting user settings or small state fragments. |

## Development Dependencies

- **flutter_test**: The testing framework for Flutter applications.
- **flutter_lints**: Recommended linting rules to encourage good coding practices.
