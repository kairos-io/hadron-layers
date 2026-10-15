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

# autoapprove.yml runs on pull_request_target, seconds after a bot opens a pull
# request and before any check has reported. The ruleset on main requires an
# approving review and no status check, so an approved pull request is in a
# CLEAN merge state at that moment and `gh pr merge --auto` merges it on the
# spot rather than queueing anything: that is how #91 put a ZFS_VERSION OpenZFS
# never released onto main, 18 seconds after it was approved and a minute
# before its own build 404ed. The merge belongs in automerge.yml, behind a
# green "Build and push layer images" run.
workflows=$(dirname "$workflow")

# Read code only: both files name the call in a comment explaining the split.
if grep -v '^[[:space:]]*#' "$workflows/autoapprove.yml" | grep -q 'gh pr merge'; then
  echo "autoapprove.yml merges a pull request itself. It runs before any check has reported and this repository requires no status check, so the merge lands unbuilt code on main (#91). Move the merge to automerge.yml, which waits for the build." >&2
  exit 1
fi

if ! grep -v '^[[:space:]]*#' "$workflows/automerge.yml" | grep -q 'gh pr merge'; then
  echo "automerge.yml does not merge anything. Without it an approved bot pull request never lands: \"Allow auto-merge\" is off on this repository, so enablePullRequestAutoMerge is refused." >&2
  exit 1
fi

# One allow-list, written twice. Approving a bot's pull request without ever
# merging it, or merging one nobody approved, is never what adding a bot to a
# single file is meant to do.
approve_bots=$(grep -oE "user\.login == '[^']+'" "$workflows/autoapprove.yml" |
  sed "s/.*== '//; s/'$//" | sort || true)
merge_bots=$(awk -F"'" '/^ *MERGE_BOTS:/ { print $2; exit }' "$workflows/automerge.yml" |
  tr ' ' '\n' | sed '/^$/d' | sort)

if [[ -z "$approve_bots" || -z "$merge_bots" ]]; then
  echo "could not read the bot allow-list out of autoapprove.yml or automerge.yml; the shape this test reads has changed" >&2
  exit 1
fi

if [[ "$approve_bots" != "$merge_bots" ]]; then
  echo "the bot allow-lists differ. autoapprove.yml approves [$(echo "$approve_bots" | tr '\n' ' ')] and automerge.yml merges [$(echo "$merge_bots" | tr '\n' ' ')]; keep them identical." >&2
  exit 1
fi

echo 'bot approve/merge split pass'
