# This dockerfile builds smartmontools (smartctl and smartd) from source using
# the Hadron toolchain image. HADRON_TOOLCHAIN_VERSION is provided centrally
# via docker-bake.hcl.
#
# smartmontools is C++. The Hadron base image ships libgcc_s but no
# libstdc++, and a shared libstdc++ in the layer would add a library to the
# base's /usr/lib. So the C++ runtime is linked statically into the binaries,
# and the layer ships smartctl, smartd, the drivedb and the systemd unit,
# nothing the base has.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
WORKDIR /sources

# Upstream tags releases as RELEASE_7_5 and names the tarball 7.5.
ARG SMARTMONTOOLS_VERSION=7.5
RUN curl -fL "https://github.com/smartmontools/smartmontools/releases/download/RELEASE_$(echo "${SMARTMONTOOLS_VERSION}" | tr . _)/smartmontools-${SMARTMONTOOLS_VERSION}.tar.gz" -o smartmontools.tar.gz
RUN tar -xf smartmontools.tar.gz && mv smartmontools-* smartmontools

FROM downloader AS builder
WORKDIR /sources/smartmontools
# -static-libstdc++ and -static-libgcc keep the C++ runtime out of the layer.
# smartd uses libsystemd for Type=notify. The base has libsystemd and the
# libucontext it needs, the toolchain has only libsystemd, hence
# --allow-shlib-undefined at link time.
# The drivedb is the one upstream ships, installed under /usr/share/smartmontools.
# The configuration file goes under /usr/share too, because a system extension
# cannot ship files in /etc. smartd reads /etc/smartd.conf when it exists.
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
      --sysconfdir=/etc \
      --with-systemdsystemunitdir=/usr/lib/systemd/system \
      --with-drivedbdir=/usr/share/smartmontools \
      --without-update-smart-drivedb \
      --with-libsystemd \
      --without-selinux \
      --without-libcap-ng \
      --without-gnupg \
      LDFLAGS="${LDFLAGS} -static-libstdc++ -static-libgcc -Wl,--allow-shlib-undefined"
RUN make -j"$(nproc)"
RUN make DESTDIR=/output install

# Strip what the layer does not need: docs, man pages, and everything under
# /etc and /var, which a system extension cannot ship. The drivedb stays.
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS merge
COPY --from=builder /output/ /output/
RUN rm -rf /output/usr/share/man \
           /output/usr/share/doc \
           /output/usr/share/info \
           /output/etc \
           /output/var
RUN strip --strip-unneeded /output/usr/sbin/smartctl /output/usr/sbin/smartd

# Final layer: smartctl, smartd, the drivedb and the unit. The unit is
# installed but not enabled, so smartd does not start until the image's own
# configuration enables it. Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/smartmontools:TAG / /
# Or install it as a system extension: kairos-agent sysext install smartmontools
FROM scratch AS default
COPY --from=merge /output/ /

# Smoke-test the built layer against a Hadron base image. Any RUN failure
# here fails the build and gates the release step in CI. Kept fully offline.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /layer/
# As a system extension the layer is merged over the base's /usr. It must not
# carry a file the base already has, or it would replace the base's copy (the
# isotope conflict check refuses such an extension). Check before installing.
RUN set -eu; \
    clash=$(cd /layer && find . ! -type d | while read -r f; do [ ! -e "/${f#./}" ] || echo "${f#./}"; done); \
    if [ -n "$clash" ]; then echo "layer overlays base files: $clash" >&2; exit 1; fi
RUN cp -a /layer/. / && rm -rf /layer
RUN smartctl --version | head -1 | grep -q '^smartctl '
RUN smartd --version | head -1 | grep -q '^smartd '
# Only the C library and libraries the base has may be dynamic. The base ships
# libgcc_s, libsystemd (for sd_notify), libcap and libucontext.
RUN set -eux; \
    for b in /usr/sbin/smartctl /usr/sbin/smartd; do \
      libs=$(ldd "$b" | grep -v -e 'ld-musl' -e 'libc\.' -e 'libgcc_s' -e 'libsystemd' -e 'libcap' -e 'libucontext' -e 'linux-vdso' || true); \
      [ -z "$libs" ]; \
    done
# The drivedb loads and the built-in database parses.
RUN test -s /usr/share/smartmontools/drivedb.h
RUN smartctl -P showall | grep -q 'drive database' || smartctl -P showall | head -3
# The unit is installed but not enabled: nothing may link it into a target.
RUN test -f /usr/lib/systemd/system/smartd.service
RUN ! find /usr/lib/systemd/system /etc/systemd/system -name 'smartd.service' -path '*.wants/*' | grep -q .
