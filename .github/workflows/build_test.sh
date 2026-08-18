#!/usr/bin/env bash

set -euo pipefail

workflow=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.yml

skip_list=$(awk '
  /SYSEXT_SKIP_LAYERS:/ { print; exit }
' "$workflow")

[[ "$skip_list" == *'["git"]'* ]]

for step in 'Create unsigned sysext' 'Push sysext artifact'; do
  condition=$(awk -v step="$step" '
    index($0, "- name: " step) { found = 1; next }
    found && /if:/ { print; exit }
    found && /env:/ { exit }
  ' "$workflow")

  [[ "$condition" == *'!contains(fromJSON(env.SYSEXT_SKIP_LAYERS), matrix.layer)'* ]]
done

echo 'build workflow sysext exclusions pass'
