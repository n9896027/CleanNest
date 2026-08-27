#!/bin/zsh
set -euo pipefail

report_path="${1:-build/system-monitor-soak.tsv}"
required_seconds="${CLEANNEST_REQUIRED_SOAK_SECONDS:-172800}"
maximum_rss_kb="${CLEANNEST_MAXIMUM_SOAK_RSS_KB:-524288}"

if [[ ! -f "$report_path" ]]; then
  print -u2 "48h gate: report not found: $report_path"
  exit 66
fi
if ! [[ "$required_seconds" =~ '^[0-9]+$' ]] || (( required_seconds < 1 )); then
  print -u2 "CLEANNEST_REQUIRED_SOAK_SECONDS must be a positive integer"
  exit 64
fi
if ! [[ "$maximum_rss_kb" =~ '^[0-9]+$' ]] || (( maximum_rss_kb < 1 )); then
  print -u2 "CLEANNEST_MAXIMUM_SOAK_RSS_KB must be a positive integer"
  exit 64
fi

expected_header=$'timestamp\tpid\trss_kb\tcpu_percent\tapp_state\talert_history_mtime\tlogin_item_state\tdisplay_count'
actual_header="$(head -n 1 "$report_path")"
if [[ "$actual_header" != "$expected_header" ]]; then
  print -u2 "48h gate: unexpected report header"
  exit 65
fi

sample_count=$(($(wc -l < "$report_path") - 1))
if (( sample_count < 2 )); then
  print -u2 "48h gate: at least two samples are required"
  exit 1
fi

first_timestamp="$(sed -n '2p' "$report_path" | cut -f1)"
last_timestamp="$(tail -n 1 "$report_path" | cut -f1)"
first_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$first_timestamp" '+%s' 2>/dev/null || true)"
last_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$last_timestamp" '+%s' 2>/dev/null || true)"
if [[ -z "$first_epoch" || -z "$last_epoch" ]]; then
  print -u2 "48h gate: invalid UTC timestamp"
  exit 65
fi
elapsed_seconds=$(( last_epoch - first_epoch ))
if (( elapsed_seconds < required_seconds )); then
  print -u2 "48h gate: only ${elapsed_seconds}s observed; ${required_seconds}s required"
  exit 1
fi

not_running_count="$(awk -F '\t' 'NR > 1 && $5 != "running" { count += 1 } END { print count + 0 }' "$report_path")"
invalid_numeric_count="$(awk -F '\t' 'NR > 1 && ($3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+([.][0-9]+)?$/) { count += 1 } END { print count + 0 }' "$report_path")"
maximum_observed_rss_kb="$(awk -F '\t' 'NR > 1 && $3 ~ /^[0-9]+$/ { if ($3 > maximum) maximum = $3 } END { print maximum + 0 }' "$report_path")"

if (( not_running_count > 0 )); then
  print -u2 "48h gate: CleanNest was not running in ${not_running_count} sample(s)"
  exit 1
fi
if (( invalid_numeric_count > 0 )); then
  print -u2 "48h gate: ${invalid_numeric_count} sample(s) have missing RSS/CPU evidence"
  exit 1
fi
if (( maximum_observed_rss_kb > maximum_rss_kb )); then
  print -u2 "48h gate: peak RSS ${maximum_observed_rss_kb} KB exceeds ${maximum_rss_kb} KB"
  exit 1
fi

print "48h gate passed"
print "elapsed_seconds=$elapsed_seconds"
print "samples=$sample_count"
print "maximum_rss_kb=$maximum_observed_rss_kb"
