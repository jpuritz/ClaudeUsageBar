#!/bin/bash
# Sets up Claude Usage's no-prompt mode by saving your claude.ai session cookie
# to a Keychain item the app owns. Double-click this file, or run it in Terminal.
set -euo pipefail

echo "Opening claude.ai/settings/usage in your browser…"
open "https://claude.ai/settings/usage" || true
cat <<'STEPS'

In that browser tab:
  1. Open DevTools:            ⌘⌥I
  2. Click the Network tab, then reload the page (⌘R)
  3. Click the request named "usage"
  4. Scroll to Request Headers, find the "Cookie:" line,
     and copy its entire value to your clipboard

STEPS
read -r -p "Press Return once the Cookie value is on your clipboard… " _

COOKIE="$(pbpaste)"
if [[ "$COOKIE" != *sessionKey* ]]; then
  echo
  echo "✗ That clipboard doesn't contain a sessionKey."
  echo "  Make sure you copied the whole 'Cookie:' header value, then run this again."
  exit 1
fi

security add-generic-password -U -s "ClaudeUsage-cookie" -a "claude-usage" -w "$COOKIE"
echo
echo "✓ Saved. Claude Usage will switch to no-prompt mode within a minute."
echo "  To undo: security delete-generic-password -s \"ClaudeUsage-cookie\""
