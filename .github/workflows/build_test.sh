#!/usr/bin/env bash

set -euo pipefail

workflow=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.yml
repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
settings="$repository/publishing.yaml"

skip_layers=$(awk '
  /^    skip:/ { found = 1; next }
  found && /^      - / { values = values separator "\"" substr($0, 9) "\""; separator = ","; next }
  found { exit }
  END { print "[" values "]" }
' "$settings")

[[ "$skip_layers" == '["git"]' ]]

settings_output=$(awk '
  /sysext_skip_layers:/ { print; exit }
' "$workflow")

[[ "$settings_output" == *'steps.settings.outputs.sysext_skip_layers'* ]]
grep -q 'YAML.safe_load_file("publishing.yaml")' "$workflow"

for step in 'Create unsigned sysext' 'Push sysext artifact'; do
  condition=$(awk -v step="$step" '
    index($0, "- name: " step) { found = 1; next }
    found && /if:/ { print; exit }
    found && /env:/ { exit }
  ' "$workflow")

  [[ "$condition" == *'!contains(fromJSON(needs.discover.outputs.sysext_skip_layers), matrix.layer)'* ]]
done

echo 'build workflow sysext exclusions pass'

# A regex/semver version filter reads the version out of the regex's first
# capture group, so a regex without one matches every tag and keeps none.
# updatecli then fails the source with "versions list empty" and never names
# the cause, and because the autobumper only runs on a nightly schedule the
# manifest is already merged by the time anyone sees it. Catch it on the pull
# request instead.
ungrouped=$(awk '
  /kind: *regex\/semver/ { armed = 1; next }
  armed && /^[[:space:]]*regex:/ {
    armed = 0
    probe = $0
    gsub(/\(\?:/, "", probe)
    if (probe !~ /\(/) print FILENAME ":" FNR ":" $0
  }
' "$repository"/updatecli.d/*.yaml)

if [[ -n "$ungrouped" ]]; then
  printf '%s\n' "$ungrouped" >&2
  echo "the regex/semver versionfilter above has no capture group: wrap the version in ( ) or updatecli reports \"versions list empty\"" >&2
  exit 1
fi

echo 'updatecli regex/semver capture groups pass'

# A pull request merged by autoapprove.yml lands on main as a GITHUB_TOKEN
# event, and GitHub starts no workflow run for one. The push trigger in
# build.yml is therefore reached only when a person merges, so the schedule is
# the only thing that publishes a bot-merged bump. Nothing goes red when it is
# dropped: the pull request build still passes and the images stop moving
# (kairos-io/kairos#5406). Assert it is still there.
schedule_cron=$(awk '
  /^on:/ { in_on = 1; next }
  in_on && /^[^[:space:]]/ { in_on = 0 }
  in_on && /^  schedule:/ { armed = 1; next }
  armed && /^    - cron:/ { print; exit }
  armed && /^  [^[:space:]]/ { exit }
' "$workflow")

if [[ -z "$schedule_cron" ]]; then
  echo "build.yml has no schedule: trigger. A bot merge does not start a push run, so without it a merged dependency bump is never built or published. See kairos-io/kairos#5406." >&2
  exit 1
fi

echo 'build workflow schedule trigger pass'
