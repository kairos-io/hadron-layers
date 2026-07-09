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
##         "latest": "2.52.0",
##         "tags": [
##           {"tag": "2.52.0", "digest": "sha256:...", "created": "..."}
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

layers='[]'
for target in $(jq -r '.target | keys[]' <<<"$bake"); do
  title=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.title"] // $t' <<<"$bake")
  description=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.description"] // ""' <<<"$bake")
  source_url=$(jq -r --arg t "$target" '.target[$t].labels["org.opencontainers.image.source"] // ""' <<<"$bake")

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
      | {tag: ., digest: $v.name, created: $v.created_at}
    ] | sort_by(.created) | reverse' <<<"$versions_raw")

  ## "Latest" is the highest-semver tag if any parse as semver, else the newest by date.
  latest=$(jq -r '
      (map(select(.tag | test("^[0-9]+(\\.[0-9]+)*$")))
        | sort_by(.tag | split(".") | map(tonumber))
        | reverse
        | .[0].tag)
      // (.[0].tag // "")
    ' <<<"$tags")

  layers=$(jq \
    --arg name "$target" \
    --arg title "$title" \
    --arg description "$description" \
    --arg image "$image" \
    --arg source "$source_url" \
    --arg latest "$latest" \
    --argjson tags "$tags" \
    '. += [{
      name: $name,
      title: $title,
      description: $description,
      image: $image,
      source: $source,
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
