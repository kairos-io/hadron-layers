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

# tailscale is the one layer whose builder image is not a bake variable:
# docker-bake.hcl spells the golang tag out in
# org.opencontainers.image.base.name, because the layer does not build from the
# toolchain and so cannot use common_labels(). Renovate's dockerfile manager
# bumps the FROM, and until kairos-io/kairos#5407 nothing looked inside the bake
# file, so the label described a Go version the binary had not been built with.
# Nothing goes red on its own: the layer builds, the label is never asserted,
# and the drift shows up only in the published image config.
builder_tag=$(sed -n 's|^FROM golang:\([^ @]*\).*|\1|p' \
  "$repository/tailscale/Dockerfile" | head -1)

labelled_tag=$(awk '
  /^target "tailscale"/ { armed = 1; next }
  armed && /^}/ { exit }
  armed && /"org\.opencontainers\.image\.base\.name"/ {
    if (match($0, /golang:[^"@]+/)) {
      print substr($0, RSTART + 7, RLENGTH - 7)
      exit
    }
  }
' "$repository/docker-bake.hcl")

if [[ -z "$builder_tag" || -z "$labelled_tag" ]]; then
  echo "could not read the tailscale builder tag from tailscale/Dockerfile (got '$builder_tag') or the golang tag of its org.opencontainers.image.base.name label in docker-bake.hcl (got '$labelled_tag'). One of the two was reshaped; teach this check the new shape." >&2
  exit 1
fi

if [[ "$builder_tag" != "$labelled_tag" ]]; then
  echo "tailscale/Dockerfile builds on golang:$builder_tag but docker-bake.hcl labels the layer org.opencontainers.image.base.name=docker.io/library/golang:$labelled_tag. Move both, or the published image names a base it was not built on. See kairos-io/kairos#5407." >&2
  exit 1
fi

echo 'tailscale base.name label matches its builder image'

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
