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

Velocity uses the older Greenhopper endpoint. Jira may return sprint data incrementally behind a `transactionId`, so Jyra now keeps calling the velocity endpoint until it stops receiving new sprint entries, then merges the results into one velocity dataset.

That logic lives in:

- [JiraService.swift](./Jyra/Services/JiraService.swift)
- `fetchVelocity`
- `fetchVelocityPage`
- `fetchVelocityEntries`

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
- shows the most recent six sprints in the compact view
- shows up to twelve in the expanded sheet
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
- requires sprint dates to be present in Jira

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
- expands scope via JQL from the selected parents
- sums the selected estimate field across matching child work
- projects remaining scope against recent average velocity

Relevant files:

- [ProjectBurnRateWidgetView.swift](./Jyra/Views/Widgets/ProjectBurnRateWidgetView.swift)
- [IssueSearchField.swift](./Jyra/Views/Shared/IssueSearchField.swift)
- [FieldSearchField.swift](./Jyra/Views/Shared/FieldSearchField.swift)

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

## Current Assumptions And Limitations

- The app is designed for Jira Cloud-style REST endpoints.
- Project Burn Rate currently expands scope using:
  - direct issue keys
  - `parent in (...)`
  - `"Epic Link" in (...)`
- If a Jira instance uses different parent-link semantics, burn rate scope may need more JQL variants.
- Burndown and burn rate both depend on choosing the correct estimate field for the Jira instance.
- There are currently no automated tests in the repository.
- Widget layout is persisted, but there is no backend or sync layer; all state is local to the Mac.

## Notes For Future Work

Areas that would benefit from hardening:

- automated tests around `JiraService` response shaping
- stronger error handling for unsupported Jira configurations
- richer project burn rate scope expansion beyond `parent` and `Epic Link`
- explicit refresh controls and caching strategy
- drag/drop widget reordering in the dashboard UI
