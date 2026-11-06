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

# Every layer declares who maintains its recipe, through
# io.kairos.hadron.layer.support. `official` is a promise the autobumper keeps:
# the layer has an updatecli.d manifest and a row in the autobumper matrix, so
# an upstream release reaches it and a broken bump reds the build. A
# contributed recipe with neither gets no bumps at all and goes stale in
# silence, which is exactly what the label is there to tell a consumer. Nothing
# in the build itself would notice, so assert it here.
autobumper="$(dirname "${BASH_SOURCE[0]}")/autobumper.yml"

support_per_target=$(awk '
  /^target "/ {
    if (match($0, /"[^"]+"/)) target = substr($0, RSTART + 1, RLENGTH - 2)
    support = ""
    next
  }
  target == "" { next }
  /labels[[:space:]]*=[[:space:]]*common_labels\(/ {
    # common_labels(title, description, support): read the arguments as quoted
    # strings rather than splitting on commas, so a description that holds one
    # cannot shift the count.
    rest = $0
    sub(/.*common_labels\(/, "", rest)
    count = 0
    while (match(rest, /"[^"]*"/)) {
      count++
      last = substr(rest, RSTART + 1, RLENGTH - 2)
      rest = substr(rest, RSTART + RLENGTH)
    }
    support = (count == 3) ? last : "bad-arity"
  }
  /"io\.kairos\.hadron\.layer\.support"[[:space:]]*=/ {
    if (match($0, /=[[:space:]]*"[^"]*"/)) {
      support = substr($0, RSTART, RLENGTH)
      sub(/^=[[:space:]]*"/, "", support)
      sub(/"$/, "", support)
    }
  }
  /^}/ && target != "" { print target, support; target = ""; next }
' "$repository/docker-bake.hcl")

if [[ -z "$support_per_target" ]]; then
  echo "read no layer targets out of docker-bake.hcl. The file was reshaped; teach this check the new shape." >&2
  exit 1
fi

while read -r layer support; do
  case "$support" in
    official) ;;
    community)
      continue
      ;;
    bad-arity)
      echo "common_labels() for layer '$layer' takes title, description and support. Pass the support argument: \"official\" or \"community\"." >&2
      exit 1
      ;;
    "")
      echo "layer '$layer' declares no io.kairos.hadron.layer.support label. Pass \"official\" or \"community\" to common_labels(), or set the label directly for a target that spells its labels out. See kairos-io/kairos#4239." >&2
      exit 1
      ;;
    *)
      echo "layer '$layer' declares io.kairos.hadron.layer.support='$support'. The only values consumers understand are 'official' and 'community'." >&2
      exit 1
      ;;
  esac

  if [[ ! -f "$repository/updatecli.d/${layer}.yaml" ]]; then
    echo "layer '$layer' is labelled official but has no updatecli.d/${layer}.yaml, so nothing bumps it. Add the manifest, or label the layer community." >&2
    exit 1
  fi

  if ! awk -v layer="$layer" '
    /^[[:space:]]*config:/ { armed = 1; next }
    armed && /^[[:space:]]*-[[:space:]]/ {
      name = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", name)
      if (name == layer) { found = 1; exit }
      next
    }
    armed { exit }
    END { exit found ? 0 : 1 }
  ' "$autobumper"; then
    echo "layer '$layer' is labelled official but is not in the autobumper matrix in autobumper.yml, so its updatecli manifest never runs. Add it to the matrix, or label the layer community." >&2
    exit 1
  fi
done <<<"$support_per_target"

echo 'every official layer has an updatecli manifest and an autobumper matrix row'
