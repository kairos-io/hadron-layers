#!/usr/bin/env bash
#
# Feeds sample staged diffs to parse_bumps in autobumper-changelog.rb and checks
# the bumps it finds: ARG lines, docker-bake.hcl defaults, `uses:` lines and
# `..._IMAGE:` lines.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/autobumper-changelog.rb"

out="$(ruby -e '
require "json"
require ARGV[0]

dockerfile = <<~DIFF
  --- a/fwupd/Dockerfile
  +++ b/fwupd/Dockerfile
  @@ -5 +5 @@
  -ARG FWUPD_VERSION=2.0.1
  +ARG FWUPD_VERSION=2.0.2
  @@ -9 +9 @@
  -ARG LIBJCAT_VERSION=0.2.3
  +ARG LIBJCAT_VERSION=0.2.3
DIFF

hcl = <<~DIFF
  --- a/docker-bake.hcl
  +++ b/docker-bake.hcl
  @@ -3 +3 @@
  -  default = "v0.6.6"
  +  default = "v0.6.7"
DIFF

actions = <<~DIFF
  --- a/.github/workflows/pages.yml
  +++ b/.github/workflows/pages.yml
  @@ -47 +47 @@
  -        uses: actions/checkout@v6
  +        uses: actions/checkout@v7
  @@ -75 +75 @@
  -      - uses: actions/deploy-pages@v4
  +      - uses: actions/deploy-pages@v5
DIFF

image = <<~DIFF
  --- a/.github/workflows/build.yml
  +++ b/.github/workflows/build.yml
  @@ -9 +9 @@
  -  AURORABOOT_IMAGE: quay.io/kairos/auroraboot:v0.30.0
  +  AURORABOOT_IMAGE: quay.io/kairos/auroraboot:v0.31.0
DIFF

puts parse_bumps(dockerfile).to_json
puts parse_bumps(hcl, "docker-bake.hcl" => "HADRON_VERSION").to_json
puts parse_bumps(hcl).to_json
puts parse_bumps(actions).to_json
puts parse_bumps(image).to_json
puts display_name("LIBGPG_ERROR_VERSION"), display_name("AURORABOOT_IMAGE"), display_name("actions/checkout")
' "$SCRIPT")"

want='[{"matcher":"FWUPD_VERSION","old_version":"2.0.1","new_version":"2.0.2"}]
[{"matcher":"HADRON_VERSION","old_version":"v0.6.6","new_version":"v0.6.7"}]
[]
[{"matcher":"actions/checkout","old_version":"v6","new_version":"v7"},{"matcher":"actions/deploy-pages","old_version":"v4","new_version":"v5"}]
[{"matcher":"AURORABOOT_IMAGE","old_version":"v0.30.0","new_version":"v0.31.0"}]
libgpg-error
auroraboot
actions/checkout'

if [ "$out" = "$want" ]; then
  echo "ok"
else
  echo "FAIL" >&2
  diff <(echo "$want") <(echo "$out") >&2 || true
  exit 1
fi
