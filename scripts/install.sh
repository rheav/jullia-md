#!/usr/bin/env bash
# Builds Jullia.md and installs it to /Applications, replacing the previous copy. Preferences and annotations live
# outside the bundle (UserDefaults dev.rheav.jullia, ~/Library/Application Support/Jullia), so they carry over.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=/Applications/Jullia.md.app

./scripts/build-app.sh

# Quit a running copy the normal way (it saves its state), and wait for it to go.
if pgrep -xq Jullia; then
  osascript -e 'quit app "Jullia.md"' || true
  for _ in $(seq 1 50); do pgrep -xq Jullia || break; sleep 0.1; done
fi
if pgrep -xq Jullia; then
  echo "Jullia.md is still running; quit it and run this again." >&2
  exit 1
fi

rm -rf "$DEST"
ditto build/Jullia.md.app "$DEST"
# Make Finder, Spotlight and "Open With" see this copy (and its icon) right away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "Installed $DEST ($(cat VERSION))"
[[ "${1:-}" == "--no-open" ]] || open "$DEST"
