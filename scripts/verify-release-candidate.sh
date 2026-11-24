#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
cd "$project_dir"

require_distribution="${CLEANNEST_REQUIRE_DISTRIBUTION:-0}"
require_strict_localization="${CLEANNEST_REQUIRE_STRICT_LOCALIZATION:-$require_distribution}"
allow_dirty="${CLEANNEST_ALLOW_DIRTY:-0}"

if [[ "$require_distribution" != "0" && "$require_distribution" != "1" ]]; then
  print -u2 "CLEANNEST_REQUIRE_DISTRIBUTION must be 0 or 1"
  exit 64
fi
if [[ "$require_strict_localization" != "0" && "$require_strict_localization" != "1" ]]; then
  print -u2 "CLEANNEST_REQUIRE_STRICT_LOCALIZATION must be 0 or 1"
  exit 64
fi

git diff --check
source_dirty="false"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  source_dirty="true"
  if [[ "$allow_dirty" != "1" ]]; then
    print -u2 "release candidate gate: source tree is dirty"
    exit 1
  fi
fi

version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
build_number="$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
for plist in Resources/CleanNestLoginItem-Info.plist Resources/CleanNestScanner-Info.plist; do
  [[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "$version" ]]
  [[ "$(plutil -extract CFBundleVersion raw "$plist")" == "$build_number" ]]
done

localization_arguments=(
  Tools/LocalizationAudit.swift
  Resources/Localizable.xcstrings
  Sources/CleanNest
)
if [[ "$require_strict_localization" == "1" ]]; then
  localization_arguments+=(--strict-source)
fi
swift "${localization_arguments[@]}"

swift test
swift run CleanNestSelfTest
if [[ "$require_distribution" == "1" ]]; then
  scripts/build-installer.sh
else
  ./build.sh release
fi

app_path="$project_dir/build/CleanNest.app"
codesign --verify --deep --strict --verbose=2 "$app_path"
[[ "$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")" == "$version" ]]
[[ "$(plutil -extract CFBundleVersion raw "$app_path/Contents/Info.plist")" == "$build_number" ]]

authority="$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
signing_class="local-or-adhoc"
if [[ "$authority" == Developer\ ID\ Application:* ]]; then
  signing_class="developer-id"
fi

notarization="not-stapled"
if xcrun stapler validate "$app_path" >/dev/null 2>&1; then
  notarization="stapled"
fi

gate_status="source-candidate"
typeset -a blockers
blockers=()
if [[ "$signing_class" != "developer-id" ]]; then
  blockers+=("missing Developer ID Application signature")
fi
if [[ "$notarization" != "stapled" ]]; then
  blockers+=("missing Apple notarization staple")
fi
if [[ "$require_strict_localization" != "1" ]]; then
  blockers+=("strict source localization gate was not required")
fi

pkg_source=""
pkg_notarization="not-applicable"
if [[ "$require_distribution" == "1" ]]; then
  [[ "$signing_class" == "developer-id" ]]
  [[ "$notarization" == "stapled" ]]
  spctl --assess --type execute --verbose=2 "$app_path"

  for executable in \
    "$app_path/Contents/MacOS/CleanNest" \
    "$app_path/Contents/MacOS/CleanNestMCP" \
    "$app_path/Contents/Library/LoginItems/CleanNestLoginItem.app/Contents/MacOS/CleanNestLoginItem" \
    "$app_path/Contents/XPCServices/CleanNestScanner.xpc/Contents/MacOS/CleanNestScanner"; do
    [[ "$(lipo -archs "$executable")" == "x86_64 arm64" ]]
  done

  pkg_source="$project_dir/build/installer/CleanNest-${version}-${build_number}.pkg"
  [[ -f "$pkg_source" ]]
  pkgutil --check-signature "$pkg_source"
  xcrun stapler validate "$pkg_source"
  pkg_notarization="stapled"
  spctl --assess --type install --verbose=2 "$pkg_source"
  gate_status="distribution-candidate"
fi

commit="$(git rev-parse HEAD)"
short_commit="${commit[1,12]}"
output_dir="${CLEANNEST_RELEASE_OUTPUT_DIR:-$project_dir/build/release-candidate/${version}-${short_commit}}"
mkdir -p "$output_dir"
sbom_path="$output_dir/CleanNest-${version}.spdx.json"
archive_path="$output_dir/CleanNest-${version}-${build_number}.zip"
checksums_path="$output_dir/SHA256SUMS"
provenance_path="$output_dir/PROVENANCE.json"
pkg_path=""

swift Tools/SBOMGenerator.swift "$app_path" "$sbom_path"
ditto -c -k --keepParent "$app_path" "$archive_path"
rules_path=""
if [[ "$require_distribution" == "1" ]]; then
  rules_source="$project_dir/build/installer/CleanNestAgentRules.zip"
  [[ -f "$rules_source" ]]
  rules_path="$output_dir/CleanNestAgentRules.zip"
  cp -f "$rules_source" "$rules_path"
fi
if [[ -n "$pkg_source" ]]; then
  pkg_path="$output_dir/${pkg_source:t}"
  cp -f "$pkg_source" "$pkg_path"
fi
artifacts_to_hash=("${archive_path:t}" "${sbom_path:t}")
if [[ -n "$pkg_path" ]]; then
  artifacts_to_hash+=("${pkg_path:t}")
fi
if [[ -n "$rules_path" ]]; then
  artifacts_to_hash+=("${rules_path:t}")
fi
(
  cd "$output_dir"
  shasum -a 256 "${artifacts_to_hash[@]}" > "${checksums_path:t}"
)

archive_sha="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
sbom_sha="$(shasum -a 256 "$sbom_path" | awk '{print $1}')"
pkg_sha=""
if [[ -n "$pkg_path" ]]; then
  pkg_sha="$(shasum -a 256 "$pkg_path" | awk '{print $1}')"
fi
rules_sha=""
if [[ -n "$rules_path" ]]; then
  rules_sha="$(shasum -a 256 "$rules_path" | awk '{print $1}')"
fi
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
architecture="$(lipo -archs "$app_path/Contents/MacOS/CleanNest")"
swift_version="$(swift --version | head -n 1)"
blockers_json="$(printf '%s\n' "${blockers[@]:-}" | jq -R -s 'split("\n") | map(select(length > 0))')"

jq -n \
  --arg schemaVersion "2" \
  --arg product "CleanNest" \
  --arg version "$version" \
  --arg build "$build_number" \
  --arg sourceCommit "$commit" \
  --arg sourceDirty "$source_dirty" \
  --arg generatedAt "$generated_at" \
  --arg architecture "$architecture" \
  --arg swiftVersion "$swift_version" \
  --arg signingAuthority "$authority" \
  --arg signingClass "$signing_class" \
  --arg notarization "$notarization" \
  --arg pkgNotarization "$pkg_notarization" \
  --arg gateStatus "$gate_status" \
  --arg archive "${archive_path:t}" \
  --arg archiveSHA256 "$archive_sha" \
  --arg sbom "${sbom_path:t}" \
  --arg sbomSHA256 "$sbom_sha" \
  --arg pkg "${pkg_path:t}" \
  --arg pkgSHA256 "$pkg_sha" \
  --arg rules "${rules_path:t}" \
  --arg rulesSHA256 "$rules_sha" \
  --argjson blockers "$blockers_json" \
  '{
    schemaVersion: ($schemaVersion | tonumber),
    product: $product,
    version: $version,
    build: ($build | tonumber),
    source: {commit: $sourceCommit, dirty: ($sourceDirty == "true")},
    generatedAt: $generatedAt,
    buildEnvironment: {architecture: $architecture, swift: $swiftVersion},
    trust: {
      signingAuthority: $signingAuthority,
      signingClass: $signingClass,
      notarization: $notarization,
      pkgNotarization: $pkgNotarization,
      gateStatus: $gateStatus,
      blockers: $blockers
    },
    artifacts: ([
      {name: $archive, sha256: $archiveSHA256},
      {name: $sbom, sha256: $sbomSHA256}
    ] + (if $pkg == "" then [] else [{name: $pkg, sha256: $pkgSHA256}] end)
      + (if $rules == "" then [] else [{name: $rules, sha256: $rulesSHA256}] end))
  }' > "$provenance_path"

jq empty "$sbom_path" "$provenance_path"
print "release_candidate=$output_dir"
print "version=$version build=$build_number commit=$commit"
print "gate_status=$gate_status signing=$signing_class notarization=$notarization pkg_notarization=$pkg_notarization"
if [[ -n "$pkg_path" ]]; then
  print "pkg=$pkg_path"
fi
if (( ${#blockers[@]} > 0 )); then
  print "distribution_blockers=${(j:; :)blockers}"
fi
