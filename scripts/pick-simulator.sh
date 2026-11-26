#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
set -euo pipefail
xcrun simctl list devices available -j | jq -r '
  [.devices | to_entries[]
    | select(.key | contains("SimRuntime.iOS"))
    | .key as $runtime
    | .value[]
    | select(.name | startswith("iPhone"))
    | {runtime: $runtime, udid: .udid}]
  | sort_by(.runtime | split("iOS-")[1] | split("-") | map(tonumber))
  | last
  | .udid'
