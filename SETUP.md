# Jyra — Setup Guide

Step-by-step instructions for getting Jyra running on a fresh Mac.

## 1. Install Node.js

If you don't have Node.js 18+:

```bash
# With Homebrew (recommended)
brew install node

# Verify
node --version   # should be 18.17.0 or later
npm --version    # should be 9.x or later
```

Alternatively, download the LTS installer from **https://nodejs.org**.

## 2. Clone and install

```bash
git clone <your-repo-url> ~/jyra
cd ~/jyra
npm install
```

## 3. Get a Jira API token

1. Sign in to Atlassian at **https://id.atlassian.com**
2. Click your avatar → **Manage account**
3. Go to **Security** → **API tokens**
4. Click **Create API token**
5. Label it `Jyra` and click **Create**
6. **Copy the token now** — Atlassian will not show it again

Keep this token secret. It has the same permissions as your Jira account.

## 4. Start the app

```bash
npm run dev
```

Open **http://localhost:3131** — you will be redirected to the setup wizard automatically.

## 5. Complete the setup wizard

Fill in the three fields:

```
Jira URL:   https://yourcompany.atlassian.net
Email:      you@yourcompany.com
API Token:  ATATT3xFfGF0... (the token you copied above)
```

Click **Save & Connect**. Jyra will test the connection live and confirm your Jira display name. If the test fails, see [Troubleshooting](#troubleshooting) below.

## 6. Create your first dashboard

1. Click the **+** icon next to "Dashboards" in the left sidebar
2. Type a name (e.g. "Engineering") and press Enter
3. Click **Add widget** in the top-right corner
4. Choose a widget type and configure it

## 7. Configure widgets

### Velocity widget

Select the **Scrum board** you want to track. The widget will show the last 6 closed sprints automatically. Click the ⤢ expand icon on the widget to see 12 sprints.

### Burndown widget

1. Select the **board**
2. Select the **sprint** ("Active sprint" or a specific closed sprint)
3. Select the **points field** — this is the Jira custom field your team uses for story points. Common values:
   - `story_points` — standard Jira Software field
   - `customfield_10016` — another common story points field
   - If unsure, check your Jira board settings or ask your Jira admin

### Project Burn Rate widget

1. Enter a **project name** and **total story points** (the full backlog, not per team)
2. Click **Add team** for each team contributing to the project
3. Select each team's **board** — their velocity is fetched automatically

The widget projects how many sprints until the shared pool reaches zero, based on each team's rolling 6-sprint average velocity.

## Updating credentials

Go to **Settings** (bottom of the sidebar) at any time to update your Jira URL, email, or API token.

To completely reset: delete `~/.config/jyra/config.json` and `~/.config/jyra/dashboards.json`, then reload the app.

## Running as a persistent service (optional)

To have Jyra start automatically at login, create a launchd plist:

```bash
cat > ~/Library/LaunchAgents/com.jyra.app.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jyra.app</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/node</string>
    <string>/Users/YOUR_USERNAME/jyra/node_modules/.bin/next</string>
    <string>start</string>
    <string>--port</string>
    <string>3131</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/Users/YOUR_USERNAME/jyra</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/jyra.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/jyra-error.log</string>
</dict>
</plist>
EOF
```

Replace `YOUR_USERNAME` with your macOS username, then:

```bash
# Build first (required for production mode)
npm run build

# Load the service
launchctl load ~/Library/LaunchAgents/com.jyra.app.plist

# To stop it
launchctl unload ~/Library/LaunchAgents/com.jyra.app.plist
```

## Troubleshooting

### "Connection failed" during setup

- Confirm the URL is exactly `https://yourcompany.atlassian.net` with no trailing slash
- Confirm you are using your **Atlassian account email**, not a display name
- Confirm the API token was copied in full — they start with `ATATT3`
- Check that your Jira account has permission to view boards

### Widgets show "Jira 403" errors

Your API token may have expired or been revoked. Go to Settings and re-enter a fresh token.

### Velocity widget shows "No closed sprints found"

The selected board has no completed sprints yet, or the board is a Kanban board (velocity only applies to Scrum boards).

### Burndown shows 0 points everywhere

The points field selected does not match the field your team actually populates. Use the ⚙ configure button on the widget and try a different field. Your Jira admin can confirm the correct field ID under **Jira Settings → Issues → Custom fields**.

### Port 3131 is already in use

Edit `package.json` and change `--port 3131` to any free port, for example `--port 4000`.
