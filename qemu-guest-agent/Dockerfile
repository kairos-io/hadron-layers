# This dockerfile builds qemu-ga, the QEMU guest agent, from source using the
# Hadron toolchain image. HADRON_TOOLCHAIN_VERSION is provided centrally via
# docker-bake.hcl.
#
# The build follows the qemu-guest-agent stage of kairos-io/hadron's
# Dockerfile: only the qemu-ga target, with --enable-guest-agent --disable-tcg.
#
# qemu-ga needs glib. The Hadron base image ships no glib, libffi or pcre2, and
# a shared glib in the layer would put new libraries next to the base's own
# when merged as a system extension. So glib and the two libraries it needs
# are built as static libraries only, linked into qemu-ga, and the layer ships
# the qemu-ga binary and its systemd unit, nothing the base has.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION
# QEMU, glib, pcre2 and libffi come from the checksummed source cache that
# Hadron itself builds from. QEMU_AGENT_VERSION is the version Hadron pins as
# QEMU_AGENT_VERSION in its Dockerfile. The others are the versions Hadron
# builds its own glib with, so they exist in the cache.
ARG QEMU_AGENT_VERSION=11.1.3
ARG GLIB_VERSION=2.90.1
ARG PCRE2_VERSION=10.49
ARG LIBFFI_VERSION=3.8.1

FROM ghcr.io/kairos-io/hadron-sources/qemu:${QEMU_AGENT_VERSION} AS qemu-download
FROM ghcr.io/kairos-io/hadron-sources/glib:${GLIB_VERSION} AS glib-download
FROM ghcr.io/kairos-io/hadron-sources/pcre2:${PCRE2_VERSION} AS pcre2-download
FROM ghcr.io/kairos-io/hadron-sources/libffi:${LIBFFI_VERSION} AS libffi-download

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
WORKDIR /sources
COPY --from=qemu-download /sources/downloads/qemu.tar.xz /sources/
COPY --from=glib-download /sources/downloads/glib.tar.xz /sources/
COPY --from=pcre2-download /sources/downloads/pcre2.tar.gz /sources/
COPY --from=libffi-download /sources/downloads/libffi.tar.gz /sources/
RUN tar -xf qemu.tar.xz && mv qemu-* qemu
RUN tar -xf glib.tar.xz && mv glib-* glib
RUN tar -xf pcre2.tar.gz && mv pcre2-* pcre2
RUN tar -xf libffi.tar.gz && mv libffi-* libffi

# The static libraries are installed into /deps, not /output, so none of them
# reach the layer.
FROM downloader AS libffi
WORKDIR /sources/libffi
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--enable-shared/}"
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--disable-static/}"
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-shared --enable-static \
    --with-pic --disable-docs --libdir=/usr/lib --disable-multi-os-directory
RUN make -j"$(nproc)"
RUN make DESTDIR=/deps install

FROM libffi AS pcre2
COPY --from=libffi /deps/ /
WORKDIR /sources/pcre2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-shared --enable-static \
    --with-pic --enable-utf --enable-unicode-properties --disable-dependency-tracking
RUN make -j"$(nproc)"
RUN make DESTDIR=/deps install

FROM pcre2 AS glib
COPY --from=pcre2 /deps/ /
WORKDIR /sources/glib
RUN pip3 install meson ninja
RUN meson setup buildDir ${COMMON_MESON_FLAGS} --default-library=static -Db_pie=false \
    -Dselinux=disabled -Dxattr=false -Dlibmount=disabled -Dman-pages=disabled \
    -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled -Ddocumentation=false \
    -Dtests=false -Dinstalled_tests=false -Dnls=disabled -Dglib_debug=disabled \
    -Dglib_assert=false -Dglib_checks=false -Dlibelf=disabled -Dintrospection=disabled
RUN DESTDIR=/deps ninja -j"$(nproc)" -C buildDir install

FROM downloader AS builder
COPY --from=glib /deps/ /
RUN pip3 install meson ninja
WORKDIR /sources/qemu
# --without-default-features turns every feature off, and only the guest agent
# is turned back on, so there is no qemu-system, qemu-img, TCG or KVM.
# --disable-install-blobs and --enable-fdt=disabled stop meson from looking
# for bzip2 and from cloning the dtc subproject, as in Hadron's own build.
RUN ./configure \
      --prefix=/usr \
      --without-default-features --without-default-devices --disable-coroutine-pool \
      --disable-install-blobs \
      --enable-fdt=disabled \
      --enable-guest-agent --disable-tcg
RUN make -j"$(nproc)" qemu-ga
RUN install -Dm755 build/qga/qemu-ga /output/usr/bin/qemu-ga
RUN install -Dm644 contrib/systemd/qemu-guest-agent.service \
      /output/usr/lib/systemd/system/qemu-guest-agent.service

# Upstream's unit has an empty [Install] section, so nothing starts it, and its
# BindTo= is the old spelling of BindsTo=. Use the current name. The unit is
# started by the udev rule in files/, which pulls it in when the virtio port
# org.qemu.guest_agent.0 appears. That port exists only in a QEMU VM, so the
# unit stays inactive on bare metal. The rule lives under /usr, so this works as
# a system extension, which cannot enable a unit under /etc.
RUN sed -i 's/^BindTo=/BindsTo=/' /output/usr/lib/systemd/system/qemu-guest-agent.service
COPY files/ /output/

# Final layer: the qemu-ga binary, its systemd unit and the udev rule that starts it. Use as a layer on top
# of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/qemu-guest-agent:TAG / /
# Or install it as a system extension: kairos-agent sysext install qemu-guest-agent
FROM scratch AS default
COPY --from=builder /output/ /

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
RUN qemu-ga --version
# glib is linked statically: only the C library is dynamic.
RUN set -eux; \
    libs=$(ldd /usr/bin/qemu-ga | grep -v -e 'ld-musl' -e 'libc\.' -e 'linux-vdso' || true); \
    [ -z "$libs" ]
# The binary must be the guest agent only, with no TCG or system emulator.
RUN qemu-ga --help | grep -q 'QEMU Guest Agent'
# The unit must bind to the virtio port device, and the udev rule that starts
# it must be valid. Nothing may enable the unit statically, or it would start
# on bare metal and fail there.
RUN grep -q '^BindsTo=dev-virtio\\x2dports-org.qemu.guest_agent.0.device' /usr/lib/systemd/system/qemu-guest-agent.service
RUN grep -q '^After=dev-virtio\\x2dports-org.qemu.guest_agent.0.device' /usr/lib/systemd/system/qemu-guest-agent.service
RUN grep -q '^ExecStart=.*/usr/bin/qemu-ga' /usr/lib/systemd/system/qemu-guest-agent.service
RUN ! test -e /usr/lib/systemd/system/multi-user.target.wants/qemu-guest-agent.service
RUN grep -q 'SYSTEMD_WANTS}="qemu-guest-agent.service"' /usr/lib/udev/rules.d/99-qemu-guest-agent.rules
RUN udevadm verify /usr/lib/udev/rules.d/99-qemu-guest-agent.rules
