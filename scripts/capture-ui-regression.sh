#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_path="${1:-$project_dir/build/CleanNest.app}"
output_dir="${2:-$project_dir/build/ui-regression/$(date -u '+%Y%m%dT%H%M%SZ')-$$}"
width="${CLEANNEST_UI_WIDTH:-900}"
height="${CLEANNEST_UI_HEIGHT:-700}"
language_list="${CLEANNEST_UI_LANGUAGES:-zh-Hans en zh-Hant}"
page_list="${CLEANNEST_UI_PAGES:-overview cleanup applications disk status maintenance models agents evolution activity settings}"
languages=(${=language_list})
pages=(${=page_list})

executable="$app_path/Contents/MacOS/CleanNest"
if [[ ! -x "$executable" ]]; then
  print -u2 "UI regression: CleanNest executable not found: $executable"
  exit 66
fi
if pgrep -f "^${executable}" >/dev/null 2>&1; then
  print -u2 "UI regression: quit the running build before snapshot capture"
  exit 1
fi
mkdir -p "$output_dir"

for language in $languages; do
  locale="en_US"
  [[ "$language" == "zh-Hans" ]] && locale="zh_CN"
  [[ "$language" == "zh-Hant" ]] && locale="zh_TW"
  for page in $pages; do
    output="$output_dir/${language}-${page}-${width}x${height}.png"
    env \
      CLEANNEST_DEMO=1 \
      CLEANNEST_SNAPSHOT="$output" \
      CLEANNEST_SNAPSHOT_PAGE="$page" \
      CLEANNEST_SNAPSHOT_WIDTH="$width" \
      CLEANNEST_SNAPSHOT_HEIGHT="$height" \
      "$executable" \
      -AppleLanguages "($language)" \
      -AppleLocale "$locale"
    [[ -s "$output" ]]
  done
done

print "ui_regression=$output_dir"
print "captures=$(find "$output_dir" -type f -name '*.png' | wc -l | xargs)"
print "languages=${(j:,:)languages}"
print "pages=${(j:,:)pages}"
print "size=${width}x${height}"
