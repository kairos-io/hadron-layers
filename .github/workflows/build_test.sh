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

# A gittag source only promises that the tag exists. A Dockerfile that fetches
# https://<host>/releases/download/<version>/... needs a published release, and
# upstreams tag more than they release: OpenZFS tags its development branch
# zfs-2.4.99 and never releases it, so the nightly bump moved the zfs layer onto
# a tarball that 404s. The autobumper merges itself, so main went red with no
# pull request to read. Pair a releases/download ARG with a githubrelease source.
if ! (
  cd "$repository" &&
  awk '
    FILENAME ~ /Dockerfile$/ {
      if ($0 !~ /releases\/download\//) next
      line = $0
      while (match(line, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
        released[FILENAME SUBSEP substr(line, RSTART + 2, RLENGTH - 3)] = 1
        line = substr(line, RSTART + RLENGTH)
      }
      next
    }

    # The manifests nest "kind:" under a versionfilter as well, so a source kind
    # is only the one at the entry s own indent.
    /^sources:[[:space:]]*$/ { section = "sources"; id = ""; next }
    /^targets:[[:space:]]*$/ { section = "targets"; id = ""; next }
    /^[^[:space:]#-]/        { section = "";       id = ""; next }
    section == "" { next }

    /^  [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ {
      id = $1; sub(/:$/, "", id); next
    }
    id == "" { next }

    { value = $2; gsub(/^["'\'']|["'\'']$/, "", value) }

    section == "sources" && /^    kind:[[:space:]]/ { kind[FILENAME SUBSEP id] = value; next }

    section == "targets" && $1 == "file:"     { file[FILENAME SUBSEP id] = value; next }
    section == "targets" && $1 == "matcher:"  { matcher[FILENAME SUBSEP id] = value; next }
    section == "targets" && $1 == "sourceid:" { sourceid[FILENAME SUBSEP id] = value; next }

    END {
      for (target in matcher) {
        split(target, part, SUBSEP)
        if (!((file[target] SUBSEP matcher[target]) in released)) continue

        source = sourceid[target]
        if (source == "") {
          printf "%s: target %s writes %s, read from a releases/download URL, and names no sourceid\n", part[1], part[2], matcher[target] > "/dev/stderr"
          bad = 1
          continue
        }
        if (kind[part[1] SUBSEP source] != "githubrelease") {
          printf "%s: %s is read from a releases/download URL in %s, but its source %s is kind %s, which only promises a tag\n", part[1], matcher[target], file[target], source, (kind[part[1] SUBSEP source] == "" ? "(none)" : kind[part[1] SUBSEP source]) > "/dev/stderr"
          bad = 1
        }
      }
      exit bad
    }
  ' */Dockerfile updatecli.d/*.yaml
); then
  echo "use kind: githubrelease for the source above, so a tag that was never released cannot be picked" >&2
  exit 1
fi

echo 'updatecli release-asset sources pass'

# One job gates the whole workflow, so the ruleset can require a single check
# that does not change when a layer or an arch is added.
workflow_file=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build.yml
awk '
  /^  layers-ci:/ { in_job = 1; next }
  in_job && /^  [a-z]/ { in_job = 0 }
  in_job && /name: layers-ci/ { named = 1 }
  in_job && /if: always\(\)/ { always = 1 }
  in_job && /needs: \[discover, build, merge\]/ { needs = 1 }
  END { exit !(named && always && needs) }
' "$workflow_file" || {
  echo "build.yml needs a layers-ci job named layers-ci that runs if: always() and needs discover, build and merge" >&2
  exit 1
}
echo 'layers-ci gate job present'

# The toolchain image and the base image are the same Hadron release, so the
# bake file has one version variable for both. A second variable would let a
# layer be built against one release and tested on another.
bake_file=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/docker-bake.hcl
if grep -q '^variable "HADRON_TOOLCHAIN_VERSION"' "$bake_file"; then
  echo "docker-bake.hcl must not define HADRON_TOOLCHAIN_VERSION; use HADRON_VERSION for the toolchain and the base image" >&2
  exit 1
fi
if grep -E '^\s*HADRON_TOOLCHAIN_VERSION\s*=' "$bake_file" | grep -vE '=\s*(HADRON_VERSION|ZFS_HADRON_VERSION)\s*$' | grep -q .; then
  echo "docker-bake.hcl must set HADRON_TOOLCHAIN_VERSION from HADRON_VERSION (or ZFS_HADRON_VERSION for zfs)" >&2
  exit 1
fi
echo 'one Hadron version for toolchain and base'

# The ruleset requires layers-ci in the merge queue, so the workflow must run
# there, and must not rebuild or publish anything: the pull request already
# built the same content.
grep -q '^  merge_group:' "$workflow_file" || {
  echo "build.yml needs a merge_group trigger so layers-ci reports in the merge queue" >&2
  exit 1
}
awk '
  /^  (build|merge):/ { job = $1; next }
  /^  [a-z-]+:/ { job = "" }
  job && /^    if:/ && /merge_group/ { seen[job] = 1 }
  END { exit !(seen["build:"] && seen["merge:"]) }
' "$workflow_file" || {
  echo "the build and merge jobs must be skipped on merge_group" >&2
  exit 1
}
echo 'merge queue runs the gate only'
