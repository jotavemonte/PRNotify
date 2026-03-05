# PRNotify

**Note**: This app was vibecoded.

macOS menu bar app that monitors GitHub PRs — review queue, your open PRs, and activity notifications.

## Features

- **Menu bar badge** showing count of PRs awaiting your review
- **Dropdown menu:**
  - PRs awaiting review, up to 20 (configurable), with configurable sort order
  - "See More" opens GitHub with the same query
  - Recently visited review PRs, up to 10 (configurable), with PR status indicators
  - Your open PRs (authored), for quick access, with configurable sort order
- **System notifications** (each individually toggleable):
  - New PR assigned for your review
  - New comment on your PR
  - Approval on your PR
  - Changes requested on your PR
  - SLA breach — PR has been waiting for review beyond a configurable threshold
- **Settings** window (⌘,): token, username, limits, filter type, sort orders, SLA threshold, notification toggles, poll interval
- Runs as a **daemon on boot** via `SMAppService` (macOS 13+) or LaunchAgent

## Requirements

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) or Xcode.app
- GitHub token (personal access token with `repo` read scope)

## Build & Run

```bash
make build   # compile PRNotify.app
make run     # build + launch in background
pkill PRNotify  # stop
```

## Testing

```bash
make test    # compile and run the test suite
```

Tests cover models (`PullRequest`, `Settings`) and storage (`RecentPRsStore`, `PRActivityStore`). They run as a standalone binary with no Xcode required.

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

The username is auto-detected from the token on first launch. It can also be set manually or via the "Auto-detect" button in Settings.

## Settings

| Field | Default | Description |
|---|---|---|
| GitHub Token | — | Personal access token (`repo` read scope) |
| GitHub Username | auto | Your GitHub login |
| Max PRs to show | 20 | Review queue list limit |
| Max recent PRs | 10 | Recently visited list limit |
| Review filter | `user-review-requested` | `user-review-requested` = directly you; `review-requested` = you or your teams; `team-review-requested` = a specific team |
| Team slug | — | `org/team` slug, required when filter is `team-review-requested` |
| Review queue sort | oldest first | Sort order for the review queue |
| Authored PRs sort | newest first | Sort order for your open PRs |
| Review SLA (days) | 2 | Days before a PR is considered overdue; triggers SLA breach notifications |
| Notify: new PRs | on | Notify when a new PR is assigned for review |
| Notify: comments | on | Notify when a new comment appears on your PR |
| Notify: approvals | on | Notify when your PR is approved |
| Notify: changes requested | on | Notify when changes are requested on your PR |
| Notify: SLA breach | on | Notify when a review PR exceeds the SLA threshold |
| Poll interval | 120s | How often to fetch from GitHub |

## Notifications

| Event | Trigger |
|---|---|
| New review requested | A PR matching the review filter appeared since last poll |
| New comment | A new comment (including review comments) appeared on one of your open PRs |
| Approval | Someone approved your PR |
| Changes requested | Someone requested changes on your PR |
| SLA breach | A PR in the review queue has been open longer than the configured SLA threshold |

Clicking a notification opens the PR in the browser. Each notification type can be toggled individually in Settings.

## Notes

- App Sandbox is **disabled** — required for unrestricted network access
- No Dock icon — menu bar only
- All data (settings, recent PRs, activity snapshots) stored in `UserDefaults` under `com.prnotify`
- All GitHub interactions are **read-only** (GET requests only)
- Logs when running as LaunchAgent: `/tmp/com.prnotify.out.log` / `/tmp/com.prnotify.err.log`
