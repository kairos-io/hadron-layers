#!/usr/bin/env bash

set -euo pipefail

root=${1:?usage: materialize-hardlinks.sh ROOT}

find "$root" -type f -links +1 -print0 |
  while IFS= read -r -d '' file; do
    replacement=$(mktemp --tmpdir="$(dirname -- "$file")" ".$(basename -- "$file").materialized.XXXXXX")
    if ! cp --preserve=all --reflink=never "$file" "$replacement"; then
      rm -f -- "$replacement"
      exit 1
    fi
    mv "$replacement" "$file"
  done
