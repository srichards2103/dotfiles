#!/usr/bin/env bash
# Open app URL and set 1920x1080 viewport for shipfeat screenshots.
set -euo pipefail

if (( $# < 1 )); then
  echo "Usage: playwright_shipfeat_init.sh <app-url>" >&2
  exit 1
fi

url="$1"

if ! command -v playwright-cli >/dev/null 2>&1; then
  echo "playwright_shipfeat_init: playwright-cli not on PATH" >&2
  exit 1
fi

playwright-cli open "$url"
playwright-cli resize 1920 1080

echo "playwright: ${url} @ 1920x1080"
