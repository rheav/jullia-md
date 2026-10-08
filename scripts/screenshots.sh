#!/usr/bin/env bash
# Render the real app views with demo files and an in-memory annotation store.
set -euo pipefail
cd "$(dirname "$0")/.."

export JULLIA_SCREENSHOTS="$PWD/docs/screenshots"
swift test --filter ScreenshotTests
