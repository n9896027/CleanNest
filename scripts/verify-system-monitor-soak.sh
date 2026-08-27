#!/bin/zsh
set -euo pipefail
zmodload zsh/datetime

duration_seconds="${CLEANNEST_SOAK_SECONDS:-172800}"
sample_seconds="${CLEANNEST_SOAK_INTERVAL_SECONDS:-60}"
report_path="${CLEANNEST_SOAK_REPORT:-build/system-monitor-soak.tsv}"

if ! [[ "$duration_seconds" =~ '^[0-9]+$' ]] || (( duration_seconds < 1 )); then
  print -u2 "CLEANNEST_SOAK_SECONDS must be a positive integer"
  exit 2
fi
if ! [[ "$sample_seconds" =~ '^[0-9]+$' ]] || (( sample_seconds < 1 )); then
  print -u2 "CLEANNEST_SOAK_INTERVAL_SECONDS must be a positive integer"
  exit 2
fi

mkdir -p "${report_path:h}"
print 'timestamp\tpid\trss_kb\tcpu_percent\tapp_state\talert_history_mtime\tlogin_item_state\tdisplay_count' > "$report_path"

started_at=$EPOCHSECONDS
deadline=$(( started_at + duration_seconds ))
alert_file="$HOME/Library/Application Support/CleanNest/system-alert-timeline.json"

while (( EPOCHSECONDS < deadline )); do
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  pid="$(pgrep -x CleanNest | head -n 1 || true)"
  if [[ -n "$pid" ]]; then
    process_values="$(ps -p "$pid" -o rss=,%cpu= | xargs || true)"
    rss_kb="${process_values%% *}"
    cpu_percent="${process_values##* }"
    app_state="running"
  else
    rss_kb="-"
    cpu_percent="-"
    app_state="not_running"
  fi
  if [[ -e "$alert_file" ]]; then
    alert_mtime="$(stat -f '%m' "$alert_file")"
  else
    alert_mtime="-"
  fi
  if launchctl print "gui/$UID/com.zone.cleannest.loginitem" >/dev/null 2>&1; then
    login_state="loaded"
  else
    login_state="not_loaded"
  fi
  display_count="$(system_profiler SPDisplaysDataType 2>/dev/null | rg -c 'Resolution:' || true)"
  print "$timestamp\t${pid:--}\t${rss_kb:--}\t${cpu_percent:--}\t$app_state\t$alert_mtime\t$login_state\t${display_count:-0}" >> "$report_path"
  remaining=$(( deadline - EPOCHSECONDS ))
  (( remaining <= 0 )) && break
  sleep_for=$sample_seconds
  (( remaining < sleep_for )) && sleep_for=$remaining
  sleep "$sleep_for"
done

print "soak_report=$report_path"
print "requested_seconds=$duration_seconds"
print "samples=$(($(wc -l < "$report_path") - 1))"
