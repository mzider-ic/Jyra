# Jyra

A local-first Jira metrics dashboard for engineering teams. Runs entirely on your Mac — credentials never leave your machine.

## Features

- **Velocity widget** — committed vs. completed story points for the last 6 sprints, expandable to 12 sprints, with rolling average line
- **Burndown widget** — ideal line, actual remaining, projected completion, scope-added markers, and configurable points field
- **Project Burn Rate widget** — multi-team shared story pool, per-team velocity contributions, and projected finish date
- **Multiple dashboards** — compose any mix of widgets across as many boards and teams as you need
- **Secure local config** — credentials stored in `~/.config/jyra/` with `chmod 600`, never exposed to the browser

## Prerequisites

| Requirement | Version |
|---|---|
| Node.js | 18.17 or later |
| npm | 9 or later |
| Jira Cloud | Any plan with API access |

## Installation

```bash
git clone <your-repo-url> jyra
cd jyra
npm install
```

## Running the app

```bash
npm run dev
```

Open **http://localhost:3131** in your browser. On first launch you will be redirected to the setup wizard.

For a production build (optional — dev mode is fine for local use):

```bash
npm run build
npm start
```

## First-run setup

The setup wizard asks for three things:

| Field | Example | Notes |
|---|---|---|
| Jira URL | `https://acme.atlassian.net` | No trailing slash |
| Email | `you@acme.com` | The email you log into Jira with |
| API Token | `ATATT3xFfGF0…` | See below |

### Getting a Jira API token

1. Go to **https://id.atlassian.com/manage-profile/security/api-tokens**
2. Click **Create API token**
3. Give it a label (e.g. "Jyra") and copy the token immediately — it is only shown once

After saving, Jyra tests the connection live. If it fails, check that your Jira URL is correct and that the token has not expired.

## Dashboards

### Creating a dashboard

Click the **+** icon next to "Dashboards" in the sidebar, type a name, and press Enter.

### Adding widgets

Click **Add widget** in the top-right of any dashboard. Choose a widget type, set its size (half or full width), and configure it.

### Widget sizes

| Size | Columns spanned |
|---|---|
| Half width | 6 of 12 columns |
| Full width | 12 of 12 columns |

### Editing and removing widgets

Click **Edit** in the dashboard header to reveal the configure (⚙) and delete (🗑) buttons on each widget.

## Widgets

### Velocity

Shows committed vs. completed story points per sprint as a grouped bar chart with a dashed average line.

**Configuration:**
- **Board** — the Scrum board to pull sprint data from

**Default view:** last 6 closed sprints. Click the expand (⤢) icon to open a modal showing the last 12 sprints.

**Data source:** Jira Agile API (sprint list) + Jira Greenhopper API (velocity stats)

---

### Burndown

Shows a sprint burndown built from raw issue data — not Jira's built-in chart — giving you full control over which field represents points.

**Configuration:**
- **Board** — the Scrum board
- **Sprint** — "Active sprint" or any specific closed sprint
- **Points field** — the Jira field that holds story points (e.g. `story_points`, `customfield_10016`, or any numeric custom field)

**Chart elements:**
| Element | Color | Meaning |
|---|---|---|
| Ideal line | Violet dashed | Linear burn from start total to zero |
| Actual | Cyan solid | Remaining points each day |
| Projected | Gray dashed | Linear extrapolation from today to zero |
| Scope markers | Rose | Points added to sprint after start |
| Today marker | Cyan vertical | Current day |

**Data source:** Jira Agile API (sprint + issues with resolution dates)

---

### Project Burn Rate

Tracks a project that spans multiple teams drawing from a single shared story-point pool.

**Configuration:**
- **Project name** — display label
- **Total story points** — the full project backlog size
- **Teams** — one or more boards; each team's recent velocity is fetched automatically

**How the projection works:**
1. Each team's average velocity is calculated from their last 6 closed sprints
2. Combined velocity = sum of all team averages
3. Historical burn is plotted from actual sprint completions
4. Future sprints are projected linearly until the pool reaches zero

**Data source:** Jira Greenhopper velocity API (one call per team)

## Security

| Concern | How it is handled |
|---|---|
| API key storage | Written to `~/.config/jyra/config.json` with `chmod 600` (user-readable only) |
| API key in browser | Never sent — all Jira calls are server-side Next.js API routes |
| API key in logs | Not logged at any level |
| Network | Runs on `localhost:3131` only, no external exposure |

To revoke access at any time: go to **Settings** in the sidebar and use **Update Jira Connection**, or delete `~/.config/jyra/config.json` manually.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Next.js 14 (App Router) | Server-side API proxy keeps credentials off the browser |
| Styling | Tailwind CSS | No runtime, dark theme via custom color tokens |
| Charts | Recharts | React-native, composable, customisable |
| Icons | lucide-react | Tree-shakeable, consistent |
| State | React Context + `useState` | No extra library needed at this scale |
| Data fetching | Native `fetch` + custom hooks | No extra library needed |
| Config storage | `~/.config/jyra/*.json` | Simple, portable, OS-level file permissions |

## File structure

```
app/
  api/              Server-side API routes (Jira proxy + dashboard CRUD)
  dashboard/        Dashboard pages
  setup/            First-run setup wizard
  globals.css       Dark theme base styles

components/
  dashboard/        Grid, widget shell, add/configure modals
  layout/           Sidebar, app shell
  setup/            Setup wizard form
  ui/               Button, Input, Select, Modal, Spinner, Badge
  widgets/          VelocityWidget, BurndownWidget, ProjectBurnRateWidget

lib/
  config.ts         Read/write ~/.config/jyra/config.json
  dashboards.ts     Read/write ~/.config/jyra/dashboards.json
  jira.ts           Typed Jira API client (server-side only)

hooks/
  useApi.ts         Fetch hook with abort, loading, error state
  useDashboards.ts  Dashboard CRUD with optimistic local state

types/
  index.ts          All shared TypeScript types
```

## Troubleshooting

**"Not configured" errors from widgets**
The server cannot read `~/.config/jyra/config.json`. Re-run setup at `/setup`.

**Velocity chart shows no data**
The board may have no closed sprints, or the Greenhopper API may be unavailable for your Jira instance. Check the browser console for the specific error returned from `/api/jira/velocity/[boardId]`.

**Burndown shows wrong point counts**
The points field selected in widget config does not match the field your team uses. Go to widget settings (⚙) and select the correct field from the dropdown — it lists all numeric Jira fields on your instance.

**Port 3131 already in use**
Change the port in `package.json`:
```json
"dev": "next dev --port 3232"
```
