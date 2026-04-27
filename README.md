# Jyra

Jyra is a native macOS SwiftUI app for Jira. It connects to a Jira Cloud instance with an API token and gives you four complementary views into your team's data:

**Dashboards** — build flexible dashboards made up of widgets that visualize team metrics:

- `Velocity`: completed vs committed points across recent sprints, with average velocity, completion rate, and predicted capacity
- `Burndown`: sprint burndown for the active or selected sprint
- `Project Burn Rate`: scope-based burn-up projection for selected epics or parent issues

**Boards** — live kanban/scrum board views with neon card UIs, configurable metric highlight rules, and click-to-expand story details

**Calibration** — per-engineer sprint metrics with grade-level normalization and relative workload ranking; optionally enriched with GitLab activity data

**Settings** — connection settings for Jira and GitLab, accessible via the **⚙ gear icon** in the sidebar or **⌘,** from anywhere in the app

## How The App Works

At launch, [JyraApp.swift](./Jyra/JyraApp.swift) creates a `ConfigService`, a `MetricsStore`, a `JiraDataCache`, a `BoardService`, a `CalibrationService`, and a `NetworkLogger`, and injects all of them into the SwiftUI environment.

- If Jira credentials are not configured, [ContentView.swift](./Jyra/ContentView.swift) shows [SetupView.swift](./Jyra/Views/Setup/SetupView.swift).
- If credentials exist, it shows [DashboardView.swift](./Jyra/Views/Dashboard/DashboardView.swift).

The basic runtime flow is:

1. User enters Jira URL, email, and API token in Settings.
2. `ConfigService` stores both tokens in the macOS Keychain and the non-secret fields in `UserDefaults`.
3. `DashboardService` loads dashboards from disk; `BoardService` and `CalibrationService` load their data from disk.
4. Each widget checks `JiraDataCache` before fetching. On a cache miss it calls `JiraService`, stores the result, and publishes metrics to `MetricsStore`. Board and calibration views follow the same cache pattern.

## Project Structure

`Jyra/Models`

- `AppConfig.swift`: Jira and GitLab connection settings and auth header generation
- `DashboardModels.swift`: dashboards, widgets, and widget config payloads
- `JiraModels.swift`: decoded Jira API response shapes and derived chart models
- `BoardModels.swift`: `Board`, `BoardIssue`, `BoardColumn`, `BoardMetricRule`, `RuleColor`, `BoardRuleField`, `BoardRuleOperator`
- `CalibrationModels.swift`: `CalibrationConfig`, `EngineerAssignment`, `GradeLevel`, `EngineerMetrics`, `GradeLevelSummary`, `GitLabActivity`

`Jyra/Services`

- `ConfigService.swift`: persists Jira and GitLab credentials (both in Keychain)
- `DashboardService.swift`: persists dashboards and widgets
- `BoardService.swift`: persists named boards to `boards.json`
- `CalibrationService.swift`: persists calibration configs to `calibrations.json`
- `GitLabService.swift`: fetches engineer activity from GitLab Cloud (commits, comments, MRs, reviews)
- `JiraService.swift`: all Jira HTTP calls and widget/board/calibration data shaping
- `JiraDataCache.swift`: in-memory response cache with a 5-minute TTL and per-widget/board force-refresh
- `MetricsStore.swift`: collects widget metrics and aggregates them by widget type for the dashboard summary section
- `NetworkLogger.swift`: captures every Jira HTTP request and response for the in-app debug panel and Xcode console

`Jyra/Views`

- `Setup/`: first-run Jira connection flow
- `Dashboard/`: unified sidebar (dashboards + boards + calibrations), widget containers, add-widget sheet
- `Boards/`: board kanban view, card view, card detail sheet, and board config sheet
- `Calibration/`: per-engineer metrics view and calibration config sheet
- `Widgets/`: individual widget views and configuration form
- `Shared/`: reusable search controls for boards, fields, and issues
- `SettingsView.swift`: Jira and GitLab connection settings
- `NetworkLogView.swift`: the in-app HTTP inspector opened from `Debug → Network Log…`

## Persistence

### Jira and GitLab Credentials

[ConfigService.swift](./Jyra/Services/ConfigService.swift) stores:

- Jira URL in `UserDefaults`
- Jira email in `UserDefaults`
- Jira API token in the macOS Keychain (`com.jyra.apikey`)
- GitLab Personal Access Token in the macOS Keychain (`com.jyra.gitlabtoken`)

`AppConfig.authHeader` generates the Basic auth header from `email:apiKey`.

### Dashboards

[DashboardService.swift](./Jyra/Services/DashboardService.swift) stores dashboards in:

`~/Library/Application Support/Jyra/dashboards.json`

Each dashboard contains widgets, and each widget stores a typed `WidgetConfig` payload.

### Boards

[BoardService.swift](./Jyra/Services/BoardService.swift) stores boards in:

`~/Library/Application Support/Jyra/boards.json`

Each board stores its name, the linked Jira board ID and name, an optional points field, and an ordered list of `BoardMetricRule` objects. Metric rules are fully `Codable`; `RuleColor` is stored as `r/g/b` Double triplets to avoid bridging issues with SwiftUI `Color`.

### Calibrations

[CalibrationService.swift](./Jyra/Services/CalibrationService.swift) stores calibration configs in:

`~/Library/Application Support/Jyra/calibrations.json`

Each calibration stores its name, linked boards, sprint count, and the engineer roster with grade levels and optional GitLab usernames.

## Navigation

The app uses a `NavigationSplitView` with a unified sidebar that has three sections:

- **Dashboards** — lists all saved dashboards; context-menu supports rename and delete
- **Boards** — lists all saved boards; context-menu supports configure and delete
- **Calibration** — lists all saved calibration configs; context-menu supports configure and delete

All three sections share a footer row of **+ New …** buttons. A **⚙ gear** button in the sidebar title bar opens Settings directly; **⌘,** does the same from anywhere.

## Settings

Settings are accessible via:

- **⚙ gear icon** in the top-right corner of the sidebar
- **⌘,** keyboard shortcut (standard macOS convention)
- **Jyra → Settings…** in the menu bar

The settings panel has three sections:

| Section | Contents |
|---------|----------|
| Jira Connection | URL, email, API token, Test Connection button |
| GitLab Activity (optional) | Personal Access Token, Test Connection button |
| Default Velocity Colors | Color pickers for the four velocity chart series |

Both tokens are stored in the macOS Keychain; nothing sensitive is written to `UserDefaults` or disk.

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
- `/rest/agile/1.0/board/{id}/issue`
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

## Boards

Boards are the second major view type in Jyra. Each board is linked to a Jira scrum or kanban board and shows all current issues grouped into three swimlane columns.

### Columns

| Column | Status category |
|--------|----------------|
| To Do | `new` |
| In Progress | `indeterminate` |
| Done | `done` |

Issues are grouped by their Jira status category key, not by status name, so custom statuses map correctly regardless of how they are named in Jira.

### Card UI

Each card shows:

- Issue key (monospaced, neon cyan)
- Issue type badge
- Summary (bold white)
- Story points badge (neon green, hidden when no points field is set)
- Assignee initials avatar (neon cyan outline)
- Priority label

Cards have a dark background with a neon outline. When a metric rule matches, the border color changes to the rule's configured highlight color and a matching glow appears behind the card. Blocked cards always show a red border and a red "BLOCKED" badge — blocked status takes precedence over all metric rules.

### Click to Expand

Clicking any card opens a detail sheet (`BoardCardDetailView`) showing:

- Full summary and issue key with a direct **Open in Jira** link
- Metadata grid: status, priority, story points, assignee, hours in current status
- Description (Atlassian Document Format is converted to plain text)
- Labels (wrapped pill layout)
- Parent issue key and summary
- Created and last-updated timestamps

### Metric Rules

Each board has a configurable list of `BoardMetricRule` objects. Rules are evaluated in order; the first matching rule sets the card's highlight color.

**Available fields:**

| Field | Type | Notes |
|-------|------|-------|
| Hours in Status | numeric | Time since the issue last changed status |
| Story Points | numeric | Requires a points field to be configured |
| Priority | string | Matches priority name |
| Status Name | string | Matches status display name |
| Issue Type | string | Matches issue type name |
| Label | string | True if the issue has the given label |
| Is Blocked | boolean | No value needed; matches `isBlocked` flag |

**Available operators** (vary by field type):

- Numeric: `>`, `<`, `=`, `≠`
- String: `=`, `≠`, `contains`
- Boolean: `is true`

**Colors:** seven neon presets — cyan, green, orange, red, purple, yellow, white.

Rules are configured per board in `BoardConfigView`. Each rule can be enabled/disabled with an inline toggle, edited in `RuleEditorView`, or deleted with swipe-to-delete.

### Board Configuration

Open the configuration sheet with the **⋯** button in the board toolbar, or right-click the board in the sidebar and choose **Configure**.

Settings:

- **Board Name**: display name shown in the sidebar and toolbar
- **Jira Board**: live-search the Jira Agile board list (same `BoardSearchField` used by widgets)
- **Points Field**: optional; auto-detected if left blank (same logic as burndown widgets)
- **Highlight Rules**: ordered rule list with add, edit, enable/disable, and delete

### Refresh

The board toolbar has a **↺** refresh button that immediately evicts the board's `JiraDataCache` entry and re-fetches all issues from Jira. The same 5-minute TTL and cache-key scheme used by widgets applies to boards.

## Calibration

Calibration is a per-engineer workload analysis tool. Each calibration config is linked to one or more Jira boards and analyzes a configurable number of recent closed sprints (plus the active sprint if one exists).

### Engineer Roster

Each calibration has an **engineer roster** — a curated list of people whose metrics you want to track. People not on the roster (e.g. stakeholders who occasionally appear as Jira assignees) are excluded from individual metric cards; their sprint work still contributes to the team's committed-point denominator and is treated as "other work."

**Roles available:**

| Role | Included in calibration metrics |
|------|---------------------------------|
| Intern | Yes |
| Engineer | Yes |
| Senior Engineer | Yes |
| Staff Engineer | Yes |
| Principal Engineer | Yes |
| Engineering Manager | Yes |
| Product Owner | No — excluded; work counts as "other work" |
| Business Analyst | No — excluded; work counts as "other work" |

You can remove anyone from the roster at any time by right-clicking their card and choosing **Remove from Roster**. The removal is immediate and persisted; the person does not reappear on the next data refresh.

Use **Discover Engineers** in the calibration config to automatically find all Jira assignees from recent sprint data and add them to the roster in one step.

### Metrics Per Engineer

| Metric | Description |
|--------|-------------|
| Avg Pts/Sprint | Completed points ÷ sprints analyzed |
| Total Completed | Sum of completed story points across all analyzed sprints |
| Team Committed | Total points the team committed across all analyzed sprints (denominator for relative workload) |
| Relative Workload | Engineer's completed points as a fraction of total team committed points |
| Stories Done | Count of completed issues |
| Avg Cycle Time | Mean time from "In Progress" to "Done" (hours if < 1 day, days otherwise) |
| Grade Rank | Rank within the same grade level, sorted by relative workload |

### Grade-Level Rankings

The **Grade Rankings** tab groups engineers by grade and ranks them by relative workload within each group. This enables fair cross-team comparison: a Senior Engineer's workload is only benchmarked against other Senior Engineers.

### GitLab Activity

If a GitLab Personal Access Token is configured in Settings, additional activity metrics are fetched from GitLab Cloud and shown on each engineer card:

| Metric | Source |
|--------|--------|
| Commits | Push events (commit count from push_data) |
| Comments | Note/comment events |
| MRs Opened | Merge request open events |
| MRs Reviewed | Merge request accepted/approval events |
| MRs Merged | Merge request merged events |

To link a Jira engineer to their GitLab account, enter their GitLab **@username** in the engineer row inside the calibration config sheet. The lookback window matches the configured sprint count (approximately sprint count × 14 days).

### CSV Export

The **↑ export button** in the calibration toolbar exports all currently visible engineer metrics to a CSV file. The export respects the active grade filter and sort order. When GitLab data is present, five additional columns are appended.

### Calibration Configuration

Open the configuration sheet with the **slider icon** in the calibration toolbar.

Settings:

- **Name**: display name for the calibration
- **Boards**: one or more Jira boards to analyze; each board can have its own points field
- **Sprint Window**: number of recent sprints to analyze (1–10)
- **Engineers**: roster with grade level and optional GitLab username per person

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
3. Enter an API token (generate one at id.atlassian.com → Security → API tokens)
4. Click **Test Connection**
5. Click **Save & Continue**

To connect GitLab (optional):

1. Open Settings (⌘, or the gear icon in the sidebar)
2. Under **GitLab Activity**, paste a Personal Access Token with `read_user` and `read_api` scopes
3. Click **Test GitLab Connection** to verify
4. Click **Save Settings**

You can update or clear either connection from Settings at any time.

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

### Mock Board Issues

The mock server includes two boards with issue fixture data for testing the Boards feature. These are distinct from the sprint/velocity boards above; they serve the `/rest/agile/1.0/board/{id}/issue` endpoint.

| Board ID | Name | Issues |
|----------|------|--------|
| 101 | Lone Wolf | 9 issues: 3 To Do, 4 In Progress (1 blocked), 2 Done |
| 102 | Velocity Kings | 11 issues: 3 To Do, 5 In Progress (1 blocked, 1 with "urgent" label), 3 Done |

### Testing The Boards Feature

1. Run the app under the **Jyra (Mock)** scheme.
2. In the sidebar footer, click **+ New Board**.
3. Give the board a name, then use the **Jira Board** search to select board **101** (Lone Wolf) or **102** (Velocity Kings). The points field can be left blank.
4. Save. The board appears in the sidebar under Boards.
5. Click the board to open the kanban view. Three columns appear with issues distributed by status category.
6. The blocked issue in each board appears with a red border and BLOCKED badge.
7. Click any card to open the full detail sheet.

**Testing metric rules:**

1. Open board configuration (⋯ button or right-click → Configure).
2. Click **Add Rule**.
3. Set: Field = Hours in Status, Operator = >, Value = 0 (all in-progress cards match since mock data has non-zero hours).
4. Pick a highlight color and save.
5. In-progress cards now show the chosen neon border and glow.

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
- GitLab integration targets GitLab Cloud (gitlab.com). Self-managed GitLab instances are not currently supported.
- The GitLab activity lookback window is estimated as sprint count × 14 + 7 days; it does not use actual sprint start dates.
- The network log panel captures up to 500 entries before dropping the oldest. It is intended for development and debugging — it is active in the Debug and Mock schemes only (controlled by `JYRA_DEBUG_NETWORK`).
- There are currently no automated tests in the repository.
- All state is local to the Mac; there is no backend or sync layer.
