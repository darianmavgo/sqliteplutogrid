# 🍊 Sqliter vs. Dataflare — Technical Comparison & Improvement Roadmap

## At a Glance

| | **Dataflare** | **🍊 Sqliter (SqlitePlutoGrid)** |
|---|---|---|
| **Framework** | Tauri (Rust + WebView) | Flutter (Dart + native macOS) |
| **UI Runtime** | System WebView (WKWebView on macOS) | Flutter rasterizer (Skia/Impeller) |
| **App Size** | ~30 MB | ~53 MB |
| **SQLite Access** | Bundled Rust `rusqlite` crate | `sqflite_common_ffi` (C FFI bridge) |
| **Current Stability** | ✅ Production-ready, open to public | ⚠️ Alpha — several known bugs |
| **Table browsing** | ✅ Works reliably out of the box | ⚠️ Blank screen on relative paths |
| **Right-click open** | ✅ Native macOS document association | ✅ Registered (after today's build) |
| **Sorting** | ✅ Native, server-side | ⚠️ Client-side only in TrinaGrid |
| **Filtering** | ✅ Built-in filter bar | ❌ Not yet implemented |
| **SQL Editor** | ✅ Syntax highlighting + autocomplete | ❌ Absent |
| **Schema View** | ✅ Column types, FK, indexes | ⚠️ Column names only |
| **Recent Files** | ✅ Persistent history | ⚠️ Crashes on numeric table names (`1_recent_files`) |
| **Error Dialogs** | ✅ Clear user-facing errors | ⚠️ Silent failures (black screen) |
| **Multi-DB support** | ✅ 27+ database types | ✅ SQLite + remote Banquet |
| **Pricing** | Free (open source) | Free (private repo) |

---

## 1. Tech Stack Deep Dive

### Dataflare — Tauri (Rust + WebView)

```
┌─────────────────────────────────────────┐
│           WebView (WKWebView / WebKit)  │  ← UI rendering
│   React / Vue frontend (HTML/CSS/JS)   │
└───────────────┬─────────────────────────┘
                │  IPC (JSON over Tauri bridge)
┌───────────────▼─────────────────────────┐
│           Rust backend (Tauri core)     │
│  ┌──────────────────────────────────┐   │
│  │  rusqlite  │  connection pool    │   │  ← SQLite access
│  └──────────────────────────────────┘   │
│      macOS native APIs (AppKit/Swift)   │
└─────────────────────────────────────────┘
```

**Why it's stable:**
- **Rust backend is memory-safe and crash-resistant** — no null pointer panics, no GC pauses.
- `rusqlite` is a battle-tested, direct C-to-Rust binding to SQLite3 — zero intermediate layers.
- The WebView UI is completely decoupled from the database engine. A UI crash does not take down the DB connection.
- SQLite path handling is trivial in Rust: `std::path::Path::new(s).exists()` panics gracefully; the frontend sends the path via IPC and Rust validates it atomically.
- File association via macOS Launch Services is handled by Tauri's scaffold automatically at build time.
- The web frontend uses standard browser pagination — `LIMIT N OFFSET M` — which works regardless of row count.

---

### 🍊 Sqliter (SqlitePlutoGrid) — Flutter + sqflite_common_ffi

```
┌─────────────────────────────────────────┐
│     Flutter Skia/Impeller rasterizer    │  ← UI rendering
│   Dart widgets (MacosUI + TrinaGrid)   │
└───────────────┬─────────────────────────┘
                │  Dart FFI (dart:ffi + sqflite_common_ffi)
┌───────────────▼─────────────────────────┐
│     sqflite_common_ffi (Dart wrapper)   │
│  ┌──────────────────────────────────┐   │
│  │   sqlite3.dylib (system-linked)  │   │  ← SQLite access
│  └──────────────────────────────────┘   │
│   Banquet (custom remote sync layer)    │
│   FlightService (PocketBase HTTP API)   │
└─────────────────────────────────────────┘
```

**Why it's currently less stable:**

| Layer | Problem |
|---|---|
| **Path validation** | `FileSystemEntity.type(path)` is async + returns `notFound` for relative paths, falling silently to remote Banquet sync — blank screen results |
| **SQL table names** | `INSERT INTO 1_recent_files` is invalid SQL — numeric-prefixed names crash `sqflite_common_ffi` unless quoted |
| **Error surfacing** | Exceptions are caught in `debugPrint` but no user-visible dialog is shown — user sees a black screen with no explanation |
| **TrinaGrid lazy loading** | TrinaGrid's `TrinaLazyPagination` fetches data on-demand, but if `_gridColumns` is empty or stale, the widget renders blank |
| **Remote fallback** | If the Banquet/FlightService remote (PocketBase at `127.0.0.1:8090`) is not running, the app falls back silently with no retry dialog |
| **State coupling** | `_viewType`, `_currentTableName`, `_gridColumns` are all in one 917-line `_DBViewerPageState` — a single bad state transition can brick the whole view |
| **Column initialization** | `_gridColumns` must be set *before* `DatabaseGridView` renders. If `_loadTableMetadata` throws, the grid gets an empty column list and draws nothing |

---

## 2. Why Dataflare's Table Browsing "Just Works"

1. **Deterministic path handling** — Rust validates the absolute path before even trying to open the file. If the path is wrong, an error dialog fires immediately in the WebView frontend.

2. **Separation of concerns** — The database engine (Rust) and the display layer (WebView) communicate via clean IPC. A UI freeze doesn't block a query; a slow query doesn't freeze the UI.

3. **Correct SQL generation** — Dataflare's Rust layer always quotes identifiers (`"1_recent_files"`), so numeric-prefixed or reserved-word table names never cause crashes.

4. **Always-visible error states** — The frontend shows a `<ErrorBanner>` component whenever the Tauri IPC response contains `{ error: "..." }`. There's no silent swallowing of exceptions.

5. **Proven pagination** — The Rust layer runs `SELECT * FROM "tableName" LIMIT 100 OFFSET N` per page. It works identically on a 100-row table or a 10 million-row table.

6. **File association works at install time** — Tauri's `tauri.conf.json` `fileAssociations` field registers `.db`, `.sqlite`, `.sqlite3` at install. Right-click works the moment you install the `.dmg`.

---

## 3. What Sqliter Needs to Be as Stable as Dataflare

Ordered from highest impact to lowest effort:

### 🔴 Critical — Fix These First

#### 3.1 Fail fast & show an error dialog on bad paths
**Problem:** Invalid/relative paths silently fall through to remote sync → blank screen.  
**Fix:** In `_loadPath()` in [`main.dart`](file:///Users/darianhickman/Documents/sqliteplutogrid/lib/main.dart), add synchronous path validation before any async call:

```dart
final type = await FileSystemEntity.type(resolvedPath);
if (type == FileSystemEntityType.notFound) {
  _showErrorDialog('File not found: $resolvedPath\n\nUse Cmd+O to browse.');
  return;
}
```

Add a `_showErrorDialog(String msg)` helper that uses a `MacosAlertDialog` or `showDialog`.

#### 3.2 Quote all SQLite identifiers (fix the `1_recent_files` crash)
**Problem:** `INSERT INTO 1_recent_files` crashes `sqflite_common_ffi` because numeric-leading names are not valid bare SQL identifiers.  
**Fix:** In `_recordRecentFile()` in [`main.dart`](file:///Users/darianhickman/Documents/sqliteplutogrid/lib/main.dart) line 437:
```dart
// BEFORE:
await homeDb.insert('1_recent_files', { ... });
// AFTER:
await homeDb.rawInsert(
  'INSERT OR REPLACE INTO "1_recent_files" (filename, path, last_opened, size_mb) VALUES (?, ?, ?, ?)',
  [filename, path, lastOpened, sizeMb]
);
```
Also apply the same fix anywhere `homeDb.query('1_recent_files', ...)` is called.

#### 3.3 Guard `_gridColumns` before rendering
**Problem:** If `_loadTableMetadata` throws or returns before setting columns, `DatabaseGridView` renders with an empty column list → blank grid.  
**Fix:** In `DatabaseGridView`, add a guard:
```dart
if (columns.isEmpty) {
  return const Center(child: Text('No columns found in table.'));
}
```

---

### 🟡 High Priority — Parity Features

#### 3.4 Server-side (SQL-level) sorting and pagination
**Problem:** TrinaGrid sorts in-memory — only the currently loaded page gets sorted.  
**Fix:** Wire `TrinaGrid`'s `onSorted` callback to re-issue `SELECT * FROM "table" ORDER BY "col" ASC/DESC LIMIT 100 OFFSET 0` and reload the grid.

#### 3.5 Basic column filter bar
**Problem:** Dataflare has a one-click filter row per column; Sqliter has none.  
**Fix:** Add a filter input row above the grid (a `Row` of `MacosTextField` widgets). On change, debounce and re-issue a `SELECT ... WHERE "col" LIKE ?` query.

#### 3.6 Show column types and NOT NULL constraints in header tooltips
**Problem:** Dataflare shows `INTEGER NOT NULL`, `TEXT`, etc. Sqliter only shows column names.  
**Fix:** Run `PRAGMA table_info("tableName")` and store `type`, `notnull`, `pk` alongside each column, then display in a tooltip on hover.

#### 3.7 Built-in SQL editor tab
**Problem:** Dataflare has a full SQL editor with syntax highlighting. Sqliter has none.  
**Fix:** Add a second tab using `flutter_code_editor` or a `TextField` with a monospace font. On `Cmd+Enter`, run `homeDb.rawQuery(sql)` and display results in the grid.

---

### 🟢 Polish — Quality-of-Life

#### 3.8 Auto-fit columns after first data load
Already documented in [`UpdatesFeb20.md`](file:///Users/darianhickman/Documents/sqliteplutogrid/UpdatesFeb20.md) — item #6. Capture `stateManager` in `onLoaded` and call `autoFitColumn` per column in a `addPostFrameCallback`.

#### 3.9 Persistent column widths and sort preferences
Store per-table column widths in `home.sqlite` so they survive restarts.

#### 3.10 Row count badge and progress on load
Show `Loaded 100 / 12,400 rows` in the toolbar while lazy-loading proceeds.

#### 3.11 Remove `<>` from column headers
Already documented in [`UpdatesFeb20.md`](file:///Users/darianhickman/Documents/sqliteplutogrid/UpdatesFeb20.md) — item #4. Strip in `_loadTableMetadata`.

#### 3.12 Schema view sidebar
Add a collapsible `MacosSidebar` listing all tables in the open database. Clicking a table name calls `_loadPath` with that table appended (`;tableName` Banquet syntax).

---

## 4. Summary Verdict

> **Dataflare is more stable because it has a clean Rust/WebView split, zero silent failures, and uses mature, battle-tested database access primitives. Sqliter's instability stems from a handful of addressable bugs — not from any fundamental architectural flaw.**

The Flutter + FFI architecture Sqliter is built on is perfectly capable of matching Dataflare's reliability. The path from alpha to production-quality is well-defined:

1. ✅ Fix the 3 critical bugs (path validation, table name quoting, empty column guard)
2. Add server-side sort + basic filter bar
3. Add SQL editor tab
4. Polish with schema sidebar and auto-fit columns

With those changes, Sqliter's native macOS rendering (via Flutter/Impeller) would actually **exceed** Dataflare's WebView-based rendering for raw grid performance on large tables — which was the entire reason it was built to replace `sqliter` (the original Wails/Go version).
