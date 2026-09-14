# Tailscale (tailscaled + the tailscale CLI) packaged as a Hadron layer.
#
# Unlike every other layer here, Tailscale is written in Go, and the
# hadron-toolchain image is a musl *C* toolchain that deliberately ships no Go
# (each C package it builds is configured with GOLANG=no). The build stage
# therefore uses the upstream golang image with CGO_ENABLED=0, which is how
# Tailscale builds its own static release binaries too. The result is two
# statically linked binaries with no libc dependency, so the final layer needs
# nothing from the toolchain and drops straight onto Hadron.
#
# Renovate tracks the golang tag on the FROM line below; updatecli tracks
# TAILSCALE_VERSION, see updatecli.d/tailscale.yaml.

ARG HADRON_VERSION

FROM golang:1.27.1-alpine AS builder

# Tailscale releases stable versions on even minor numbers (1.100.x, 1.102.x);
# odd minors are development tags such as v1.103.0-pre. updatecli only offers
# even minors.
ARG TAILSCALE_VERSION=1.102.3
ARG TARGETARCH

WORKDIR /build
RUN wget -q -O tailscale.tar.gz \
      "https://github.com/tailscale/tailscale/archive/refs/tags/v${TAILSCALE_VERSION}.tar.gz" && \
    tar -xf tailscale.tar.gz && rm tailscale.tar.gz && mv tailscale-* src
WORKDIR /build/src

# CGO_ENABLED=0 makes the binaries fully static, so there is no musl/glibc
# split to reconcile between this builder and the Hadron base image.
# Tailscale's systemd (sd_notify) and DNS integrations are pure Go, so nothing
# is lost. The version stamps are what `tailscale version` reports; without
# them a build from a source tarball reports "date.YYYYMMDD" instead, because
# the tarball carries no VCS metadata. -s -w drops the symbol table and DWARF,
# roughly halving both binaries.
ENV CGO_ENABLED=0 GOOS=linux
RUN set -eux; \
    stamps="-s -w \
      -X tailscale.com/version.longStamp=${TAILSCALE_VERSION} \
      -X tailscale.com/version.shortStamp=${TAILSCALE_VERSION}"; \
    GOARCH="${TARGETARCH}" go build -trimpath -ldflags "${stamps}" \
      -o /output/usr/sbin/tailscaled ./cmd/tailscaled; \
    GOARCH="${TARGETARCH}" go build -trimpath -ldflags "${stamps}" \
      -o /output/usr/bin/tailscale ./cmd/tailscale

# Service wiring. Everything lives under /usr so this layer works unchanged as
# a system extension, where only /usr and /opt are merged. The unit is enabled
# statically from /usr (the same thing a vendor preset does) because a sysext
# cannot create the /etc/systemd/system/multi-user.target.wants symlink that
# `systemctl enable` would.
COPY files/ /output/
RUN mkdir -p /output/usr/lib/systemd/system/multi-user.target.wants && \
    ln -sf ../tailscaled.service \
      /output/usr/lib/systemd/system/multi-user.target.wants/tailscaled.service

# Final layer: two static binaries plus the service wiring. Use as a layer on
# top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/tailscale:TAG / /
# Or pull the system extension published alongside it, see the README.
#
# There is no merge/strip stage: `go build` emits only the two binaries, so
# there are no headers, static libs, man pages or docs to strip.
FROM scratch AS default
COPY --from=builder /output/ /

# Smoke-test the built layer against a Hadron base image. Any RUN failure here
# fails the build and gates the release step in CI. Kept fully offline so the
# test is deterministic: tailscaled runs in userspace-networking mode, which
# needs neither /dev/net/tun nor a reachable tailnet.
# HADRON_VERSION is pinned centrally in docker-bake.hcl and bumped by Renovate
# when a newer semver tag is published to GHCR.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /

# The stamps are linker-set, so a bare "1.2.3" proves both that the binary
# starts and that the ldflags landed on the symbols they name.
RUN /usr/bin/tailscale version | head -1 | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
RUN /usr/sbin/tailscaled --version | head -1 | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'

# Exercise the daemon and the CLI-to-daemon IPC over the local socket.
# `status` exits non-zero while logged out, which is the expected state here,
# so assert on its JSON instead: BackendState is the daemon's own view of
# itself and only appears once the IPC round trip worked.
RUN set -eux; \
    mkdir -p /tmp/tsstate; \
    /usr/sbin/tailscaled \
      --tun=userspace-networking \
      --state=/tmp/tsstate/tailscaled.state \
      --socket=/tmp/tailscaled.sock \
      --port=0 >/tmp/tailscaled.log 2>&1 & \
    i=0; \
    while [ "$i" -lt 30 ]; do \
      [ -S /tmp/tailscaled.sock ] && break; \
      i=$((i+1)); \
      sleep 1; \
    done; \
    if [ ! -S /tmp/tailscaled.sock ]; then cat /tmp/tailscaled.log; exit 1; fi; \
    /usr/bin/tailscale --socket=/tmp/tailscaled.sock status --json >/tmp/status.json || true; \
    grep -q '"BackendState"' /tmp/status.json

# The service wiring is what makes this usable as a sysext, so assert the two
# properties a sysext depends on: the unit must not require anything in /etc,
# and it must be enabled from /usr. `test -f` follows the symlink, so it also
# proves the link target resolves.
RUN grep -q '^EnvironmentFile=-/etc/default/tailscaled' \
      /usr/lib/systemd/system/tailscaled.service
RUN test -f /usr/lib/systemd/system/multi-user.target.wants/tailscaled.service
RUN test -x /usr/sbin/tailscaled

# The tmpfiles drop-in seeds the override file from the factory copy under
# /usr, which is the only way a sysext can populate /etc.
RUN systemd-tmpfiles --create tailscaled.conf && \
    grep -q '^PORT=' /etc/default/tailscaled

# Tailscale shells out to iptables for its netfilter rules unless it is run
# with --netfilter-mode=off, so confirm the base image really provides it.
# Hadron builds iptables with --enable-nftables --disable-legacy-utils, so
# accept either front-end name rather than pinning the symlink layout.
RUN iptables --version || iptables-nft --version
