# containerd-shim-wasmtime (runwasi) packaged as a Hadron layer, so k3s can run
# WebAssembly workloads with `runtimeClassName: wasmtime`.
#
# k3s scans PATH for containerd shims it knows by name when it starts, adds
# them to the containerd config it generates and points the matching
# RuntimeClass at them. The binary must therefore be named
# containerd-shim-wasmtime-v1 and live in /usr/bin: under any other name k3s
# ignores it. /usr also keeps the layer usable as a system extension, where
# only /usr and /opt are merged.
#
# Upstream publishes static musl builds for x86_64 and aarch64, which drop
# straight onto Hadron, so nothing is compiled here. updatecli tracks
# WASMTIME_SHIM_VERSION, see updatecli.d/containerd-shim-wasmtime.yaml.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS fetch

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG WASMTIME_SHIM_VERSION=0.6.1
ARG TARGETARCH

WORKDIR /build

# Release assets are named after the kernel architecture, not Docker's.
RUN case "${TARGETARCH}" in \
      amd64) echo x86_64 > arch ;; \
      arm64) echo aarch64 > arch ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac

RUN curl -fsSLO "https://github.com/containerd/runwasi/releases/download/containerd-shim-wasmtime/v${WASMTIME_SHIM_VERSION}/containerd-shim-wasmtime-$(cat arch)-linux-musl.tar.gz"

# runwasi publishes a SHA256SUMS file with every release, so the download is
# checked against the release it names without pinning a checksum here.
RUN curl -fsSLO "https://github.com/containerd/runwasi/releases/download/containerd-shim-wasmtime/v${WASMTIME_SHIM_VERSION}/SHA256SUMS"
RUN grep " containerd-shim-wasmtime-$(cat arch)-linux-musl.tar.gz\$" SHA256SUMS | sha256sum -c -

RUN mkdir -p /output/usr/bin && \
    tar -xzf "containerd-shim-wasmtime-$(cat arch)-linux-musl.tar.gz" -C /output/usr/bin ./containerd-shim-wasmtime-v1

# Final layer: one static binary. Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/containerd-shim-wasmtime:TAG / /
# Or declare the system extension published alongside it, see the README.
FROM scratch AS default
COPY --from=fetch /output/ /

# Offline checks against a Hadron base image. The shim only does useful work
# when containerd starts it, so the test checks what k3s depends on: the exact
# name, the location in PATH, and that the file is executable.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /
RUN test -x /usr/bin/containerd-shim-wasmtime-v1
RUN [ "$(command -v containerd-shim-wasmtime-v1)" = /usr/bin/containerd-shim-wasmtime-v1 ]
