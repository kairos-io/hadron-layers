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
