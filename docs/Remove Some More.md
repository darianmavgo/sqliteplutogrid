
Remove:
- [x] **`view_mode.dart`**
  Defines the `ViewMode` enum (`database` or `flight`), used to switch between the local database grid and the remote banquet list view.
There aren't two views, just the database view that either shows local or remote fetched by flight. 

Remove most of :
- [x] **`app_toolbar.dart`**
  The top application toolbar. It integrates the breadcrumb field, navigation buttons, connection status, and database-specific actions (dropdowns, exports, analysis tools).
  and make the clear the bar for banquet urls that is breadcrumbs is called banquet bar. 
Remove everything that isn't the banquet bar.  Remove all nav buttons remove all stats, exports, and analysis tools
Remove entirely:
- [x] **`flight_banquet_view.dart`**
  Displays the list of available "Banquet" datasets from the Flight3 server. It renders a grid of paths and descriptions, allowing users to double-click to open a remote dataset.

