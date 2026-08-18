#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

cat > "$test_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"target":{"git":{"args":{"HADRON_TOOLCHAIN_VERSION":"v1.2.3"},"labels":{"org.opencontainers.image.title":"git","org.opencontainers.image.description":"Git","org.opencontainers.image.source":"https://github.com/kairos-io/hadron-layers"},"tags":["ghcr.io/kairos-io/hadron-layers/git:latest"]},"gpg":{"args":{"HADRON_TOOLCHAIN_VERSION":"v1.2.3"},"labels":{"org.opencontainers.image.title":"gpg","org.opencontainers.image.description":"GPG","org.opencontainers.image.source":"https://github.com/kairos-io/hadron-layers"},"tags":["ghcr.io/kairos-io/hadron-layers/gpg:latest"]}}}
JSON
EOF

cat > "$test_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *hadron-layers%2Fgit/versions*)
    printf '%s\n' '[{"name":"sha256:layergit","created_at":"2026-08-01T00:00:00Z","metadata":{"container":{"tags":["2.55.0"]}}}]'
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
chmod +x "$test_dir/bin/docker" "$test_dir/bin/gh"

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

if grep -qE 'unrelated|s390x|othermanifest' "$output"; then
  echo "unrelated sysext tags leaked into releases.json" >&2
  exit 1
fi

echo "build-data sysext tests passed"
