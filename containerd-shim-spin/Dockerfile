# containerd-shim-spin packaged as a Hadron layer, so k3s can run Spin
# WebAssembly applications with `runtimeClassName: spin`.
#
# k3s scans PATH for containerd shims it knows by name when it starts, adds
# them to the containerd config it generates and points the matching
# RuntimeClass at them. The binary must therefore be named
# containerd-shim-spin-v2 and live in /usr/bin: under any other name k3s
# ignores it. /usr also keeps the layer usable as a system extension, where
# only /usr and /opt are merged.
#
# Upstream publishes static builds for x86_64 and aarch64, which drop straight
# onto Hadron, so nothing is compiled here. updatecli tracks SPIN_SHIM_VERSION,
# see updatecli.d/containerd-shim-spin.yaml.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS fetch

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG SPIN_SHIM_VERSION=0.27.2
ARG TARGETARCH

WORKDIR /build

# Release assets are named after the kernel architecture, not Docker's.
RUN case "${TARGETARCH}" in \
      amd64) echo x86_64 > arch ;; \
      arm64) echo aarch64 > arch ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac

# The Spin shim releases publish no checksum file. GitHub records a SHA-256
# digest for every release asset, but reading it needs the API at build time,
# so the download relies on HTTPS from the release, as the tailscale layer does
# for its source tarball.
RUN curl -fsSLO "https://github.com/spinframework/containerd-shim-spin/releases/download/v${SPIN_SHIM_VERSION}/containerd-shim-spin-v2-linux-$(cat arch).tar.gz"

RUN mkdir -p /output/usr/bin && \
    tar -xzf "containerd-shim-spin-v2-linux-$(cat arch).tar.gz" -C /output/usr/bin containerd-shim-spin-v2

# Final layer: one static binary. Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/containerd-shim-spin:TAG / /
# Or declare the system extension published alongside it, see the README.
FROM scratch AS default
COPY --from=fetch /output/ /

# Offline checks against a Hadron base image. The shim only does useful work
# when containerd starts it, so the test checks what k3s depends on: the exact
# name, the location in PATH, and that the file is executable.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /
RUN test -x /usr/bin/containerd-shim-spin-v2
RUN [ "$(command -v containerd-shim-spin-v2)" = /usr/bin/containerd-shim-spin-v2 ]
