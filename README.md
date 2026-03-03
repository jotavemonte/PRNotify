# PRNotify

**Note**: This app was vibecoded
macOS menu bar app that monitors GitHub PRs — review queue, your open PRs, and activity notifications.

## Features

- **Menu bar badge** showing count of PRs awaiting your review
- **Dropdown menu:**
  - PRs awaiting review, oldest-first, up to 20 (configurable)
  - "See More" opens GitHub with the same query
  - Recently visited review PRs, newest-first, up to 10 (configurable)
  - Your open PRs (authored), for quick access
- **System notifications:**
  - New PR assigned for your review
  - New comment on your PR
  - Approval on your PR
  - Changes requested on your PR
- **Settings** window (⌘,): token, username, limits, filter type, poll interval
- Runs as a **daemon on boot** via `SMAppService` (macOS 13+) or LaunchAgent

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) or Xcode.app
- GitHub token **or** `gh` CLI authenticated (`gh auth login`)

## Build & Run

```bash
make build   # compile PRNotify.app
make run     # build + launch in background
pkill PRNotify  # stop
```

## Install as Daemon

```bash
./install.sh            # build, copy to /Applications, register LaunchAgent
./install.sh uninstall  # remove everything
```

The app also registers itself with **System Settings → General → Login Items** automatically on first launch.

## GitHub Authentication

Resolved in this order:

1. Token saved in Settings window
2. `GITHUB_TOKEN` environment variable
3. `gh` CLI auth (`gh auth login`)

The username is auto-detected from the token or CLI on first launch. It can also be set manually or via the "Auto-detect" button in Settings.

## Settings

| Field | Default | Description |
|---|---|---|
| GitHub Token | — | Personal access token (`repo` read scope) |
| GitHub Username | auto | Your GitHub login |
| Max PRs to show | 20 | Review queue list limit |
| Max recent PRs | 10 | Recently visited list limit |
| Review filter | `user-review-requested` | `user-review-requested` = directly you; `review-requested` = you or your teams |
| Poll interval | 120s | How often to fetch from GitHub |

## Notifications

| Event | Trigger |
|---|---|
| New review requested | A PR matching the review filter appeared since last poll |
| New comment | Comment count increased on one of your open PRs |
| Approval | Someone approved your PR |
| Changes requested | Someone requested changes on your PR |

Clicking a notification opens the PR in the browser.

## Notes

- App Sandbox is **disabled** — required for `gh` CLI calls and unrestricted network access
- No Dock icon — menu bar only
- All data (settings, recent PRs, activity snapshots) stored in `UserDefaults` under `com.prnotify`
- All GitHub interactions are **read-only** (GET requests only)
- Logs when running as LaunchAgent: `/tmp/com.prnotify.out.log` / `/tmp/com.prnotify.err.log`
