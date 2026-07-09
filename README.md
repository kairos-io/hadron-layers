# hadron-layers

A collection of pre-built layers for [Hadron](https://github.com/kairos-io/hadron). Each layer compiles a software component from source using the Hadron toolchain and publishes a minimal OCI image containing only the runtime binaries and their shared-library dependencies.

Images are published to `ghcr.io/kairos-io/hadron-layers/<name>` and are indexed with copy-ready pull commands, tag history and pinned digests at [kairos-io.github.io/hadron-layers](https://kairos-io.github.io/hadron-layers/) (raw data at [`releases.json`](https://kairos-io.github.io/hadron-layers/releases.json), individual layer pages at `#/<layer>` and `#/<layer>/<tag>`).

They can be used to extend a Hadron base system:

```dockerfile
FROM ghcr.io/kairos-io/hadron:VERSION
COPY --from=ghcr.io/kairos-io/hadron-layers/git:latest / /
```

Or to create a sysextension with [Auroraboot](https://github.com/kairos-io/auroraboot).

## Available layers

| Layer | Image | Description |
|-------|-------|-------------|
| `git` | `ghcr.io/kairos-io/hadron-layers/git` | Git version control system |
| `gpg` | `ghcr.io/kairos-io/hadron-layers/gpg` | GnuPG and its runtime libraries |
| `fwupd` | `ghcr.io/kairos-io/hadron-layers/fwupd` | Firmware update daemon |

## How it works

Each layer lives in its own subdirectory (e.g. `git/Dockerfile`) and follows this pattern:

1. **Build stage** – compiles from source using `ghcr.io/kairos-io/hadron-toolchain`.
2. **Merge stage** – collects all build outputs, then strips dev artifacts (headers `*.h`, static libs `*.a`, libtool archives `*.la`, pkg-config files `*.pc`, man pages, docs). Only runtime files remain.
3. **Final `default` stage** – `FROM scratch`, copying the filtered output. This is the published image.
4. **`test` stage** – `FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION}`, layered with `default`, runs offline smoke tests (`RUN`) that exercise the built binaries. CI builds this stage first (amd64 only); if any `RUN` fails, the release build is skipped.

## Toolchain and base versions

`HADRON_TOOLCHAIN_VERSION` (used by every layer's build stage) and `HADRON_VERSION` (used by every layer's test stage) are both defined **once** in [`docker-bake.hcl`](docker-bake.hcl). Updatecli bumps `HADRON_TOOLCHAIN_VERSION` and Renovate bumps `HADRON_VERSION` — no Dockerfile needs touching. All layers pick up the new versions on the next build.

## Automation

- **Build & publish** – `.github/workflows/build.yml` runs on every push to `main` via `docker buildx bake`, building multi-arch images (`linux/amd64`, `linux/arm64`) and pushing to GHCR.
- **Version bumping** – `.github/workflows/autobumper.yml` runs daily, using [updatecli](https://www.updatecli.io/) to open PRs for new upstream releases (toolchain, git, gpg, fwupd dependencies). Renovate handles action pins and other dependencies.
- **Auto-approve** – `.github/workflows/autoapprove.yml` automatically approves and enables squash-merge on PRs opened by the updatecli bots (`github-actions[bot]`, `ci-robbot`) and Renovate (`renovate[bot]`).
- **Releases page** – `.github/workflows/pages.yml` regenerates [`releases.json`](https://kairos-io.github.io/hadron-layers/releases.json) from the GHCR package versions API and deploys `site/index.html` to GitHub Pages after every successful main/tag build.

## Adding a new layer

1. Create a new directory (e.g. `myapp/`) with a `Dockerfile` that follows the build → merge → `FROM scratch AS default` → `ARG HADRON_VERSION` + `FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test` pattern. The `test` stage must `COPY --from=default / /` and add offline `RUN` steps that exercise the shipped binaries.
2. Add a target to `docker-bake.hcl` passing `HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION` and `HADRON_VERSION = HADRON_VERSION`, plus OCI labels via `common_labels("myapp", "One-line description")` (the description surfaces on the releases page).
3. Add an updatecli config under `updatecli.d/myapp.yaml` to track upstream releases.
4. Add `myapp` to the `matrix.config` list in `.github/workflows/autobumper.yml`.

The releases page auto-discovers layers from `docker-bake.hcl`, so no site edits are needed.
