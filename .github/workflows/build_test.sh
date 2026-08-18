#!/usr/bin/env bash

set -euo pipefail

workflow=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.yml

create_condition=$(awk '
  /- name: Create unsigned sysext/ { found = 1; next }
  found && /if:/ { print; exit }
  found && /env:/ { exit }
' "$workflow")

[[ "$create_condition" == *"matrix.layer != 'git'"* ]]

echo 'build workflow sysext exclusions pass'
