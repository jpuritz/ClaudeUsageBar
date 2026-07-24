# Claude Usage

> Watch your Claude usage limits from the macOS menu bar, a desktop widget, and
> a status window — the same numbers as Claude Code's `/usage`, always in view.

[![Downloads](https://img.shields.io/github/downloads/jpuritz/ClaudeUsageBar/total?label=downloads&color=brightgreen)](https://github.com/jpuritz/ClaudeUsageBar/releases)
[![Latest release](https://img.shields.io/github/v/release/jpuritz/ClaudeUsageBar)](https://github.com/jpuritz/ClaudeUsageBar/releases/latest)
[![License](https://img.shields.io/github/license/jpuritz/ClaudeUsageBar)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)

![Opening Claude Usage: the ring icon in the menu bar, then the dropdown showing each limit with reset countdowns](docs/demo.gif)

> **Unofficial** — not affiliated with Anthropic. It reads *your* Claude sign-in
> from your Keychain, talks only to Anthropic's servers, and has no telemetry.

**Requires:** macOS 14+, an active Claude subscription, and the
[Claude Code CLI](https://code.claude.com) signed in.

## Install

**Homebrew** (recommended):

```sh
brew install --cask --no-quarantine jpuritz/tap/claude-usage
```

**Or** download `ClaudeUsage-menubar.zip` from the
[latest release](https://github.com/jpuritz/ClaudeUsageBar/releases/latest),
unzip, drag **Claude Usage.app** to `/Applications`, then run once:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"
```

*(Both are needed because the app is ad-hoc signed; the flag / command tells
Gatekeeper to trust it.)*

**On first launch**, macOS asks to access *Claude Code-credentials* — click
**Always Allow**. That's how the app reads your usage.

> **Want the desktop widget?** The download and Homebrew builds are the **menu
> bar + window** version. The widget has to be built from source (free, needs
> Xcode) — see [building](docs/TECHNICAL.md#building-from-source).

## Features

- **Menu bar** — a colored ring and your 5-hour session percentage; click for
  every limit with reset countdowns.
- **Desktop widget** — a real WidgetKit widget (small / medium / large) in the
  system widget gallery.
- **Usage window** — the full breakdown in a normal window: resizable, remembers
  its position, and can float on top.
- **Live Claude service status** — a colored line in the menu and a dot on the
  ring when claude.ai, the API, Claude Code, or the Console has an incident.
- **Notifications** — 80% / 95% thresholds, reset alerts, "on pace to run out"
  warnings, and service up/down alerts. Each toggleable.
- **Global shortcut** (⌘⇧U) opens the window from anywhere — no extra permissions.
- **Configurable refresh** (15 s – 2 min), plus an instant refresh on wake.

## Screenshots

| Widget | Menu bar | Window |
|---|---|---|
| ![widget](docs/widget.png) | ![menu bar](docs/menubar.png) | ![window](docs/window.png) |

## Menu options

- **Claude service status** — click to open status.claude.com
- **Refresh Now** (⌘R while the menu is open)
- **Usage Window** (⌘W) — show/hide the detail window
- **Keep Window on Top**
- **Notifications** — thresholds, resets, pace warnings, service alerts
- **Refresh Interval** — 15 s / 30 s / 1 min / 2 min
- **Global Shortcut (⌘⇧U)** — off by default
- **Launch at Login**
- **Quit**

## Sign-in and the password prompt

Out of the box the app uses your **Claude Code CLI** sign-in — nothing to set up.
The one quirk: because it reads a credential that belongs to the CLI, macOS asks
for your password to authorize it, and that authorization gets reset each time
the CLI refreshes its token (a few times a day). So the prompt comes back
periodically. This is macOS protecting the CLI's credential, not a bug.

**To never see that prompt,** switch to a claude.ai session cookie stored in a
Keychain item the app owns. The easiest way:

```sh
# from a copy of this repo
./set-cookie.command
```

That opens the right page, walks you through copying your cookie, and saves it.
Prefer to do it by hand? Copy the `Cookie:` header from claude.ai's DevTools
(Network tab → the `usage` request) and run:

```sh
security add-generic-password -U -s "ClaudeUsage-cookie" -a "claude-usage" -w "$(pbpaste)"
```

The app switches over automatically. The cookie is full claude.ai session access
(broader than the CLI token) and expires every few weeks, so you re-run it
occasionally. To go back to CLI mode:
`security delete-generic-password -s "ClaudeUsage-cookie"`.

Full details on both modes are in [docs/TECHNICAL.md](docs/TECHNICAL.md#how-it-fetches-usage).

## More

- **[Technical notes](docs/TECHNICAL.md)** — how it works, privacy, architecture,
  building from source, and the dead ends we hit so you don't repeat them.

## License

[MIT](LICENSE) © Jon Puritz
