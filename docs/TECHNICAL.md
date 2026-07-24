# Claudar — technical notes

Internals, design decisions, and dead ends. For install and everyday use, see
the [README](../README.md).

## How it fetches usage

The app polls your usage every 30 seconds (configurable 15 s – 2 min), with
`Retry-After`-aware exponential backoff on 429s. It has two authentication modes.

### Mode 1 — Claude Code CLI (default)

Reads the OAuth token Claude Code stores in your login Keychain
(`Claude Code-credentials`) and calls `api.anthropic.com/api/oauth/usage` — the
same undocumented endpoint behind Claude Code's `/usage`.

It identifies itself as `claude-code/<version>` because that endpoint rejects
unrecognized User-Agents. Because the endpoint is undocumented, Anthropic can
change or remove it at any time, which would break the app.

**Why it prompts for your password.** That Keychain item belongs to *another
app*, so macOS gates each read with an authorization prompt. Clicking "Always
Allow" grants access — but the grant is tied to the item's access-control list,
and the CLI **rewrites that item every time it renews the token** (~every 8
hours), which resets the ACL and wipes your grant. So the prompt returns a few
times a day, usually noticed after an overnight sleep. Nothing in the app can
prevent this — it's macOS protecting another app's credential — and a paid
Developer ID signature wouldn't change it. Mode 2 exists to sidestep it.

**Keeping you signed in.** Access tokens last ~8 hours. The app can't refresh
them directly (see dead ends), but a real CLI call does — so on a 401 it runs a
tiny `claude -p "hi" --model haiku --no-session-persistence`, which makes the
CLI renew the Keychain token, then retries. This fires ~3×/day for a negligible
number of tokens (rate-limited to one call per 5 minutes). Only if that fails
does it ask you to run `claude` → `/login`.

**Reducing prompts.** The app caches the token it reads into its *own* Keychain
item (`Claudar-session`) and reads from there on normal polls and on wake —
reading your own item never prompts. It only touches Claude Code's item on first
launch and after a 401. This removes the wake-from-short-sleep prompt, but not
the renewal prompt (a long sleep expires the cached token, forcing a re-read of
Claude Code's freshly-rewritten item).

### Mode 2 — claude.ai session cookie

Reads a claude.ai session cookie from `Claudar-cookie` — a Keychain item
this app **owns**, so reading it never prompts — and calls
`claude.ai/api/organizations/<org>/usage`. That response carries the same limit
fields (`five_hour`, `seven_day`, `extra_usage`, …), so the parser is shared.

The cookie is obtained via an embedded `WKWebView` sign-in (menu → No-Prompt
Mode → Sign In). The WebView is given the same `User-Agent` as the fetch, so the
`cf_clearance` cookie it earns from Cloudflare stays valid for the later
`URLSession` requests — cf_clearance is UA-bound, so a mismatch would 403.
On success the app harvests all `claude.ai` cookies from the WebView's store and
writes them to the Keychain. (A manual path via `set-cookie.command` also exists.)

- The org UUID comes from the cookie's `lastActiveOrg`, with a
  `/api/organizations` lookup as fallback. Org and plan are cached in
  UserDefaults, so the extra lookup happens at most once.
- The plan badge (Pro / Max / Team / Enterprise) is derived from the org's
  `capabilities` array.
- **Cloudflare:** claude.ai is behind Cloudflare, which serves a challenge page
  (HTTP 403 "Just a moment…") to non-browser clients. `URLSession` passes;
  `curl` and Python both fail. So cookie mode always uses `URLSession` and never
  the curl fallback that Mode 1 has.

**Tradeoff:** the cookie is broader than the usage-scoped OAuth token (full
claude.ai session access) and expires every few weeks-to-months, so you re-paste
occasionally. In exchange, zero Keychain prompts. It's sent only to `claude.ai`.

## Privacy

No telemetry, no analytics, no third-party network calls. Credentials are read
from the Keychain, never written back to Claude Code's item, and sent only to
`api.anthropic.com` (Mode 1) or `claude.ai` (Mode 2). The credential-handling
code is in [Sources/Keychain.swift](../Sources/Keychain.swift) and
[Sources/UsageModel.swift](../Sources/UsageModel.swift).

## Approaches that do NOT work

Documented so nobody repeats them:

- **Calling the OAuth refresh endpoint from the app.**
  `platform.claude.com/v1/oauth/token` returns a persistent 429 to non-browser
  clients — it never clears, identically via `URLSession` and `curl` (with or
  without HTTP/1.1). Bot protection, not a rate limit.
- **`claude auth status`.** Reports only locally-stored state and never hits the
  network — returns `loggedIn: true` even when the stored token is long dead.
- **`claude setup-token` long-lived tokens.** Scoped for the Anthropic API, not
  `/oauth/usage`, so they're rejected with 401. (A token placed in a
  `Claudar-token` Keychain item is still preferred if present, but it isn't a
  working path today.)
- **A paid Developer ID signature to stop the prompt.** The prompt is caused by
  the CLI rewriting its own Keychain item's ACL, independent of how this app is
  signed. Signing doesn't help.
- **Timezone gotcha when debugging:** the Keychain's `expiresAt` is a Unix
  timestamp most tooling renders in *local* time. Print both zones when comparing
  against expiry, or you'll chase failures that haven't happened yet.

## Architecture

```
Sources/   host app (menu bar, window, fetching, notifications, status)
Widget/    WidgetKit extension
Shared/    model + formatting compiled into BOTH targets
Config/    Info.plists and entitlements
```

The host app is deliberately **not sandboxed** — it reads the Claude Code
Keychain item and spawns the `claude` CLI, neither of which a sandboxed process
can do. Widget extensions, by contrast, *must* be sandboxed. So they can't share
memory or arbitrary files: the app writes a JSON snapshot into the shared App
Group container and calls `WidgetCenter.reloadAllTimelines()`; the widget only
ever reads that snapshot and never touches your credentials.

The app pushes a widget reload on every poll, but macOS throttles and coalesces
widget refreshes on its own schedule, so the widget updates less often than the
menu bar in practice — every widget view shows an "updated Xm ago" stamp rather
than implying the number is live. The menu bar, drawn directly by the app,
tracks the full poll cadence.

Other details:

- Colors: green < 50%, yellow < 75%, orange < 90%, red ≥ 90%.
- The menu bar and widget headline show the **5-hour session** limit (the one
  that bites mid-session), falling back to the highest limit if absent. The menu,
  window, and medium/large widgets list every limit.
- The usage parser is generic: any new limit Anthropic adds appears
  automatically, no code change needed.

## Building from source

Two paths, depending on whether you want the WidgetKit widget.

### With the widget (needs Xcode)

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
   xcodegen generate && open Claudar.xcodeproj
   ```
   Select the **Claudar** target ▸ Signing & Capabilities ▸ **Team**, then do
   the same for the **ClaudarWidget** target. Xcode creates your development
   certificate at that moment.
4. Run `./build-widget.sh`. From here on it's fully command-line — it finds your
   team automatically.

Then add the widget: right-click the desktop ▸ **Edit Widgets** ▸ search
"Claudar" ▸ drag out the size you want.

The Apple ID is required because the app and widget are separate processes that
share data through an **App Group**, and that entitlement can't be ad-hoc signed.
The Xcode project is generated from [`project.yml`](../project.yml) by XcodeGen,
so edit that rather than the `.xcodeproj` (which is gitignored).

<details>
<summary>Widget build troubleshooting</summary>

- *"has entitlements that require signing with a development certificate"* — no
  Team selected yet; do step 3 above.
- *"invalid or unsupported format for signature"* — stale build artifacts. Run
  `rm -rf build/dd` and rebuild.
- *Widget doesn't appear in the gallery* — it's registered from the installed
  copy, so the app must be in `/Applications`. Confirm with
  `pluginkit -mv -p com.apple.widgetkit-extension | grep claude`.
- *Widget shows old data* — make sure only the `/Applications` copy is running.
  An ad-hoc `build.sh` copy in `~/Applications` can't write the shared snapshot.

</details>

### Without the widget (Command Line Tools only)

No Xcode, no Apple ID. Menu bar and usage window work fully; there's just no
widget.

```sh
./build.sh              # ad-hoc signed, installs to ~/Applications
./build.sh --package    # …and also produces build/Claudar-menubar.zip
```

This is what the published release contains.
