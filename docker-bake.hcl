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
  platforms = ["linux/amd64", "linux/arm64"]
  tags      = ["${REGISTRY}/hadron-layer-fwupd:${TAG}"]
}
