#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

cat > "$test_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "buildx imagetools" ]]; then
  case "$4" in
    */git:2.55.0) echo '{"linux/amd64":{"config":{"Labels":{"io.kairos.hadron.layer.kernel-compat":"7.3.x"}}}}' ;;
    */git:*) echo '{"linux/amd64":{"config":{"Labels":{"org.opencontainers.image.base.name":"ghcr.io/kairos-io/hadron-toolchain:v0.6.1"}}}}' ;;
    *) echo '{}' ;;
  esac
  exit 0
fi
cat <<'JSON'
{"target":{"git":{"args":{"HADRON_TOOLCHAIN_VERSION":"v1.2.3"},"labels":{"org.opencontainers.image.title":"git","org.opencontainers.image.description":"Git","org.opencontainers.image.source":"https://github.com/kairos-io/hadron-layers","io.kairos.hadron.layer.support":"community","io.kairos.hadron.layer.status":"beta","io.kairos.hadron.layer.hadron-compat":">=0.6.1","io.kairos.hadron.layer.kernel-compat":""},"tags":["ghcr.io/kairos-io/hadron-layers/git:latest"]},"gpg":{"args":{"HADRON_TOOLCHAIN_VERSION":"v1.2.3"},"labels":{"org.opencontainers.image.title":"gpg","org.opencontainers.image.description":"GPG","org.opencontainers.image.source":"https://github.com/kairos-io/hadron-layers"},"tags":["ghcr.io/kairos-io/hadron-layers/gpg:latest"]}}}
JSON
EOF

cat > "$test_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *hadron-layers%2Fgit/versions*)
    printf '%s\n' '[{"name":"sha256:layergit","created_at":"2026-08-01T00:00:00Z","metadata":{"container":{"tags":["2.55.0"]}}},{"name":"sha256:layergitold","created_at":"2026-07-01T00:00:00Z","metadata":{"container":{"tags":["2.54.0"]}}}]'
    ;;
  *hadron-layers%2Fgpg/versions*)
    printf '%s\n' '[{"name":"sha256:layergpg","created_at":"2026-08-01T00:00:00Z","metadata":{"container":{"tags":["2.4.9"]}}}]'
    ;;
  *hadron-layers%2Fsysext%2Fgit/versions*)
    printf '%s\n' '[{"name":"sha256:amd64manifest","created_at":"2026-08-02T00:00:00Z","metadata":{"container":{"tags":["2.55.0-amd64","unrelated"]}}},{"name":"sha256:arm64manifest","created_at":"2026-08-02T00:00:00Z","metadata":{"container":{"tags":["2.55.0-arm64","2.55.0-s390x"]}}},{"name":"sha256:othermanifest","created_at":"2026-08-02T00:00:00Z","metadata":{"container":{"tags":["9.9.9-amd64"]}}}]'
    ;;
  *hadron-layers%2Fsysext%2Fgpg/versions*)
    exit 1
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 2
    ;;
esac
EOF
cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *hadron/v0.6.1/Dockerfile) echo "ARG KERNEL_VERSION=7.2.11" ;;
  *) exit 22 ;;
esac
EOF
chmod +x "$test_dir/bin/docker" "$test_dir/bin/gh" "$test_dir/bin/curl"

output="$test_dir/releases.json"
PATH="$test_dir/bin:$PATH" REPO=kairos-io/hadron-layers \
  "$repo_root/site/build-data.sh" "$output"

jq -e '
  (.layers[] | select(.name == "git") | .tags[] | select(.tag == "2.55.0") | .sysext) == {
    "amd64": {"oci": "ghcr.io/kairos-io/hadron-layers/sysext/git@sha256:amd64manifest"},
    "arm64": {"oci": "ghcr.io/kairos-io/hadron-layers/sysext/git@sha256:arm64manifest"}
  }
' "$output" >/dev/null

jq -e '
  (.layers[] | select(.name == "gpg") | .tags[] | select(.tag == "2.4.9")) as $tag
  | $tag.digest == "sha256:layergpg" and $tag.sysext == {}
' "$output" >/dev/null

## The support label rides the same metadata pipeline as title and description:
## a layer that carries it keeps its value, and a layer published before the
## label existed is reported as official rather than as an empty string.
jq -e '(.layers[] | select(.name == "git") | .support) == "community"' "$output" >/dev/null
jq -e '(.layers[] | select(.name == "gpg") | .support) == "official"' "$output" >/dev/null

## status, hadron-compat and kernel-compat are informational: a value is copied
## through as text, and a missing or empty one means no claim (stable, `*`).
jq -e '(.layers[] | select(.name == "git") | [.status, .hadron_compat, .kernel_compat]) == ["beta", "*", "7.3.x"]' "$output" >/dev/null
jq -e '(.layers[] | select(.name == "gpg") | [.status, .hadron_compat, .kernel_compat]) == ["stable", "*", "*"]' "$output" >/dev/null

## Compat is per tag: a tag with the label keeps it, an older tag without one
## gets the kernel series of the Hadron release its toolchain base names, and a
## tag with neither makes no claim. The layer-level value is the latest tag's.
jq -e '(.layers[] | select(.name == "git") | .tags[] | select(.tag == "2.55.0") | .kernel_compat) == "7.3.x"' "$output" >/dev/null
jq -e '(.layers[] | select(.name == "git") | .tags[] | select(.tag == "2.54.0") | .kernel_compat) == "7.2.x"' "$output" >/dev/null
jq -e '(.layers[] | select(.name == "git") | .kernel_compat) == "7.3.x"' "$output" >/dev/null
jq -e '(.layers[] | select(.name == "gpg") | .tags[0].kernel_compat) == "*"' "$output" >/dev/null

if grep -qE 'unrelated|s390x|othermanifest' "$output"; then
  echo "unrelated sysext tags leaked into releases.json" >&2
  exit 1
fi

echo "build-data sysext, support and compat label tests passed"
