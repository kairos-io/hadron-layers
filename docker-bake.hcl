# docker-bake.hcl — central build configuration for all hadron layers.
#
# HADRON_TOOLCHAIN_VERSION is the single source of truth for the toolchain
# version used across every layer Dockerfile. Update it here (or let updatecli
# do it automatically) and all layers will pick up the new version on the next
# build.

variable "HADRON_TOOLCHAIN_VERSION" {
  default = "v0.4.0"
}

variable "REGISTRY" {
  default = "ghcr.io/kairos-io"
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
  }
  labels    = common_labels("hadron-layer-git", "Git version control system")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/hadron-layer-git:${TAG}"]
}

target "gpg" {
  context    = "gpg"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION
  }
  labels    = common_labels("hadron-layer-gpg", "GnuPG and its runtime libraries")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/hadron-layer-gpg:${TAG}"]
}

target "fwupd" {
  context    = "fwupd"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_TOOLCHAIN_VERSION
  }
  labels    = common_labels("hadron-layer-fwupd", "Firmware update daemon")
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/hadron-layer-fwupd:${TAG}"]
}
