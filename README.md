# Claude Usage — menu bar app + desktop widget

A native macOS app that shows your Claude usage limits (the same data as Claude
Code's `/usage`) in three places:

- **Menu bar**: a colored progress ring + your 5-hour session limit percentage.
  Click it for per-limit bars, reset countdowns, and controls.
- **Desktop widget**: a real WidgetKit widget in the system widget gallery
  (small / medium / large). Right-click the desktop ▸ Edit Widgets ▸ "Claude Usage".
- **Usage window**: a standard titled window with the full breakdown — resizable,
  remembers its frame, optionally floats on top. Toggle it from the menu (⌘W).

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

It reads the Keychain OAuth token and polls the usage endpoint every minute,
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

## First launch

macOS will ask: *"ClaudeUsage wants to use your confidential information stored
in 'Claude Code-credentials'"* — click **Always Allow**.

## Menu options

- **Refresh Now** (⌘R while menu open)
- **Usage Window** (⌘W) — show/hide the detail window
- **Keep Window on Top** — pin that window above other apps
- **Notifications** submenu:
  - *Alert at 80% and 95%* — banner when a limit crosses those thresholds
  - *Alert When Limits Reset* — scheduled for the reset time of any limit ≥ 60%,
    so it fires even if the Mac was asleep at reset time
  - *Usage Pace Warnings* — burn-rate projection over the last hour; warns once
    per window if you're on pace to hit 100% before the reset arrives
- **Launch at Login** — via SMAppService (also toggleable in
  System Settings → General → Login Items)
- **Quit Claude Usage**

## Building

Two build paths, depending on whether you want the WidgetKit widget.

### With the widget (recommended) — needs Xcode

```sh
./build-widget.sh    # builds app + widget, installs to /Applications
```

Requirements:

- **Xcode** (not just Command Line Tools) and **XcodeGen** (`brew install xcodegen`).
- **An Apple ID signed into Xcode** (Settings ▸ Accounts). A *free* Apple ID is
  enough — no paid developer account. The first time, open `ClaudeUsage.xcodeproj`
  and pick your Team under Signing & Capabilities for **both** targets; Xcode
  creates the certificate then. After that the script is fully command-line.

Why signing is mandatory here: the app and the widget are separate processes that
share data through an **App Group**, and that entitlement cannot be ad-hoc signed.

The Xcode project is generated from [`project.yml`](project.yml) by XcodeGen, so
edit that rather than the `.xcodeproj` (which is gitignored).

### Without the widget — Command Line Tools only

```sh
./build.sh    # ad-hoc signed, installs to ~/Applications, no widget
```

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

Because the app pushes reloads on every poll, the widget tracks the ~1 minute
refresh rather than WidgetKit's lazy default schedule. macOS may still throttle
reloads, so every view shows an "updated Xm ago" stamp rather than implying the
number is live.

## Notes

- Colors: green < 50 %, yellow < 75 %, orange < 90 %, red ≥ 90 %.
- The menu bar and widget headline show the **5-hour session** limit (the one
  that bites mid-session), falling back to the highest limit if absent. The menu,
  window, and medium/large widgets list every limit.
- Installing to `/Applications` matters for the widget build: macOS registers
  widget extensions from a stable location. If you previously used `build.sh`,
  delete the old `~/Applications/Claude Usage.app` so you don't run both.
