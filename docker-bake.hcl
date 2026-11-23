# docker-bake.hcl — central build configuration for all hadron layers.
#
# HADRON_VERSION is the single source of truth for the Hadron release every
# layer is built and tested against. It names both the hadron-toolchain image a
# layer is built from and the hadron base image its test stage runs on. The two
# images come from the same Hadron release and carry the same compiler, musl
# and libraries, so a layer built against one must be tested on the other.
# Update it here (or let updatecli do it) and every layer picks it up on the
# next build. The Dockerfiles still take it as two build arguments,
# HADRON_TOOLCHAIN_VERSION and HADRON_VERSION, which this file sets to the same
# value.
variable "HADRON_VERSION" {
  default = "v0.6.7"
}

# HADRON_KERNEL_SERIES is the kernel series the HADRON_VERSION release ships
# (v0.6.7 ships kernel 7.3.5). The kernel module layers (drbd) put it in their
# kernel-compat label. updatecli moves it together with HADRON_VERSION, from
# the KERNEL_VERSION of the Hadron release (updatecli.d/toolchain.yaml).
variable "HADRON_KERNEL_SERIES" {
  default = "7.3.x"
}

# ZFS_HADRON_VERSION pins the zfs layer to the Hadron release whose kernel it
# is built against, apart from HADRON_VERSION. OpenZFS 2.4.4, the newest
# release, supports kernels up to 7.2 (META: Linux-Maximum 7.2); Hadron v0.6.2
# and later ship kernel 7.3.x, which no OpenZFS release supports yet. v0.6.1
# (kernel 7.2.11) is the newest Hadron release 2.4.4 can be built against.
# updatecli tracks HADRON_VERSION by exact name and leaves this one alone.
# Move it when OpenZFS releases a version that supports the kernel of a newer
# Hadron.
variable "ZFS_HADRON_VERSION" {
  default = "v0.6.1"
}

# ZFS_KERNEL_SERIES is the kernel series ZFS_HADRON_VERSION ships (7.2.11 for
# v0.6.1). updatecli leaves it alone like ZFS_HADRON_VERSION, so move the two
# together by hand.
variable "ZFS_KERNEL_SERIES" {
  default = "7.2.x"
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

# PLATFORMS is the set of target platforms every layer is built for. Override
# per-target with `--set <target>.platform=linux/amd64` when needed; bake's
# variable-override syntax doesn't support list-typed variables.
variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

# common_labels returns the OCI image labels shared by every layer. The
# per-layer title and description are merged in at the target level.
#
# `support` records who keeps the recipe working: `official` for a layer the
# Kairos maintainers maintain, which has an updatecli.d manifest and a row in
# the autobumper matrix so breakage blocks the build, and `community` for a
# contributed recipe carried on a best-effort basis. Both are built, tested and
# published by the same CI, so the vendor label stays Kairos either way; this
# label is about maintenance, not about who distributes the image.
#
# A target can add informational labels with merge(), the way zfs overrides
# base.name. None is required, and a missing one means "no claim":
#   io.kairos.hadron.layer.status         stable, beta or alpha (default stable)
#   io.kairos.hadron.layer.hadron-compat  semver range of Hadron, e.g. ">=0.6.1" (default *)
#   io.kairos.hadron.layer.kernel-compat  semver range of the kernel (default *)
function "common_labels" {
  params = [title, description, support]
  result = {
    "org.opencontainers.image.title"       = title
    "org.opencontainers.image.description" = description
    "org.opencontainers.image.source"      = REPO_URL
    "org.opencontainers.image.url"         = REPO_URL
    "org.opencontainers.image.vendor"      = "Kairos"
    "org.opencontainers.image.base.name"   = "ghcr.io/kairos-io/hadron-toolchain:${HADRON_VERSION}"
    "io.kairos.hadron.layer.support"       = support
  }
}

group "default" {
  targets = ["git", "gpg", "fwupd", "drbd", "zfs", "tailscale", "htop", "smartmontools", "qemu-guest-agent", "containerd-shim-wasmtime", "containerd-shim-spin"]
}

target "git" {
  context    = "git"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("git", "Git version control system", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/git:${TAG}"]
}

target "gpg" {
  context    = "gpg"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("gpg", "GnuPG and its runtime libraries", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/gpg:${TAG}"]
}

target "fwupd" {
  context    = "fwupd"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("fwupd", "Firmware update daemon", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/fwupd:${TAG}"]
}

target "drbd" {
  context    = "drbd"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
  }
  labels = merge(
    common_labels("drbd", "Out-of-tree DRBD 9 kernel module and drbd-utils", "official"),
    {
      # The module is built for the kernel of the toolchain image and only
      # loads on a Hadron that ships a kernel of the same series.
      "io.kairos.hadron.layer.kernel-compat" = HADRON_KERNEL_SERIES
    },
  )
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/drbd:${TAG}"]
}

target "zfs" {
  context    = "zfs"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = ZFS_HADRON_VERSION
    HADRON_VERSION           = ZFS_HADRON_VERSION
  }
  labels = merge(
    common_labels("zfs", "OpenZFS kernel module and userspace tools", "official"),
    {
      "org.opencontainers.image.base.name" = "ghcr.io/kairos-io/hadron-toolchain:${ZFS_HADRON_VERSION}"
      # The module is built for the kernel of the toolchain image and only
      # loads on a Hadron that ships a kernel of the same series.
      "io.kairos.hadron.layer.kernel-compat" = ZFS_KERNEL_SERIES
    },
  )
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/zfs:${TAG}"]
}

target "htop" {
  context    = "htop"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("htop", "Interactive process viewer", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/htop:${TAG}"]
}

target "smartmontools" {
  context    = "smartmontools"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("smartmontools", "Disk health tools: smartctl and the smartd daemon", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/smartmontools:${TAG}"]
}

target "qemu-guest-agent" {
  context    = "qemu-guest-agent"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("qemu-guest-agent", "QEMU guest agent (qemu-ga) for virtual machines", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/qemu-guest-agent:${TAG}"]
}

# Tailscale builds from the upstream golang image rather than the toolchain
# (see tailscale/Dockerfile), so it takes no HADRON_TOOLCHAIN_VERSION.
target "tailscale" {
  context    = "tailscale"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_VERSION = HADRON_VERSION
  }
  # Spelled out rather than using common_labels(): that helper hardcodes
  # org.opencontainers.image.base.name to the toolchain image, which this
  # layer is not built from.
  #
  # The golang tag below is the only version in this file that is not a
  # variable, so it is also the only one that can fall behind the Dockerfile it
  # describes. It must stay equal to the builder FROM in tailscale/Dockerfile.
  # updatecli.d/golang.yaml moves both in one pull request, and build_test.sh
  # fails the build if they ever differ.
  labels = {
    "org.opencontainers.image.title"       = "tailscale"
    "org.opencontainers.image.description" = "Tailscale node agent (tailscaled) and CLI"
    "org.opencontainers.image.source"      = REPO_URL
    "org.opencontainers.image.url"         = REPO_URL
    "org.opencontainers.image.vendor"      = "Kairos"
    "org.opencontainers.image.base.name"   = "docker.io/library/golang:1.27.4-alpine"
    "io.kairos.hadron.layer.support"       = "official"
  }
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/tailscale:${TAG}"]
}

target "containerd-shim-wasmtime" {
  context    = "containerd-shim-wasmtime"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("containerd-shim-wasmtime", "containerd shim for WebAssembly workloads on wasmtime (runwasi)", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/containerd-shim-wasmtime:${TAG}"]
}

target "containerd-shim-spin" {
  context    = "containerd-shim-spin"
  dockerfile = "Dockerfile"
  target     = "default"
  args = {
    HADRON_TOOLCHAIN_VERSION = HADRON_VERSION
    HADRON_VERSION           = HADRON_VERSION
  }
  labels    = common_labels("containerd-shim-spin", "containerd shim for Spin WebAssembly applications", "official")
  platforms = PLATFORMS
  tags      = ["${REGISTRY}/containerd-shim-spin:${TAG}"]
}
