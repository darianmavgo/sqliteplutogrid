# UpdatesFeb20.md — Sqliter Feature Updates

A prioritized list of changes, files affected, and test strategies.

---

## 1. Column Header Separator Auto-Fit
**Goal:** Double-clicking column header separator resizes to fit content (like Google Sheets).

**Root Cause:** `TrinaGrid` has `enableColumnBorderDrag` defaulting to resize-only, but auto-fit on double-click requires `onColumnDoubleTap` wired to `stateManager.autoFitColumn(column)`.

**Files:**
- `lib/widgets/database_grid_view.dart` — add `onColumnDoubleTap` callback that calls `stateManager.autoFitColumn(event.column)`.
- `lib/theme/sqliter_theme.dart` — ensure `enableColumnBorderDrag: true` in `TrinaGridConfiguration`.

**Test:** `integration_test/column_autofit_test.dart`
- Load a database, tap a column header separator twice, assert column width equals max content width.

---

## 2. Gap Between Window Sizing Buttons and Tangerine
**Goal:** Add a small (e.g. 8px) horizontal gap between the traffic lights (window sizing buttons) and the 🍊 leading icon.

**Files:**
- `lib/widgets/banquet_bar.dart` — wrap `leading` `MacosIconButton` with a `Padding(padding: EdgeInsets.only(left: 8))`.

**Test:** Widget test asserting the leading widget has left padding > 0.

---

## 3. Platform Menu Bar — URL-Based Folder Menu
**Goal:** When a URL is in the path bar, generate a submenu in `PlatformMenuBar` with each path segment navigable. Cap at 10 levels. Sort longest→shortest.

**Logic:**
1. Split `_pathController.text` by `/` (or `;` for banquet paths).
2. Build cumulative path segments: `["a", "a/b", "a/b/c", ...]`.
3. Sort by length descending. Take first 10.
4. Render each as a `PlatformMenuItem` that calls `_loadPath(pathOverride: segment)`.

**Files:**
- `lib/main.dart` — replace the existing `if (_pathController.text.isNotEmpty) PlatformMenu(...)` block with the new segment-based menu builder.

**Test:** Unit test for the segment-building function using a known path.

---

## 4. Remove `<>` Characters from Column Headers
**Goal:** Strip `<` and `>` from column titles before they display.

**Root Cause:** `trina_grid` adds `<` and `>` around the sort icon area in column headers when no custom renderer is set.

**Fix Option A (preferred):** In `_loadTableMetadata` and `_optimizeColumns` in `main.dart`, strip `<` and `>` from column `title` strings.
**Fix Option B:** In `TrinaGridStyleConfig`, set `columnTextStyle` to use a `TextDecoration.none` and override `defaultColumnTitlePadding` with some trailing space so the icon doesn't clip into the text region.

**Files:**
- `lib/main.dart` — sanitize column titles: `title: colName.replaceAll('<', '').replaceAll('>', '')`.
- Alternatively, set a zero-width `\u200b` (zero-width space) suffix to push icons clear of the title text.

**Test:** Widget test asserting no `<` or `>` in rendered column header text.

---

## 5. Clickable Column Headers for Sorting
**Goal:** Single-click on a column header toggles sort ascending/descending (like a spreadsheet).

**TrinaGrid support:** `TrinaGrid` supports sorting natively when `enableSorting: true` is set on each `TrinaColumn` and the `sortType` is set.

**Files:**
- `lib/main.dart` — in `_loadTableMetadata` and `_optimizeColumns`, set `enableSorting: true` on each `TrinaColumn`.
- `lib/theme/sqliter_theme.dart` — ensure the `TrinaGridConfiguration` does not disable sorting globally.
- For server-side sort (optional follow-up): wire `onSorted` callback on `TrinaGrid` to call `_dbService.fetchRows` with an `ORDER BY` clause.

**Test:** Integration test: load a table, click a column header, assert rows are reordered.

---

## 6. Auto-Size All Columns After First 100 Rows Load
**Goal:** Once the first page (≤100 rows) arrives or data stops arriving, call `autoFitColumn` on every column.

**Implementation:**
1. In `DatabaseGridView`, hold a `TrinaGridStateManager?` reference via the `onLoaded` callback.
2. After `TrinaLazyPagination`'s `fetch` returns for page 1, post a `WidgetsBinding.instance.addPostFrameCallback` that calls `stateManager.autoFitColumn(col)` for each column.

**Files:**
- `lib/widgets/database_grid_view.dart` — capture `stateManager` in `onLoaded`, run auto-fit post frame after first fetch.

**Test:** Integration test asserting that after initial load, no column is at its default width of 100px.

---

## 7. Add Tangerine UTF-8 Character to App Name
**Goal:** Rename the app from "Sqliter" / empty display name to "🍊 Sqliter".

**Files:**
- `macos/Runner/Info.plist` — change `CFBundleDisplayName` from `🍋` to `🍊 Sqliter`.
- `pubspec.yaml` — update `name` or add a `display_name` comment for tracking.

**Test:** Shell check: `grep -A1 CFBundleDisplayName macos/Runner/Info.plist | grep '🍊'`.

---

## 8. Clickable URLs / SQLite File Paths in Cells
**Goal:**
- If a cell value is a URL (`http://` / `https://`), make it clickable → opens in default browser.
- If a cell value ends in `.sqlite`, `.sqlite3`, or `.db`, clicking it opens the file in the banquet bar.
- Otherwise, no change.

**Files:**
- `lib/widgets/database_grid_view.dart` — add a `cellRenderer` on `TrinaColumn` that detects URL/path and wraps in a `GestureDetector` + `MouseRegion(cursor: SystemMouseCursors.click)`.
- Create `lib/utils/cell_link_renderer.dart` — a helper `Widget buildCellWidget(String value, VoidCallback? onNavigate)` that handles the three cases.
- `lib/main.dart` — pass an `onNavigate` callback down to `DatabaseGridView` so cell clicks can call `_loadPath`.

**Test:** Widget test rendering a cell with `https://example.com` and asserting the `GestureDetector` is present and invokes the URL launcher.

---

## Cross-Cutting Test Plan

| Feature | Test File | Test Type |
|---|---|---|
| Column auto-fit on separator double-click | `integration_test/column_autofit_test.dart` | Integration |
| Gap between traffic lights & 🍊 | `test/widget/banquet_bar_test.dart` | Widget |
| URL-based platform menu | `test/unit/path_menu_builder_test.dart` | Unit |
| No `<>` in headers | `test/widget/grid_header_test.dart` | Widget |
| Column header sort | `integration_test/column_sort_test.dart` | Integration |
| Auto-size after first page | `integration_test/column_autosize_test.dart` | Integration |
| App display name | `test/shell/info_plist_check.sh` | Shell |
| Cell URL clickability | `test/widget/cell_link_test.dart` | Widget |

---

## Execution Order (Recommended)

1. **#7** App name (trivial, no risk)
2. **#2** Tangerine gap (trivial, no risk)
3. **#4** Remove `<>` from headers
4. **#5** Column sort (enable flag)
5. **#6** Auto-size after load (requires stateManager capture)
6. **#1** Column separator double-click auto-fit (builds on #5/#6)
7. **#3** Platform menu URL segments
8. **#8** Cell URL/path clickability (most complex — new widget + utils)
