# Jyra

Jyra is a native macOS SwiftUI dashboard for Jira. It connects to a Jira Cloud instance with an API token, lets you build dashboards made up of widgets, and pulls live data from Jira Agile and Jira REST APIs.

The app is currently focused on three widget types:

- `Velocity`: completed vs committed points across recent sprints, with average velocity, completion rate, and predicted capacity
- `Burndown`: sprint burndown for the active or selected sprint
- `Project Burn Rate`: scope-based burn-up projection for selected epics or parent issues

## How The App Works

At launch, [JyraApp.swift](./Jyra/JyraApp.swift) creates a `ConfigService`, a `MetricsStore`, a `JiraDataCache`, and a `NetworkLogger`, and injects all of them into the SwiftUI environment.

- If Jira credentials are not configured, [ContentView.swift](./Jyra/ContentView.swift) shows [SetupView.swift](./Jyra/Views/Setup/SetupView.swift).
- If credentials exist, it shows [DashboardView.swift](./Jyra/Views/Dashboard/DashboardView.swift).

The basic runtime flow is:

1. User enters Jira URL, email, and API token.
2. `ConfigService` stores the token in Keychain and the non-secret fields in `UserDefaults`.
3. `DashboardService` loads dashboards from disk.
4. Each widget checks `JiraDataCache` before fetching. On a cache miss it calls `JiraService`, stores the result, and publishes metrics to `MetricsStore`.

## Project Structure

`Jyra/Models`

- `AppConfig.swift`: Jira connection settings and auth header generation
- `DashboardModels.swift`: dashboards, widgets, and widget config payloads
- `JiraModels.swift`: decoded Jira API response shapes and derived chart models

`Jyra/Services`

- `ConfigService.swift`: persists Jira credentials
- `DashboardService.swift`: persists dashboards and widgets
- `JiraService.swift`: all Jira HTTP calls and widget data shaping; instruments every request through `NetworkLogger`
- `JiraDataCache.swift`: in-memory response cache with a 5-minute TTL and per-widget force-refresh
- `MetricsStore.swift`: collects widget metrics and aggregates them by widget type for the dashboard summary section
- `NetworkLogger.swift`: captures every Jira HTTP request and response for the in-app debug panel and Xcode console

`Jyra/Views`

- `Setup/`: first-run Jira connection flow
- `Dashboard/`: dashboard list, widget containers, add-widget sheet
- `Widgets/`: individual widget views and configuration form
- `Shared/`: reusable search controls for boards, fields, and issues
- `NetworkLogView.swift`: the in-app HTTP inspector opened from `Debug → Network Log…`

## Persistence

### Jira Credentials

[ConfigService.swift](./Jyra/Services/ConfigService.swift) stores:

- Jira URL in `UserDefaults`
- Jira email in `UserDefaults`
- Jira API token in the macOS Keychain

`AppConfig.authHeader` generates the Basic auth header from `email:apiKey`.

### Dashboards

[DashboardService.swift](./Jyra/Services/DashboardService.swift) stores dashboards in:

`~/Library/Application Support/Jyra/dashboards.json`

Each dashboard contains widgets, and each widget stores a typed `WidgetConfig` payload.

## Jira Integration

All Jira access goes through [JiraService.swift](./Jyra/Services/JiraService.swift).

### Endpoints Used

- `/rest/api/3/myself`
- `/rest/api/3/field`
- `/rest/api/3/search`
- `/rest/api/3/search/jql`
- `/rest/api/3/issue/picker`
- `/rest/agile/1.0/board`
- `/rest/agile/1.0/board/{id}/sprint`
- `/rest/agile/1.0/board/{id}/sprint/{id}/issue`
- `/rest/greenhopper/1.0/rapid/charts/velocity`

### Velocity Fetching

Velocity uses the older Greenhopper endpoint. Jira may return sprint data incrementally behind a `transactionId`, so Jyra keeps calling the velocity endpoint until it stops receiving new sprint entries, then merges the results into one velocity dataset.

That logic lives in `JiraService`: `fetchVelocity`, `fetchVelocityPage`, `fetchVelocityEntries`.

### Story Point / Estimate Field Handling

Burndown and Project Burn Rate both need a Jira field that represents estimates. Jira custom fields vary per instance, so Jyra treats the selected field as dynamic and injects it during decode instead of hardcoding a single field id.

When a widget is first added and no points field has been selected yet, `JiraService` calls `fetchPreferredPointsField()` to auto-detect the best match from the instance's field list (looks for "Story Points" first, then any field containing "story point", then "point estimate"). The result is cached for the session.

## Widget Data Caching

[JiraDataCache.swift](./Jyra/Services/JiraDataCache.swift) sits between each widget view and `JiraService`. It prevents redundant network calls when the SwiftUI view tree rebuilds (e.g. after a scroll) and keeps the dashboard fast after the first load.

**Cache TTL**: 5 minutes per widget entry. After TTL expiry the next widget appearance triggers a fresh fetch.

**Cache keys**: each entry is keyed by `widgetId + config parameters`, so changing a widget's board or sprint selection automatically bypasses the stale entry.

**Force refresh**: the `↺` button in every widget header immediately evicts that widget's cache and re-fetches. The widget shows its normal loading state during the refresh.

**Implementation**: `JiraDataCache` is an `@Observable` class stored in the SwiftUI environment. It exposes `refreshVersion(for:)` (a per-widget integer that bumps on force-refresh) which widgets pass as their `.task(id:)` parameter so SwiftUI knows when to rerun the fetch.

## Dashboard Metrics

Each widget publishes a set of named metrics to [MetricsStore.swift](./Jyra/Services/MetricsStore.swift) after its data loads. At the bottom of every dashboard, a collapsible **Dashboard Metrics** section shows these metrics aggregated across all widgets:

| Widget type     | Metrics shown |
|-----------------|---------------|
| Velocity        | Avg Velocity (pts), Avg Completion (%) — averaged across all velocity widgets |
| Burndown        | Remaining (pts), % Complete — averaged across all burndown widgets |
| Project Burn Rate | Total Scope (pts), % Complete — averaged across all burn-rate widgets |

Averaging is performed only on metrics that have a numeric `rawValue`. The **Predicted Capacity** metric (calculated per velocity widget as a rolling 3-sprint average) is intentionally excluded from dashboard-level aggregation because team point scales are relative and averaging across teams produces a meaningless number. Predicted Capacity still appears in each individual velocity widget's summary row.

## Widget Types

### Velocity

Config: [DashboardModels.swift](./Jyra/Models/DashboardModels.swift) `VelocityConfig`

Inputs:

- board
- optional custom title

Behavior:

- fetches full velocity history for the board
- matches sprint metadata from the Agile sprint endpoint
- sprints with zero committed and zero completed points are excluded from the chart
- shows the most recent six sprints in the compact view, up to twelve in the expanded sheet
- active sprint appears on the far right; historical sprints run oldest-left to newest-right
- falls back to the board name when no custom title is set
- summary row shows average velocity, average completion %, and a predicted capacity (rolling 3-sprint average of completed points — intended for sprint planning reference within a single team)

Relevant files:

- [VelocityWidgetView.swift](./Jyra/Views/Widgets/VelocityWidgetView.swift)
- [WidgetConfigView.swift](./Jyra/Views/Widgets/WidgetConfigView.swift)

### Burndown

Config: `BurndownConfig`

Inputs:

- board
- sprint selection (`active` or a specific sprint)
- points field (optional — auto-detected if left blank)

Behavior:

- loads sprint issues from the Agile sprint issue API
- when no points field is configured, `JiraService` calls `fetchPreferredPointsField()` to auto-detect the best available estimate field for the Jira instance
- computes total points, completed points, ideal line, actual remaining, and simple linear projection
- requires sprint `startDate` and `endDate` to be set in Jira; missing dates produce a `missingSprintDates` error

Relevant files:

- [BurndownWidgetView.swift](./Jyra/Views/Widgets/BurndownWidgetView.swift)
- [JiraService.swift](./Jyra/Services/JiraService.swift)

### Project Burn Rate

Config: `ProjectBurnRateConfig`

Inputs:

- project name
- parent issues / epics (searched via Jira issue picker)
- per-epic estimate field (each epic can use a different Jira custom field for points)

Behavior:

- fetches child stories for all selected epics using `parent in (...)` JQL; falls back to `"Epic Link" in (...)` for classic projects
- each epic can have its own estimate field configured — the widget collects all configured field IDs, requests them all in a single JQL query, and uses the first non-nil value found per issue
- groups child issues by sprint, computes cumulative completed points, and plots a burn-up chart
- unsprinted issues appear as a "Backlog" bucket at the right edge of the chart

Story field picker:

When configuring scope issues in `IssueSearchField`, each selected epic shows a small **field picker** below its summary. An orange badge on the picker means no field has been selected for that epic yet; the badge turns grey once a field is chosen. Available choices come from the full Jira field list filtered to names containing "point" or "story".

Relevant files:

- [ProjectBurnRateWidgetView.swift](./Jyra/Views/Widgets/ProjectBurnRateWidgetView.swift)
- [IssueSearchField.swift](./Jyra/Views/Shared/IssueSearchField.swift)
- [FieldSearchField.swift](./Jyra/Views/Shared/FieldSearchField.swift)

## Widget Layout

### Drag-and-Drop Reordering

Widgets on a dashboard can be reordered by dragging. The drag handle (three-line icon in the widget header) signals the draggable area, but a drag initiated anywhere on the widget card works. The dragged widget fades to 40% opacity while in flight; on drop the order is persisted immediately.

Implementation: [WidgetContainerView.swift](./Jyra/Views/Dashboard/WidgetContainerView.swift) — `WidgetDropDelegate` (conforms to `DropDelegate`) + `.onDrag`/`.onDrop` on each widget card.

### Resize Handle

Each widget card has a thin resize strip at the bottom. Drag it up or down to adjust the widget's height. The cursor changes to a vertical resize cursor on hover.

- Minimum height: 160 pt
- Default height when no resize has been applied: 260 pt
- The chosen height is stored in `Widget.customHeight` and persisted to `dashboards.json`

### Widget Header

Each widget card header contains:

- a drag handle icon (left)
- the widget title and type icon
- a **↺ refresh button** — forces an immediate re-fetch, bypassing the cache
- a **⋯ menu** — opens the configuration sheet or deletes the widget

## Widget Configuration UX

[WidgetConfigView.swift](./Jyra/Views/Widgets/WidgetConfigView.swift) is the central editor for widget settings.

Search controls:

- [BoardSearchField.swift](./Jyra/Views/Shared/BoardSearchField.swift): board lookup via Jira Agile board search
- [FieldSearchField.swift](./Jyra/Views/Shared/FieldSearchField.swift): local search over Jira fields already fetched from `/field`
- [IssueSearchField.swift](./Jyra/Views/Shared/IssueSearchField.swift): live search via Jira issue picker; includes a per-epic estimate field picker for Project Burn Rate widgets

## Building And Running

Requirements:

- macOS 15+
- Xcode 16+ (Xcode 26 tested)
- Swift 6

Open the project:

```bash
open Jyra.xcodeproj
```

Build from the command line:

```bash
xcodebuild -scheme Jyra -destination 'platform=macOS' build
```

## Xcode Schemes

| Scheme | Purpose |
|--------|---------|
| `Jyra` | Standard build against your real Jira instance |
| `Jyra (Debug)` | Same as `Jyra` but sets `JYRA_DEBUG_NETWORK=1`, enabling full network logging |
| `Jyra (Mock)` | Starts the local mock server, sets `JYRA_MOCK_URL`, and enables network logging |

## First-Run Setup

When the app starts without credentials:

1. Enter your Jira base URL, for example `https://your-org.atlassian.net`
2. Enter the Jira account email
3. Enter an API token
4. Click `Test Connection`
5. Click `Save & Continue`

You can later update or clear the connection from Settings.

## Network Debugging

Jyra has a built-in HTTP inspector. It captures every request made through `JiraService` — URL, method, HTTP status, response time, and the full pretty-printed JSON body.

### Enabling Logging

**Via scheme** (recommended): run the app under **Jyra (Debug)** or **Jyra (Mock)**. Both schemes set `JYRA_DEBUG_NETWORK=1` in the launch environment, which enables logging automatically on startup.

**At runtime**: open the Network Log panel and toggle **Logging** on with the switch in the toolbar. Requests made after the toggle are captured; earlier requests are not.

### Opening The Panel

- Menu bar: **Debug → Network Log…**
- Keyboard shortcut: **⌘⇧L**

The panel opens as a sheet over the main window.

### What The Panel Shows

The left column is a table of all captured requests, sorted newest-first:

| Column | Contents |
|--------|----------|
| status dot | green = 2xx, orange = 4xx, red = 5xx or connection error |
| Method | HTTP method |
| Status | HTTP status code, or `ERR` for transport failures |
| Path | URL path + query string |
| Duration | Time from request start to last byte received |
| Time | Wall-clock time of the request |

Click any row to see the full detail panel on the right:

- Request URL, method, status, and duration
- Error message (if any)
- Request body (shown for non-GET requests)
- Response body (pretty-printed JSON, truncated at 20 KB)

### Toolbar Controls

| Control | Action |
|---------|--------|
| Errors only | Filters the table to show only non-2xx responses and transport errors |
| Logging toggle | Enables or disables capture without restarting the app |
| Clear | Removes all entries from the panel |
| Search bar | Filters by URL substring |

### Console Logging

In addition to the panel, every request is printed to Xcode's debug console regardless of whether the panel is open:

```
[Network] GET 200 43ms   /rest/agile/1.0/board/101/sprint
[Network] GET 200 12ms   /rest/api/3/field
[Network] GET ERR  0ms   /rest/agile/1.0/board/999/sprint
```

This makes it easy to tail Jira traffic in the Xcode console while working on unrelated parts of the app.

## Local Development With The Mock Server

The repo includes a Node.js mock Jira server (zero npm dependencies) for developing and testing widgets without a real Jira instance.

### Starting The Server

```bash
bash mock-jira/start.sh
```

Runs on `http://localhost:3001`. Logs go to `/tmp/jyra-mock.log`.

```bash
bash mock-jira/stop.sh
```

### Xcode Integration

Select the **Jyra (Mock)** scheme in Xcode. It:

1. Runs `mock-jira/start.sh` before the app launches.
2. Sets `JYRA_MOCK_URL=http://localhost:3001`, which bypasses Keychain credential checks in `ConfigService`.
3. Sets `JYRA_DEBUG_NETWORK=1`, enabling the network log panel automatically.
4. Runs `mock-jira/stop.sh` when the app exits.

No Jira credentials or network access are required when running under this scheme.

### Mock Server Logging

The mock server logs every request to its terminal with color, response status, timing, and response size:

```
  GET 200  12ms      1.2KB  /rest/agile/1.0/board
  GET 200   8ms       432B  /rest/agile/1.0/board/102/sprint
  GET 404   1ms        43B  /rest/api/3/unknownpath
```

Green = 2xx, yellow = 4xx, red = 5xx.

### Mock Boards

| ID  | Name            | Description |
|-----|-----------------|-------------|
| 101 | Lone Wolf       | 1 closed sprint + 1 active. Minimal data for quick sanity checks. |
| 102 | Velocity Kings  | 12 closed sprints with wide variance: over-delivery (114%), a crash sprint (40%), and two perfect sprints (100%). Good for testing chart scaling and average lines. |
| 103 | Zero Gap        | 7 closed sprints where sprint 4 has 0 committed and 0 completed points. The velocity widget must filter this sprint out. |
| 104 | Steady Rhythms  | 5 closed sprints all completing at ~93–95%. Good for confirming a flat, consistent chart. |
| 201 | No-Dates Team   | Sprints with `null` `startDate` and `endDate`. Velocity widget works normally. Burndown widget shows the expected "missing sprint dates" error, confirming that error path. |

### Testing The Velocity Widget

Add a velocity widget and select any board from 101–201. Board 102 (Velocity Kings) gives the most coverage: over-delivery, under-delivery, and consistent tail sprints all appear in one 12-sprint view.

Board 103 (Zero Gap) verifies sprint exclusion — Sprint 4 must not appear in the chart or factor into the completion average.

### Testing The Burndown Widget

Add a burndown widget and select any board from 101–104. The points field can be left blank; the widget will auto-detect `story_points` from the mock field list. Issues across those boards have resolution dates spread across the past three days, producing a visible step-down curve rather than a single cliff drop.

Board 201 (No-Dates Team) should produce the "Sprint is missing start or end dates" error, which confirms the error path renders correctly.

### Testing The Project Burn Rate Widget

1. Add a Project Burn Rate widget.
2. In the **Scope** section, search for `JYRA` in the issue picker.
3. Select **JYRA-1** (the "Platform Modernization" epic). The mock server resolves its child stories via `parent in ("JYRA-1")`, returning 8 stories totalling **76 story points**.
4. Use the per-epic field picker that appears under JYRA-1 to select **Story Points** (`story_points`). The orange badge turns grey when a field is selected.
5. Save the widget. The burn-up chart shows cumulative completed points across three mock sprints.

Available scope issues:

| Key    | Summary                     | Points | Sprint |
|--------|-----------------------------|--------|--------|
| JYRA-1 | Platform Modernization      | —      | —      |
| JYRA-2 | Migrate auth to JWT         | 13     | Sprint 1 (closed) |
| JYRA-3 | API versioning support      | 8      | Sprint 1 (closed) |
| JYRA-4 | Database connection pooling | 5      | Sprint 2 (closed) |
| JYRA-5 | Redis caching layer         | 13     | Sprint 2 (closed) |
| JYRA-6 | Background job queue        | 8      | Sprint 3 (active) |
| JYRA-7 | Audit logging service       | 5      | Sprint 3 (active) |
| JYRA-8 | Deploy pipeline v2          | 21     | Backlog |
| JYRA-9 | Performance benchmarks      | 3      | Backlog |

## Current Assumptions And Limitations

- The app is designed for Jira Cloud-style REST endpoints.
- Project Burn Rate expands scope using direct issue keys and `parent in (...)`. If a Jira instance uses different parent-link semantics, additional JQL variants may be needed.
- Burndown requires sprint `startDate` and `endDate` to be populated in Jira.
- The network log panel captures up to 500 entries before dropping the oldest. It is intended for development and debugging — it is active in the Debug and Mock schemes only (controlled by `JYRA_DEBUG_NETWORK`).
- There are currently no automated tests in the repository.
- All state is local to the Mac; there is no backend or sync layer.
