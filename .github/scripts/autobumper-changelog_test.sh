#!/usr/bin/env bash
#
# Feeds sample staged diffs to parse_bumps in autobumper-changelog.rb and checks
# the bumps it finds: ARG lines, docker-bake.hcl defaults, `uses:` lines and
# `..._IMAGE:` lines. Also checks the name target_matcher reads off a target.

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

# A file with two bumped variables, with the one line of context a -U1 diff
# carries: each default goes to the variable declared above it.
hcl2 = <<~DIFF
  --- a/docker-bake.hcl
  +++ b/docker-bake.hcl
  @@ -12,3 +12,3 @@
   variable "HADRON_VERSION" {
  -  default = "v0.6.1"
  +  default = "v0.6.7"
   }
  @@ -20,3 +20,3 @@
   variable "HADRON_KERNEL_SERIES" {
  -  default = "7.2.x"
  +  default = "7.3.x"
   }
DIFF

puts parse_bumps(dockerfile).to_json
puts parse_bumps(hcl, "docker-bake.hcl" => "HADRON_VERSION").to_json
puts parse_bumps(hcl).to_json
puts parse_bumps(hcl2, "docker-bake.hcl" => %w[HADRON_VERSION HADRON_KERNEL_SERIES]).to_json
puts parse_bumps(actions).to_json
puts parse_bumps(image).to_json
puts display_name("LIBGPG_ERROR_VERSION"), display_name("AURORABOOT_IMAGE"), display_name("actions/checkout")

# A file target rewriting an ARG line (open-vm-tools APORTS_VERSION) is looked
# up by that ARG, like a dockerfile target.
puts target_matcher("kind" => "dockerfile", "spec" => { "instruction" => { "keyword" => "ARG", "matcher" => "GLIB_VERSION" } })
puts target_matcher("kind" => "hcl", "spec" => { "file" => "docker-bake.hcl", "path" => "variable.HADRON_VERSION.default" })
puts target_matcher("kind" => "file", "spec" => { "file" => "open-vm-tools/Dockerfile", "matchpattern" => "(?m)^ARG APORTS_VERSION=.*$" })
puts target_matcher("kind" => "file", "spec" => { "file" => ".github/workflows/build.yml", "matchpattern" => "AURORABOOT_IMAGE: .*" }).inspect
' "$SCRIPT")"

want='[{"matcher":"FWUPD_VERSION","old_version":"2.0.1","new_version":"2.0.2"}]
[{"matcher":"HADRON_VERSION","old_version":"v0.6.6","new_version":"v0.6.7"}]
[]
[{"matcher":"HADRON_VERSION","old_version":"v0.6.1","new_version":"v0.6.7"},{"matcher":"HADRON_KERNEL_SERIES","old_version":"7.2.x","new_version":"7.3.x"}]
[{"matcher":"actions/checkout","old_version":"v6","new_version":"v7"},{"matcher":"actions/deploy-pages","old_version":"v4","new_version":"v5"}]
[{"matcher":"AURORABOOT_IMAGE","old_version":"v0.30.0","new_version":"v0.31.0"}]
libgpg-error
auroraboot
actions/checkout
GLIB_VERSION
HADRON_VERSION
APORTS_VERSION
nil'

if [ "$out" = "$want" ]; then
  echo "ok"
else
  echo "FAIL" >&2
  diff <(echo "$want") <(echo "$out") >&2 || true
  exit 1
fi
