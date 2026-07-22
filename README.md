# Claude Usage — menu bar app + desktop widget

[![Downloads](https://img.shields.io/github/downloads/jpuritz/ClaudeUsageBar/total?label=downloads&color=brightgreen)](https://github.com/jpuritz/ClaudeUsageBar/releases)
[![Latest release](https://img.shields.io/github/v/release/jpuritz/ClaudeUsageBar)](https://github.com/jpuritz/ClaudeUsageBar/releases/latest)
[![License](https://img.shields.io/github/license/jpuritz/ClaudeUsageBar)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)

A native macOS app that shows your Claude usage limits (the same data as Claude
Code's `/usage`) in three places:

- **Menu bar**: a colored progress ring + your 5-hour session limit percentage.
  Click it for per-limit bars, reset countdowns, and controls.
- **Desktop widget**: a real WidgetKit widget in the system widget gallery
  (small / medium / large). Right-click the desktop ▸ Edit Widgets ▸ "Claude Usage".
- **Usage window**: a standard titled window with the full breakdown — resizable,
  remembers its frame, optionally floats on top. Toggle it from the menu (⌘W).

It also shows **live Claude service status** (a colored line in the menu, and a
dot on the menu-bar ring during an incident), refreshes on wake, and offers a
global shortcut and a configurable poll interval — see [Menu options](#menu-options).

Requires an active Claude subscription and the Claude Code CLI, signed in.

## Screenshots

**Desktop widget** — medium size shown; small and large also available:

![The Claude Usage widget on the macOS desktop: a 31% session ring beside progress bars for each limit](docs/widget.png)

**Menu bar** — ring plus session percentage, with the full breakdown and controls on click:

![The Claude Usage menu bar dropdown listing each limit with reset countdowns, above menu options](docs/menubar.png)

**Usage window** — resizable, remembers its frame, and can float on top:

![The Claude Usage window showing each limit with progress bars and reset times](docs/window.png)

## Read this before installing

This is an unofficial personal tool. It is **not affiliated with or endorsed by
Anthropic**, and it relies on two things you should know about:

1. **It calls an undocumented internal endpoint** (`/api/oauth/usage`) — the same
   one that powers Claude Code's `/usage`. There is no stability guarantee:
   Anthropic can change, restrict, or remove it at any time, and this app would
   break. Use at your own risk.
2. **It identifies itself as `claude-code/<version>`.** That endpoint rejects
   unrecognized User-Agents, so the app sends the same one the CLI does. It reads
   only your own usage data, using your own credentials, on your own machine.

**Credential handling:** it reads (never writes) the OAuth token Claude Code
stores in your login Keychain under `Claude Code-credentials`. That token is sent
to exactly one place — `api.anthropic.com` — and nowhere else. It is never
logged, displayed, or transmitted to any third party. There is no telemetry and
no network activity beyond the Anthropic API and the local `claude` CLI. All the
relevant code is in [Sources/Keychain.swift](Sources/Keychain.swift) and
[Sources/UsageModel.swift](Sources/UsageModel.swift) — it's short; read it.

## How it works

It reads the Keychain OAuth token and polls the usage endpoint every 30 seconds,
with `Retry-After`-aware exponential backoff on 429s.

### Keeping sign-in alive (no manual /login)

Access tokens last ~8 hours. The app cannot refresh them directly — the OAuth
refresh endpoint (`platform.claude.com/v1/oauth/token`) blocks non-browser
clients with a persistent 429. Neither does `claude auth status`, which only
reports locally-stored state and never hits the network.

What *does* renew the Keychain credential is **any real CLI API call**. So when
the usage endpoint returns 401, the app runs:

```sh
claude -p "hi" --model haiku --no-session-persistence
```

…which makes the CLI renew the token and write it back to the Keychain; the app
then retries with the fresh token. This fires roughly 3× a day and costs a
negligible number of tokens. It's rate-limited to one invocation per 5 minutes,
with a 45-second timeout. Only if that fails does the app ask you to run
`claude` → `/login`.

### Approaches that do NOT work

Documented so nobody repeats the dead ends:

- **Calling the OAuth refresh endpoint from the app.** `platform.claude.com/v1/oauth/token`
  returns a persistent 429 to non-browser clients — it never clears, and behaves
  identically via `URLSession` and `curl` (with or without HTTP/1.1). Looks like
  bot protection rather than a rate limit.
- **`claude auth status`.** Reports only locally-stored state and never hits the
  network — it returns `loggedIn: true` even when the stored token is long dead.
- **`claude setup-token` long-lived tokens.** Scoped for the Anthropic API, not
  the `/oauth/usage` endpoint, so they're rejected with 401. (The app will still
  prefer a token placed in a `ClaudeUsage-token` Keychain item if you add one,
  but this is not a working path today.)

### Debugging note

The Keychain's `expiresAt` is a Unix timestamp — most tooling renders it in
**local** time. Print both zones when comparing against expiry, or you'll chase
failures that haven't happened yet.

## Install

### Homebrew (menu bar + window, no widget)

```sh
brew install --cask --no-quarantine jpuritz/tap/claude-usage
```

The `--no-quarantine` flag matters: the build is ad-hoc signed, and without it
Gatekeeper blocks the first launch.

### Download (same build, manual)

Grab `ClaudeUsage-menubar.zip` from the
[latest release](https://github.com/jpuritz/ClaudeUsageBar/releases/latest),
unzip, and drag **Claude Usage.app** to `/Applications`.

It's **ad-hoc signed**, so macOS quarantines it on first open. Clear that once:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"
```

(Or open it via right-click ▸ Open, then System Settings ▸ Privacy & Security ▸
*Open Anyway*.)

**Why the download has no widget, and why it isn't properly signed:** shipping
the WidgetKit widget requires an App Group entitlement, which requires a
provisioning profile from a paid Apple Developer account ($99/yr) — a free
Personal Team certificate is development-only and won't launch on anyone else's
Mac. Distributing without Gatekeeper warnings needs a Developer ID certificate
from that same paid account. Neither is something this project has, so: the
download is the menu-bar build, and **the widget means building from source**
(free, but needs Xcode). See [Building](#building).

### First launch

macOS will ask: *"ClaudeUsage wants to use your confidential information stored
in 'Claude Code-credentials'"* — click **Always Allow**. The app reads that
token to call the usage endpoint; denying it leaves the app with nothing to show.

## Menu options

- **Claude service status** — top line, colored; click to open status.claude.com.
  Watches claude.ai, Claude API, Claude Code, and Claude Console.
- **Refresh Now** (⌘R while menu open)
- **Usage Window** (⌘W) — show/hide the detail window
- **Keep Window on Top** — pin that window above other apps
- **Notifications** submenu:
  - *Alert at 80% and 95%* — banner when a limit crosses those thresholds
  - *Alert When Limits Reset* — scheduled for the reset time of any limit ≥ 60%,
    so it fires even if the Mac was asleep at reset time
  - *Usage Pace Warnings* — burn-rate projection over the last hour; warns once
    per window if you're on pace to hit 100% before the reset arrives
  - *Claude Service Alerts* — banner when a watched service goes down or recovers
- **Refresh Interval** — 15 s / 30 s / 1 min / 2 min (default 30 s)
- **Global Shortcut (⌘⇧U)** — open the usage window from anywhere; off by default.
  Uses Carbon hotkeys, so **no Accessibility permission** is needed.
- **Launch at Login** — via SMAppService (also toggleable in
  System Settings → General → Login Items)
- **Quit Claude Usage**

The app also refreshes immediately when the Mac wakes from sleep, so the first
reading after waking isn't stale.

## Building

Two build paths, depending on whether you want the WidgetKit widget.

### With the widget (recommended) — needs Xcode

```sh
brew install xcodegen
./build-widget.sh          # builds app + widget, installs to /Applications
```

First time only, before that script will succeed:

1. Install **Xcode** (not just Command Line Tools) and point the tools at it:
   `sudo xcode-select -s /Applications/Xcode.app`
2. **Xcode ▸ Settings ▸ Accounts ▸ "+" ▸ Apple ID** and sign in. A *free* Apple ID
   works — no paid developer account.
3. Generate and open the project, then pick your Team:
   ```sh
   xcodegen generate && open ClaudeUsage.xcodeproj
   ```
   Select the **ClaudeUsage** target ▸ Signing & Capabilities ▸ **Team**, then do
   the same for the **ClaudeUsageWidget** target. Xcode creates your development
   certificate at that moment.
4. Run `./build-widget.sh`. From here on it's fully command-line — it finds your
   team automatically.

Then add the widget: right-click the desktop ▸ **Edit Widgets** ▸ search
"Claude Usage" ▸ drag out the size you want.

**Why the Apple ID is required:** the app and widget are separate processes that
share data through an **App Group**, and that entitlement can't be ad-hoc signed.

**Troubleshooting**

- *"has entitlements that require signing with a development certificate"* — no
  Team selected yet; do step 3.
- *"invalid or unsupported format for signature"* — stale build artifacts. Run
  `rm -rf build/dd` and rebuild.
- *Widget doesn't appear in the gallery* — it's registered from the installed
  copy, so the app must be in `/Applications`. Confirm with:
  `pluginkit -mv -p com.apple.widgetkit-extension | grep claude`

The Xcode project is generated from [`project.yml`](project.yml) by XcodeGen, so
edit that rather than the `.xcodeproj` (which is gitignored).

### Without the widget — Command Line Tools only

No Xcode, no Apple ID. Menu bar and usage window work fully; there's just no
widget.

```sh
./build.sh              # ad-hoc signed, installs to ~/Applications
./build.sh --package    # …and also produces build/ClaudeUsage-menubar.zip
```

This is what the published release contains.

## Architecture

```
Sources/   host app (menu bar, window, fetching, notifications)
Widget/    WidgetKit extension
Shared/    model + formatting compiled into BOTH targets
Config/    Info.plists and entitlements
```

The host app is deliberately **not sandboxed** — it reads the Claude Code
Keychain item and spawns the `claude` CLI, neither of which a sandboxed process
can do. Widget extensions, by contrast, *must* be sandboxed. So they can't share
memory or arbitrary files: the app writes a JSON snapshot into the shared App
Group container and calls `WidgetCenter.reloadAllTimelines()`, and the widget
only ever reads that snapshot. The widget never touches your credentials.

The app pushes a widget reload on every poll (~30 s), but macOS throttles and
coalesces widget refreshes on its own schedule, so the widget updates less often
than that in practice — every view shows an "updated Xm ago" stamp rather than
implying the number is live. The menu bar, which the app draws directly, is the
one that actually tracks the 30-second cadence.

## Notes

- Colors: green < 50 %, yellow < 75 %, orange < 90 %, red ≥ 90 %.
- The menu bar and widget headline show the **5-hour session** limit (the one
  that bites mid-session), falling back to the highest limit if absent. The menu,
  window, and medium/large widgets list every limit.
- Installing to `/Applications` matters for the widget build: macOS registers
  widget extensions from a stable location. If you previously used `build.sh`,
  delete the old `~/Applications/Claude Usage.app` so you don't run both.
