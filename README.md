# Claude Usage — menu bar + desktop widget

A tiny native macOS app that shows your Claude usage limits (the same data as
Claude Code's `/usage`) in two places:

- **Menu bar**: a colored progress ring + your 5-hour session limit percentage.
  Click it for per-limit bars (session window, weekly limits), reset countdowns,
  and controls.
- **Desktop widget**: a frosted-glass panel pinned at desktop level (under normal
  windows, visible with the desktop). Drag it anywhere; its position is remembered.

Requires an active Claude subscription and the Claude Code CLI, signed in.

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
in 'Claude Code-credentials'"* — click **Always Allow**. (Rebuilding the app
re-triggers this prompt because the ad-hoc code signature changes.)

## Menu options

- **Refresh Now** (⌘R while menu open)
- **Show Desktop Widget** — toggle the desktop panel
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

Requires only Command Line Tools (no Xcode):

```sh
./build.sh    # compiles, signs ad-hoc, installs to ~/Applications
```

## Notes

- The "desktop widget" is a borderless panel at desktop-icon window level —
  it behaves like a widget but isn't a WidgetKit widget, so it won't appear in
  the system widget gallery. A true WidgetKit widget requires full Xcode to
  build; if you install Xcode later, this could be converted.
- Colors: green < 50 %, yellow < 75 %, orange < 90 %, red ≥ 90 %.
- The menu bar percentage is the *highest* utilization across all limits.
