# docker-bake.hcl — central build configuration for all hadron layers.
#
# HADRON_TOOLCHAIN_VERSION is the single source of truth for the toolchain
# version used across every layer Dockerfile. Update it here (or let updatecli
# do it automatically) and all layers will pick up the new version on the next
# build.

variable "HADRON_TOOLCHAIN_VERSION" {
  default = "v0.5.1"
}

# HADRON_VERSION is the tag of the Hadron base image used by every layer's
# test stage. Renovate tracks this variable via the custom manager in
# renovate.json and opens PRs when a newer semver tag is published to GHCR.
variable "HADRON_VERSION" {
  default = "v0.5.1"
}

variable "REGISTRY" {
  default = "ghcr.io/kairos-io/hadron-layers"
}

variable "TAG" {
  default = "latest"
}

variable "REPO_URL" {
  default = "https://github.com/kairos-io/hadron-layers"
}

# common_labels returns the OCI image labels shared by every layer. The
# per-layer title and description are merged in at the target level.
function "common_labels" {
  params = [title, description]
  result = {
    "org.opencontainers.image.title"       = title
    "org.opencontainers.image.description" = description
    "org.opencontainers.image.source"      = REPO_URL
    "org.opencontainers.image.url"         = REPO_URL
    "org.opencontainers.image.vendor"      = "Kairos"
    "org.opencontainers.image.base.name"   = "ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION}"
  }
}

group "default" {
  targets = ["git", "gpg", "fwupd"]
}

target "git" {
  context    = "git"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("git", "Git version control system")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/git:${TAG}"]
}

target "gpg" {
  context    = "gpg"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("gpg", "GnuPG and its runtime libraries")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/gpg:${TAG}"]
}

target "fwupd" {
  context    = "fwupd"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("fwupd", "Firmware update daemon")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/fwupd:${TAG}"]
}
