#!/bin/zsh
set -euo pipefail

mode="${1:-cold}"
app_path="${2:-build/CleanNest.app}"
settle_seconds="${CLEANNEST_MEMORY_SETTLE_SECONDS:-60}"

case "$mode" in
  cold|tour|agent) ;;
  *)
    print -u2 "usage: $0 [cold|tour|agent] [path/to/CleanNest.app] [report.json]"
    exit 64
    ;;
esac

if [[ ! -x "$app_path/Contents/MacOS/CleanNest" ]]; then
  print -u2 "CleanNest executable not found: $app_path"
  exit 66
fi

if (( $# >= 3 )); then
  report_path="$3"
else
  report_path="$(mktemp -t cleannest-memory).json"
fi
typeset -a environment
environment=(
  "CLEANNEST_MEMORY_MODE=$mode"
  "CLEANNEST_MEMORY_REPORT=$report_path"
  "CLEANNEST_MEMORY_SETTLE_SECONDS=$settle_seconds"
)
if [[ "$mode" == "tour" ]]; then
  environment+=("CLEANNEST_DEMO=1")
fi

env "${environment[@]}" "$app_path/Contents/MacOS/CleanNest"

if [[ ! -s "$report_path" ]]; then
  print -u2 "Memory report was not created."
  exit 1
fi

print "Memory report: $report_path"
/usr/bin/plutil -p "$report_path"

if [[ "$(/usr/bin/plutil -extract passed raw -o - "$report_path")" != "true" ]]; then
  print -u2 "CleanNest memory budget failed for mode: $mode"
  exit 1
fi
