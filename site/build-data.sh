#!/usr/bin/env bash

## Aggregate hadron-layers metadata into a single releases.json file consumed
## by the static page (site/index.html).
##
## Layers are discovered from docker-bake.hcl via `docker buildx bake --print`
## so descriptions/labels stay a single source of truth (OCI labels defined on
## the bake target). Version history for each published image is pulled from
## the GitHub Packages REST API — the token must have `read:packages` scope
## (in CI, set the workflow permission `packages: read`).
##
## Output shape:
##   {
##     "generated": "<ISO timestamp>",
##     "repo": "owner/repo",
##     "toolchain": "vX.Y.Z",
##     "layers": [
##       {
##         "name": "git",
##         "title": "git",
##         "description": "Git version control system",
##         "image": "ghcr.io/kairos-io/hadron-layers/git",
##         "source": "https://github.com/kairos-io/hadron-layers",
##         "support": "official",
##         "status": "stable",
##         "hadron_compat": "*",
##         "kernel_compat": "*",
##         "latest": "2.52.0",
##         "tags": [
##           {"tag": "2.52.0", "digest": "sha256:...", "created": "...", "hadron_compat": "*", "kernel_compat": "*"}
##         ]
##       }
##     ]
##   }
##
## Environment:
##   REPO       owner/repo the site belongs to (required, e.g. kairos-io/hadron-layers)
##   NAMESPACE  ghcr namespace containing the layer packages (default: derived from REPO owner)
##   GH_TOKEN   token with `read:packages` scope for querying package versions
## Usage:
##   REPO=owner/repo ./site/build-data.sh [output_file]

set -euo pipefail

REPO="${REPO:?REPO is required (owner/repo)}"
OUT="${1:-releases.json}"
NAMESPACE="${NAMESPACE:-${REPO%%/*}}"

echo "Discovering layers from docker-bake.hcl..." >&2

## Resolve every bake target — args, labels and tags with variables substituted.
bake=$(docker buildx bake --print 2>/dev/null)
if [[ -z "$bake" ]]; then
  echo "ERROR: docker buildx bake --print produced no output" >&2
  exit 1
fi

## Toolchain version is taken from any target's resolved HADRON_TOOLCHAIN_VERSION arg.
toolchain=$(jq -r 'first(.target[] | .args.HADRON_TOOLCHAIN_VERSION // empty) // ""' <<<"$bake")

## Kernel series ("7.3.x") of a Hadron release, read from the ARG KERNEL_VERSION
## in that release's Dockerfile. Cached per release; empty when unknown.
declare -A KSERIES_CACHE=()
kernel_series_of() {
  local ver="$1"
  if [[ -z "${KSERIES_CACHE[$ver]+x}" ]]; then
    KSERIES_CACHE[$ver]=$(curl -fsSL "https://raw.githubusercontent.com/kairos-io/hadron/${ver}/Dockerfile" 2>/dev/null \
      | sed -n 's/^ARG KERNEL_VERSION=\([0-9]*\.[0-9]*\)\..*/\1.x/p' | head -1 || true)
  fi
  printf '%s' "${KSERIES_CACHE[$ver]}"
}

BACKFILL="${BACKFILL:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compat-backfill.json}"

## Add hadron_compat and kernel_compat to every tag of an image.
compat_per_tag() {
  local image="$1" tags="$2" tag labels base ver hc kc out='[]'
  while IFS= read -r tag; do
    labels=$(docker buildx imagetools inspect "${image}:${tag}" --format '{{json .Image}}' 2>/dev/null \
      | jq -c 'if type == "object" then ([.[]? | .config.Labels? // empty] | first) // {} else {} end' 2>/dev/null) || labels='{}'
    [[ -n "$labels" ]] || labels='{}'
    hc=$(jq -r '.["io.kairos.hadron.layer.hadron-compat"] // ""' <<<"$labels")
    kc=$(jq -r '.["io.kairos.hadron.layer.kernel-compat"] // ""' <<<"$labels")
    ## Tags published before the labels existed: the kernel series measured
    ## from the image (its /usr/lib/modules dir) and kept in compat-backfill.json.
    if [[ -z "$kc" && -f "$BACKFILL" ]]; then
      kc=$(jq -r --arg l "${image##*/}" --arg t "$tag" '.[$l][$t] // ""' "$BACKFILL")
    fi
    if [[ -z "$kc" ]]; then
      base=$(jq -r '.["org.opencontainers.image.base.name"] // ""' <<<"$labels")
      ver="${base##*:}"
      [[ "$ver" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && kc=$(kernel_series_of "$ver")
    fi
    out=$(jq --arg tag "$tag" --arg hc "${hc:-*}" --arg kc "${kc:-*}" \
      '. += [{key: $tag, hc: $hc, kc: $kc}]' <<<"$out")
  done < <(jq -r '.[].tag' <<<"$tags")
  jq --argjson c "$out" '
    map(. as $t | ($c | map(select(.key == $t.tag)) | first) as $m
      | . + {hadron_compat: ($m.hc // "*"), kernel_compat: ($m.kc // "*")})' <<<"$tags"
}

layers='[]'
for target in $(jq -r '.target | keys[]' <<<"$bake"); do
  title=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.title"] // $t' <<<"$bake")
  description=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.description"] // ""' <<<"$bake")
  source_url=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.source"] // ""' <<<"$bake")

  ## Provenance: official layers are maintained by the Kairos maintainers and
  ## bumped by the autobumper, community layers are contributed recipes kept on
  ## a best-effort basis. A layer built before the label existed carries no
  ## value, and every one of those is official, so that is the fallback.
  support=$(jq -r --arg t "$target" '
      (.target[$t].labels["io.kairos.hadron.layer.support"] // "")
      | if . == "" then "official" else . end
    ' <<<"$bake")

  ## Informational labels for consumers to filter on. None is enforced at
  ## build time, so a missing or empty value means "no claim": status falls
  ## back to stable, and the compat fields to `*`, any version. The compat
  ## fields are semver range strings (`>=0.6.1`, `==0.6.1`, `0.6.x`) copied
  ## through as text; the consumer evaluates them.
  status=$(jq -r --arg t "$target" '
      (.target[$t].labels["io.kairos.hadron.layer.status"] // "")
      | if . == "" then "stable" else . end
    ' <<<"$bake")
  hadron_compat=$(jq -r --arg t "$target" '
      (.target[$t].labels["io.kairos.hadron.layer.hadron-compat"] // "")
      | if . == "" then "*" else . end
    ' <<<"$bake")
  kernel_compat=$(jq -r --arg t "$target" '
      (.target[$t].labels["io.kairos.hadron.layer.kernel-compat"] // "")
      | if . == "" then "*" else . end
    ' <<<"$bake")

  ## Strip the tag from the first bake tag entry to recover the bare image name.
  first_tag=$(jq -r --arg t "$target" '.target[$t].tags[0] // ""' <<<"$bake")
  image="${first_tag%:*}"

  ## The GHCR package name is the image path under the org namespace, e.g.
  ## `ghcr.io/kairos-io/hadron-layers/git` -> `hadron-layers/git`. Fall back to
  ## the image basename if the expected `ghcr.io/<namespace>/` prefix is absent.
  pkg="${image#ghcr.io/${NAMESPACE}/}"
  if [[ -z "$pkg" || "$pkg" == "$image" ]]; then
    pkg=$(basename "$image")
  fi

  ## Path segments must be URL-encoded for the packages API (a nested package
  ## name like `hadron-layers/git` needs its slash escaped to `%2F`).
  pkg_enc="${pkg//\//%2F}"

  echo "  - ${target}: querying versions for ${NAMESPACE}/${pkg}..." >&2

  ## Fetch every published version. --paginate walks all pages.
  ## metadata.container.tags is an array (one image can carry multiple tags),
  ## expand into one entry per tag so the UI can present a flat history.
  if ! versions_raw=$(gh api --paginate "/orgs/${NAMESPACE}/packages/container/${pkg_enc}/versions" 2>/dev/null); then
    echo "    (failed to query versions — package private, missing, or token lacks read:packages)" >&2
    versions_raw='[]'
  fi

  tags=$(jq '[
      .[]
      | . as $v
      | (.metadata.container.tags // [])[]
      | {tag: ., digest: $v.name, created: $v.created_at, sysext: {}}
    ] | sort_by(.created) | reverse' <<<"$versions_raw")

  ## Sysext artifacts use a separate nested package and architecture-suffixed
  ## tags. A missing package is expected while artifacts are being introduced,
  ## so leave the layer tags intact with an empty sysext object.
  sysext_pkg="hadron-layers/sysext/${target}"
  sysext_pkg_enc="${sysext_pkg//\//%2F}"
  if ! sysext_raw=$(gh api --paginate "/orgs/${NAMESPACE}/packages/container/${sysext_pkg_enc}/versions" 2>/dev/null); then
    echo "    (no sysext package found for ${target})" >&2
    sysext_raw='[]'
  fi

  sysext_entries=$(jq --arg image "ghcr.io/${NAMESPACE}/${sysext_pkg}" '[
      .[]
      | . as $v
      | (.metadata.container.tags // [])[]
      | capture("^(?<version>.*)-(?<arch>amd64|arm64)$")?
      | select(. != null)
      | {version, arch, oci: ($image + "@" + $v.name)}
    ]' <<<"$sysext_raw")

  tags=$(jq --argjson artifacts "$sysext_entries" '
    map(. as $tag
      | .sysext = (reduce ($artifacts[] | select(.version == $tag.tag)) as $artifact
          ({}; .[$artifact.arch] = {oci: $artifact.oci})))
  ' <<<"$tags")

  ## Compat is a property of each published tag, not of the layer: drbd 9.3.4
  ## was built for one kernel series and a later tag for another. Read the
  ## labels from the published image itself. A tag built before the labels
  ## existed has none, so derive the kernel series from the Hadron release its
  ## toolchain base image names; if that fails the tag makes no claim ("*").
  tags=$(compat_per_tag "$image" "$tags")

  ## "Latest" is the highest-semver tag if any parse as semver, else the newest by date.
  latest=$(jq -r '
      (map(select(.tag | test("^[0-9]+(\\.[0-9]+)*$")))
        | sort_by(.tag | split(".") | map(tonumber))
        | reverse
        | .[0].tag)
      // (.[0].tag // "")
    ' <<<"$tags")

  ## The layer-level fields describe the latest tag; the bake labels are only
  ## the fallback for a layer with no published tag yet.
  latest_compat=$(jq -c --arg l "$latest" 'map(select(.tag == $l)) | first // empty | [.hadron_compat, .kernel_compat]' <<<"$tags")
  if [[ -n "$latest_compat" ]]; then
    hadron_compat=$(jq -r '.[0]' <<<"$latest_compat")
    kernel_compat=$(jq -r '.[1]' <<<"$latest_compat")
  fi

  layers=$(jq \
    --arg name "$target" \
    --arg title "$title" \
    --arg description "$description" \
    --arg image "$image" \
    --arg source "$source_url" \
    --arg support "$support" \
    --arg status "$status" \
    --arg hadron_compat "$hadron_compat" \
    --arg kernel_compat "$kernel_compat" \
    --arg latest "$latest" \
    --argjson tags "$tags" \
    '. += [{
      name: $name,
      title: $title,
      description: $description,
      image: $image,
      source: $source,
      support: $support,
      status: $status,
      hadron_compat: $hadron_compat,
      kernel_compat: $kernel_compat,
      latest: $latest,
      tags: $tags
    }]' <<<"$layers")
done

jq -n \
  --arg repo "$REPO" \
  --arg toolchain "$toolchain" \
  --argjson layers "$layers" \
  '{
    generated: (now | todate),
    repo: $repo,
    toolchain: $toolchain,
    layers: ($layers | sort_by(.name))
  }' > "$OUT"

count=$(jq '.layers | length' "$OUT")
tag_count=$(jq '[.layers[].tags | length] | add // 0' "$OUT")
echo "Wrote ${count} layer(s) with ${tag_count} total tag(s) to ${OUT}" >&2
