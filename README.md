# sqliter

A robust Flutter-based SQLite database viewer and Flight3 client, designed with a native MacOS feel.

## Features

### 🖥️ Native MacOS Experience
- **MacOS UI**: Built using `macos_ui` to provide a seamless, native look and feel on MacOS.
- **Window Management**: Custom window configuration with hidden title bar and transparent background support.
- **Platform Integration**: Native menu bar integration with File and View menus.

### 🗄️ Database Management
- **Local SQLite Support**: Open and view `.db` and `.sqlite` files directly from your local file system.
- **FFI Powered**: Uses `sqflite_common_ffi` for high-performance database operations on desktop.
- **Power2 Analysis**: Unique feature to sample rows at indices that are powers of 2 (1, 2, 4, 8, etc.) for quick data spot-checking.

### 📊 Data Visualization
- **High-Performance Grid**: Utilizes `trina_grid` to render large datasets efficiently.
- **Smart Formatting**: Automatically detects and formats:
  - Unix permissions (displayed as `rwxr-xr-x`)
  - Timestamps (converted to readable dates/times)
- **Column Optimization**: Automatically adjusts column widths based on content for optimal readability during initial load.

### ☁️ Flight3 Integration
- **Remote Access**: Connects to a Flight3 server (PocketBase backend) to access shared datasets.
- **Banquet Links**: Browse "Banquet" links—curated lists of datasets served by Flight3.
- **Sync & Offline**: Capability to sync remote "banquet" paths for local viewing.
- **Smart Breadcrumbs**: Interactive breadcrumb navigation bar that validates paths against the server, providing clickable segments for easy traversal.

---

## File Structure

### `lib/`
The core application code.

- **`main.dart`**
  The entry point of the application. It initializes the window manager, FFI for SQLite, and runs the `MacosApp`. It contains the main `DBViewerPage` widget which handles state, navigation, and top-level UI layout.

- **`db_service.dart`**
  Handles all interactions with local SQLite databases.
  - Connects to database files.
  - Queries metadata (tables, user version).
  - Fetches and counts rows.
  - Executes raw queries for the Power2 analysis.

- **`flight_service.dart`**
  Manages communication with the Flight3 server (PocketBase).
  - Handles authentication (Superuser/User fallback).
  - Fetches "Banquet" links and data.
  - proxies file system calls (syncing, downloading) via HTTP.

### `lib/models/`
Data models and enums.

- **`view_mode.dart`**
  Defines the `ViewMode` enum (`database` or `flight`), used to switch between the local database grid and the remote banquet list view.

### `lib/utils/`
Helper utilities for the application.

- **`formatters.dart`**
  Static methods for data formatting.
  - `formatPermissions`: Converts integer modes to Unix permission strings.
  - `formatDate` / `formatTime`: Converts timestamps to readable strings.
  - `getConverterEmoji`: Returns a specific fruit emoji based on the database version/type.

- **`path_validator.dart`**
  Helper class that communicates with the Flight3 API to validate file paths. It generates user-friendly error messages and identifies valid path segments for the breadcrumb navigation.

### `lib/widgets/`
Reusable UI components.

- **`app_toolbar.dart`**
  The top application toolbar. It integrates the breadcrumb field, navigation buttons, connection status, and database-specific actions (dropdowns, exports, analysis tools).

- **`breadcrumb_path_field.dart`**
  A sophisticated text field that parses file paths into interactive breadcrumb segments. It supports both editing (as text) and navigation (clicking on path segments).

- **`database_grid_view.dart`**
  Wraps the `TrinaGrid` to display database content. It handles dynamic column generation, infinite scrolling/fetching of rows, and displays a stats header with row counts.

- **`flight_banquet_view.dart`**
  Displays the list of available "Banquet" datasets from the Flight3 server. It renders a grid of paths and descriptions, allowing users to double-click to open a remote dataset.

### `test/`
Unit and widget tests.

- **`ui_test.dart`**
  Contains widget tests for the app's launch sequence, basic UI structure, and interactions within the tool bar (e.g., verifying buttons appear and mode switching works).

- **`ui_golden_test.dart`**
  Performs golden image tests to ensure the visual integrity of the app across changes. It verifies that the `FlightBanquetView` and `MacosApp` shell render correctly in dark mode.
