# SQLiter Client Design Document

## 1. Overview
SQLiter is a standalone Flutter application designed for macOS (and potentially other desktop platforms) that serves as a high-performance viewer for SQLite databases and a companion client for the **Flight3** server. It focuses on a clean, native experience using `macos_ui` and efficient data rendering with `trina_grid`.

## 2. Architecture & Design Principles

### 2.1 Core Philosophy
*   **Separation of Concerns**: SQLiter handles UI, local file access, and grid rendering. Heavy lifting (file conversion, remote synchronization) is delegated to the **Flight3** backend.
*   **Native Look & Feel**: Utilizes `macos_ui` components to adhere to macOS design guidelines (native toolbars, buttons, typography).
*   **Direct SQLite Access**: Uses `sqflite_common_ffi` for direct, high-performance access to local SQLite files without an intermediate server for local operations.

### 2.2 System Architecture
```mermaid
graph TD
    User[User Interface] -->|Interact| MB[MacosWindow / UI]
    MB -->|View DB| DBService[DatabaseService (sqflite_ffi)]
    MB -->|View Remote| FService[FlightService (HTTP)]
    MB -->|Browse Files| FBS[FileBrowserService]
    
    DBService -->|Read| LocalDB[(Local .db File)]
    FService -->|API Calls| Flight3[Flight3 Server]
    
    Flight3 -->|Serve Banquet| RemoteData[Banquet Data]
    Flight3 -->|Convert Files| Converters[mksqlite]
```

## 3. Core Features

### 3.1 Home Dashboard
The entry point of the application, featuring:
*   **Recent Files**: A persistent list of recently opened databases for quick access.
*   **Connection Status**: Visual indicator of the connection to the Flight3 server.
*   **Quick Actions**: Buttons to open local files or connect to a Flight server.

### 3.2 Database Viewer
The primary interface for exploring data, powered by `TrinaGrid`.
*   **Data Grid**: supporting sorting, resizing, and custom cell rendering.
*   **Pagination**:
    *   **Hybrid Infinite Scroll**: Automatically loads more rows as the user scrolls.
    *   **Header Stats**: Displays total row count, loaded count, and file size.
    *   **Jump to Row**: specific dialog to navigate large datasets.
*   **Table Navigation**: Sidebar or dropdown to switch between tables in a database.

### 3.3 Protocol: Banquet & Flight3
SQLiter integrates with the **Banquet** protocol via Flight3:
*   **Banquet Links**: The app can parse URLs (via Flight3 API) to render remote datasets as if they were local tables.
*   **Data Fetching**: Uses `FlightService` to fetch paginated JSON data from Flight3 for remote views.

### 3.4 File Browser & Conversion
*   **Integrated Browser**: Navigate the local file system within the app.
*   **Smart Conversion**: When a user attempts to open a non-SQLite file (CSV, JSON, Excel), SQLiter:
    1.  Detects the file type.
    2.  Uploads it to Flight3 (`/api/convert`).
    3.  Receives a converted `.db` file.
    4.  Caches it locally and opens it seamlessly.

## 4. Technical Implementation

### 4.1 Key Services
*   **`DatabaseService`**: Manages `sqflite` connections, executes queries (`getTables`, `countRows`, `fetchRows`).
*   **`FlightService`**: Handles HTTP communication with Flight3, authentication, and Banquet data fetching.
*   **`RecentFilesService`**: Persists file history using `shared_preferences`.
*   **`ConversionService`**: Orchestrates the upload-convert-download workflow with Flight3.

### 4.2 Data Models
*   **`TrinaRow` / `TrinaColumn`**: UI models for the grid.
*   **`RecordModel`**: Data structure for rows fetched from PocketBase/Flight3.
*   **`RecentFile`**: Metadata for history tracking.

### 4.3 Testing Strategy
*   **Widget Tests**: `ui_test.dart` covers App Launch, Client-side interactions (toolbar), and Flight Mode switching using mocked services.
*   **Manual Mocks**: `MockFlightService`, `MockDatabaseService` are used to isolate UI tests from backend dependencies.

## 5. User Interface (UX)
*   **Theming**: Dark mode by default, consistent with developer tools.
*   **Icons**: Uses `CupertinoIcons` and the signature 🔥 Flame emoji for branding.
*   **Window Management**: optimized for Desktop sizing (min width/height checks).
*   **Banquet Bar makes each breadcrumb clickable and navigatable**
*   **Banquet Bar shows full location of the table displayed in the grid**
*   **Banquet Bar shows full location of the table displayed in the grid**
*   **No UI clutter like sidebar of nav.  That belongs in the menu bar**
*   **Stats about the data set inline with banquet bar.      Total rows, loaded rows, file size, etc**
*   **Clean out **

## 6. Future Roadmap (from Proposal)
*   **Advanced Filtering**: SQL-like filter builder in the UI.
*   **Export**: Built-in CSV export for current views.
*   **Saved Queries**: Persisting user-defined SQL queries.
*   **Cached Datasets View**: Manager for downloaded/converted databases.


## 7. Todo
* Clean out the UI. 
* Make each banquet bar breadcrumb hilitr on hover. 
* Change to single click to navigate to that banquet url subset.
* Remove separate column for folder emoji. Instead prefix folder name with folder emoji.
* Banquet bar nav is failing on <enter>.  Fix that. 
* ~ fails to show ~ folder and shows duplicat ~ symbol. fix that. 
* In desktop mode, when a banquet url is for a folder send the request to flight3 and have it render the corresponding sqlite that is a filesystem conversion 
* Replace the Flutter logo with the Flame logo. 
* Keep Permission values displayed human readable.
* Change dates to yyyy-mm-dd format. Times hh:mm:ss format.
* 
Make a table in pocketbase called query style.
style_name | default_limit | default_offset | default_sort | default_filter | default_columns | default_group_by
sqlite | 200 | 0 | path | 
What's the best way to invent a non-null style? 
Peak at the first 200 records.  Remove any columns that are null.  
Calculate column width that fits tight to 98% of column values.

Use the sqlite metadata to choose a query style. 

For every existing converter in mksqlite, pick a fruit emoji to be the user_version in the sqlite metadata.
 
Experiment:
Power2 Sample 
Pull rowid 2^0, 2^1, ..., 2^9 and see what you can learn from the dataset 

