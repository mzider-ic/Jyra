# Jyra

Jyra is a native macOS SwiftUI dashboard for Jira. It connects to a Jira Cloud instance with an API token, lets you build dashboards made up of widgets, and pulls live data from Jira Agile and Jira REST APIs.

The app is currently focused on three widget types:

- `Velocity`: completed vs committed points across recent sprints
- `Burndown`: sprint burndown for the active or selected sprint
- `Project Burn Rate`: scope-based burn projection for a selected team board

## How The App Works

At launch, [JyraApp.swift](./Jyra/JyraApp.swift) creates a single `ConfigService` and injects it into the SwiftUI environment.

- If Jira credentials are not configured, [ContentView.swift](./Jyra/ContentView.swift) shows [SetupView.swift](./Jyra/Views/Setup/SetupView.swift).
- If credentials exist, it shows [DashboardView.swift](./Jyra/Views/Dashboard/DashboardView.swift).

The basic runtime flow is:

1. User enters Jira URL, email, and API token.
2. `ConfigService` stores the token in Keychain and the non-secret fields in `UserDefaults`.
3. `DashboardService` loads dashboards from disk.
4. Each widget uses `JiraService` to fetch its own Jira data on demand.

## Project Structure

`Jyra/Models`

- `AppConfig.swift`: Jira connection settings and auth header generation
- `DashboardModels.swift`: dashboards, widgets, and widget config payloads
- `JiraModels.swift`: decoded Jira API response shapes and derived chart models

`Jyra/Services`

- `ConfigService.swift`: persists Jira credentials
- `DashboardService.swift`: persists dashboards and widgets
- `JiraService.swift`: all Jira HTTP calls and widget data shaping

`Jyra/Views`

- `Setup/`: first-run Jira connection flow
- `Dashboard/`: dashboard list, widget containers, add-widget sheet
- `Widgets/`: individual widget views and configuration form
- `Shared/`: reusable search controls for boards, fields, and issues

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

Relevant files:

- [VelocityWidgetView.swift](./Jyra/Views/Widgets/VelocityWidgetView.swift)
- [WidgetConfigView.swift](./Jyra/Views/Widgets/WidgetConfigView.swift)

### Burndown

Config: `BurndownConfig`

Inputs:

- board
- sprint selection (`active` or a specific sprint)
- points field

Behavior:

- loads sprint issues from the Agile sprint issue API
- computes total points, completed points, ideal line, actual remaining, and simple projection
- requires sprint `startDate` and `endDate` to be set in Jira; missing dates produce a `missingSprintDates` error

Relevant files:

- [BurndownWidgetView.swift](./Jyra/Views/Widgets/BurndownWidgetView.swift)
- [JiraService.swift](./Jyra/Services/JiraService.swift)

### Project Burn Rate

Config: `ProjectBurnRateConfig`

Inputs:

- project name
- team board
- estimate field
- selected parent issues / epics

Behavior:

- fetches recent team velocity from the selected board
- searches selected scope issues using Jira issue picker
- expands scope via JQL from the selected parents (`parent in (...)`)
- `"Epic Link" in (...)` is attempted and silently skipped on a 400, matching Jira Cloud behavior
- sums the selected estimate field across matching child work
- projects remaining scope against recent average velocity

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

## Widget Configuration UX

[WidgetConfigView.swift](./Jyra/Views/Widgets/WidgetConfigView.swift) is the central editor for widget settings.

Search controls:

- [BoardSearchField.swift](./Jyra/Views/Shared/BoardSearchField.swift): board lookup via Jira Agile board search
- [FieldSearchField.swift](./Jyra/Views/Shared/FieldSearchField.swift): local search over Jira fields already fetched from `/field`
- [IssueSearchField.swift](./Jyra/Views/Shared/IssueSearchField.swift): live search via Jira issue picker

## Building And Running

Requirements:

- macOS
- Xcode 16+
- Swift 6

Open the project:

```bash
open Jyra.xcodeproj
```

Build from the command line:

```bash
xcodebuild -project Jyra.xcodeproj -scheme Jyra -configuration Debug -sdk macosx -derivedDataPath /tmp/JyraDerivedData build
```

The repo also contains [project.yml](./project.yml), which describes the project in XcodeGen format.

## First-Run Setup

When the app starts without credentials:

1. Enter your Jira base URL, for example `https://your-org.atlassian.net`
2. Enter the Jira account email
3. Enter an API token
4. Click `Test Connection`
5. Click `Save & Continue`

You can later update or clear the connection from Settings.

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
2. Sets the environment variable `JYRA_MOCK_URL=http://localhost:3001`, which bypasses Keychain credential checks in `ConfigService`.
3. Runs `mock-jira/stop.sh` when the app exits.

No Jira credentials or network access are required when running under this scheme.

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

Add a burndown widget and select any board from 101–104. Issues across those boards have resolution dates spread across the past three days, producing a visible step-down curve rather than a single cliff drop.

Board 201 (No-Dates Team) should produce the "Sprint is missing start or end dates" error, which confirms the error path renders correctly.

### Testing The Project Burn Rate Widget

1. Add a Project Burn Rate widget.
2. In the configuration sheet, pick any board (101–104) as the **Team Board** — this drives the velocity side of the projection.
3. In the **Scope** section, search for `JYRA` in the issue picker.
4. Select **JYRA-1** (the "Platform Modernization" epic). The mock server resolves its child stories via `parent in ("JYRA-1")`, returning 8 stories totalling **76 story points**.
5. The widget projects how many sprints the selected team needs to complete 76 points at their recent average velocity.

Available scope issues:

| Key    | Summary                     | Points |
|--------|-----------------------------|--------|
| JYRA-1 | Platform Modernization      | —      |
| JYRA-2 | Migrate auth to JWT         | 13     |
| JYRA-3 | API versioning support      | 8      |
| JYRA-4 | Database connection pooling | 5      |
| JYRA-5 | Redis caching layer         | 13     |
| JYRA-6 | Background job queue        | 8      |
| JYRA-7 | Audit logging service       | 5      |
| JYRA-8 | Deploy pipeline v2          | 21     |
| JYRA-9 | Performance benchmarks      | 3      |

## Current Assumptions And Limitations

- The app is designed for Jira Cloud-style REST endpoints.
- Project Burn Rate expands scope using direct issue keys and `parent in (...)`. If a Jira instance uses different parent-link semantics, additional JQL variants may be needed.
- Burndown requires sprint `startDate` and `endDate` to be populated in Jira.
- Burndown and Burn Rate both depend on choosing the correct estimate field for the Jira instance.
- There are currently no automated tests in the repository.
- All state is local to the Mac; there is no backend or sync layer.
