# This dockerfile builds open-vm-tools (vmtoolsd and the vmware-* helpers) from
# source using the Hadron toolchain image. HADRON_TOOLCHAIN_VERSION and
# HADRON_VERSION are provided centrally via docker-bake.hcl.
#
# The build follows the open-vm-tools stage Hadron uses for its cloud images,
# and every source comes from the checksummed cache Hadron builds from
# (ghcr.io/kairos-io/hadron-sources), including the Alpine aports tree that
# carries the musl patches and the BSD compat headers. Nothing is fetched from
# a web page during the build: fetching queue.h from the Alpine GitLab without
# --fail once saved an HTML page as the header, and libtirpc then failed with
# "invalid use of incomplete typedef 'fd_lock_t'".
#
# Runtime libraries: the Hadron base image already ships libtirpc, libssl,
# libcrypto, libz and libudev, so the layer does not carry them. It ships the
# shared glib, pcre2, libffi and libmspack that the base lacks. glib is shared,
# not static, because vmtoolsd loads its plugins as separate shared objects
# that must all use the same glib.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION
# OPENVM_TOOLS_VERSION is the version Hadron pins in its Dockerfile, and the
# others are the versions Hadron builds its own copies with, so all of them
# exist in the source cache. updatecli.d/open-vm-tools.yaml keeps every one of
# them in step with Hadron's Dockerfile under the same name. LIBTIRPC_VERSION
# matches the libtirpc in the base image, which is the copy vmtoolsd uses at
# runtime.
ARG OPENVM_TOOLS_VERSION=13.1.0
ARG MSPACK_VERSION=1.12
ARG GLIB_VERSION=2.90.1
ARG PCRE2_VERSION=10.49
ARG LIBFFI_VERSION=3.8.1
ARG LIBTIRPC_VERSION=1.3.8
ARG APORTS_VERSION=3.24.3

FROM ghcr.io/kairos-io/hadron-sources/open-vm-tools:${OPENVM_TOOLS_VERSION} AS open-vm-tools-download
FROM ghcr.io/kairos-io/hadron-sources/mspack:${MSPACK_VERSION} AS mspack-download
FROM ghcr.io/kairos-io/hadron-sources/glib:${GLIB_VERSION} AS glib-download
FROM ghcr.io/kairos-io/hadron-sources/pcre2:${PCRE2_VERSION} AS pcre2-download
FROM ghcr.io/kairos-io/hadron-sources/libffi:${LIBFFI_VERSION} AS libffi-download
FROM ghcr.io/kairos-io/hadron-sources/libtirpc:${LIBTIRPC_VERSION} AS libtirpc-download
FROM ghcr.io/kairos-io/hadron-sources/aports:${APORTS_VERSION} AS aports-download
# rpcgen is taken from the base image, which ships it. It links only against
# musl, so it runs in the toolchain image as is.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS hadron-base

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
WORKDIR /sources
COPY --from=open-vm-tools-download /sources/downloads/open-vm-tools.tar.gz /sources/
COPY --from=mspack-download /sources/downloads/mspack.tar.gz /sources/
COPY --from=glib-download /sources/downloads/glib.tar.xz /sources/
COPY --from=pcre2-download /sources/downloads/pcre2.tar.gz /sources/
COPY --from=libffi-download /sources/downloads/libffi.tar.gz /sources/
COPY --from=libtirpc-download /sources/downloads/libtirpc.tar.bz2 /sources/
COPY --from=aports-download /sources/downloads/aports.tar.gz /sources/
RUN tar -xf open-vm-tools.tar.gz && mv open-vm-tools-* open-vm-tools
RUN tar -xf mspack.tar.gz && mv libmspack-* mspack
RUN tar -xf glib.tar.xz && mv glib-* glib
RUN tar -xf pcre2.tar.gz && mv pcre2-* pcre2
RUN tar -xf libffi.tar.gz && mv libffi-* libffi
RUN tar -xf libtirpc.tar.bz2 && mv libtirpc-* libtirpc
# Only two directories of the aports tree are needed. The toolchain's tar is
# busybox, which has no --wildcards, so the top directory is named in full.
ARG APORTS_VERSION
RUN tar -xf aports.tar.gz "aports-v${APORTS_VERSION}/main/bsd-compat-headers" \
      "aports-v${APORTS_VERSION}/community/open-vm-tools" && \
    mv "aports-v${APORTS_VERSION}" aports && rm aports.tar.gz

# Runtime libraries the base image lacks. Each one is installed into /output,
# which becomes part of the layer, and into / so the next build finds it.
FROM downloader AS libffi
WORKDIR /sources/libffi
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-docs --libdir=/usr/lib --disable-multi-os-directory
RUN make -j"$(nproc)"
RUN make DESTDIR=/output install

FROM downloader AS pcre2
WORKDIR /sources/pcre2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-utf --enable-unicode-properties --disable-dependency-tracking
RUN make -j"$(nproc)"
RUN make DESTDIR=/output install

FROM downloader AS glib
COPY --from=libffi /output/ /
COPY --from=pcre2 /output/ /
RUN pip3 install meson ninja
WORKDIR /sources/glib
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dselinux=disabled -Dxattr=false \
    -Dlibmount=disabled -Dman-pages=disabled -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled \
    -Ddocumentation=false -Dtests=false -Dinstalled_tests=false -Dnls=disabled \
    -Dglib_debug=disabled -Dglib_assert=false -Dglib_checks=false -Dlibelf=disabled \
    -Dintrospection=disabled
RUN DESTDIR=/output ninja -j"$(nproc)" -C buildDir install

FROM downloader AS mspack
WORKDIR /sources/mspack/libmspack
RUN autoreconf -i -W all
RUN ./configure ${COMMON_CONFIGURE_ARGS}
RUN make -j"$(nproc)"
RUN make DESTDIR=/output install

# libtirpc is built for linking only and installed into /deps, never into the
# layer: the base image already carries libtirpc.so.3, and a second copy would
# shadow it. The flags are the ones Hadron builds its own libtirpc with.
# libtirpc needs <sys/queue.h> and <sys/cdefs.h>, which musl does not ship, so
# they come from Alpine's bsd-compat-headers in the aports tree.
FROM downloader AS libtirpc
RUN install -Dm644 -t /usr/include/sys \
      /sources/aports/main/bsd-compat-headers/cdefs.h \
      /sources/aports/main/bsd-compat-headers/queue.h \
      /sources/aports/main/bsd-compat-headers/tree.h
WORKDIR /sources/libtirpc
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc \
      --disable-gssapi --disable-authdes --enable-rpcdb
RUN make -j"$(nproc)"
RUN make DESTDIR=/deps install

FROM downloader AS builder
COPY --from=libffi /output/ /
COPY --from=pcre2 /output/ /
COPY --from=glib /output/ /
COPY --from=mspack /output/ /
COPY --from=libtirpc /deps/ /
COPY --from=hadron-base /usr/bin/rpcgen /usr/bin/rpcgen
WORKDIR /sources/open-vm-tools
# The musl patches Alpine carries for open-vm-tools, the same set Hadron
# applies for its cloud images.
RUN for p in \
      0002-open-vm-tools-Add-disable-werror-configure-option.patch \
      0003-Do-not-assume-that-linux-and-gnu-libc-are-the-same-t.patch \
      0004-Use-configure-test-for-struct-timespec.patch \
      0005-Fix-definition-of-ALLPERMS-and-ACCESSPERMS.patch \
      0006-Use-configure-to-test-for-feature-instead-of-platfor.patch \
      0007-Use-configure-test-for-sys-stat.h-include.patch \
      0008-Rename-poll.h-to-vm_poll.h.patch \
      0010-use-posix-strerror_r-unless-gnu.patch \
      0011-use-off64_t-instead-of-loff_t.patch \
      snprintf.patch \
      strerror_r.patch \
      mock-res_ninit-and-res_nclose.patch; do \
      patch -p1 < "/sources/aports/community/open-vm-tools/$p" || exit 1; \
    done
WORKDIR /sources/open-vm-tools/open-vm-tools
RUN autoreconf -if
# Teach the guest OS detection about Hadron, as Hadron does for its own build.
RUN sed -i '/#define STR_OS_ARCH/a\#define STR_OS_HADRON              "Hadron"' lib/include/guest_os.h
RUN sed -i '/{ "gentoo", *STR_OS_GENTOO, *HostinfoGenericSetShortName },/a\{ "hadron",              STR_OS_HADRON,             HostinfoGenericSetShortName },' lib/misc/hostinfoPosix.c
RUN ./configure ${COMMON_CONFIGURE_ARGS} --sysconfdir=/etc \
      --disable-glibc-check --disable-multimon --without-gtk4 --without-gtk3 --without-fuse --without-dnet \
      --without-xerces --without-icu --without-kernel-modules --without-pam --disable-werror \
      --disable-containerinfo --without-x
RUN make -j"$(nproc)"
RUN make DESTDIR=/output install

# ── Merge + strip ───────────────────────────────────────────────────────────
FROM downloader AS merge
COPY --from=libffi /output/ /dest/
COPY --from=pcre2 /output/ /dest/
COPY --from=glib /output/ /dest/
COPY --from=mspack /output/ /dest/
COPY --from=builder /output/ /dest/
COPY files/ /dest/
# Hadron is UsrMerge: /bin, /sbin and /lib are symlinks into /usr, and a real
# directory there cannot be copied over the base image. A system extension
# only merges /usr/bin, /usr/lib, /usr/sbin and /usr/share, so nothing may land
# in /usr/libexec either; glib puts gio-launch-desktop there, and none of the
# glib command line tools are needed at runtime. libpcre2-posix and the
# 16 and 32 bit pcre2 libraries are not used by glib. The layer is built
# --without-pam, so the PAM file open-vm-tools installs anyway is dropped.
RUN for d in bin sbin lib; do \
      if [ -d "/dest/$d" ] && [ ! -L "/dest/$d" ]; then \
        mkdir -p "/dest/usr/$d" && cp -a "/dest/$d/." "/dest/usr/$d/" && rm -rf "/dest/$d"; \
      fi; \
    done && \
    rm -rf /dest/usr/include /dest/usr/share/man /dest/usr/share/info /dest/usr/share/doc \
           /dest/usr/share/gtk-doc /dest/usr/share/aclocal /dest/usr/share/bash-completion \
           /dest/usr/share/gettext /dest/usr/share/gdb /dest/usr/share/glib-2.0 \
           /dest/usr/share/pkgconfig /dest/usr/lib/pkgconfig /dest/usr/share/locale \
           /dest/usr/lib/girepository-1.0 /dest/usr/lib/glib-2.0 /dest/usr/lib/gio /dest/usr/libexec \
           /dest/etc/pam.d && \
    rm -f /dest/usr/bin/gapplication /dest/usr/bin/gdbus /dest/usr/bin/gdbus-codegen \
          /dest/usr/bin/gio /dest/usr/bin/gio-querymodules /dest/usr/bin/glib-compile-resources \
          /dest/usr/bin/glib-compile-schemas /dest/usr/bin/glib-genmarshal /dest/usr/bin/glib-gettextize \
          /dest/usr/bin/glib-mkenums /dest/usr/bin/gobject-query /dest/usr/bin/gresource \
          /dest/usr/bin/gsettings /dest/usr/bin/gtester /dest/usr/bin/gtester-report \
          /dest/usr/bin/gi-compile-repository /dest/usr/bin/gi-decompile-typelib \
          /dest/usr/bin/gi-inspect-typelib /dest/usr/bin/pcre2grep /dest/usr/bin/pcre2test \
          /dest/usr/bin/pcre2-config /dest/usr/bin/libmspack-config \
          /dest/usr/lib/libgirepository-* /dest/usr/lib/libpcre2-posix.so* \
          /dest/usr/lib/libpcre2-16.so* /dest/usr/lib/libpcre2-32.so* && \
    find /dest -name '*.a' -delete && \
    find /dest -name '*.la' -delete && \
    mkdir -p /dest/usr/lib/systemd/system/multi-user.target.wants && \
    ln -sf ../vmtoolsd.service /dest/usr/lib/systemd/system/multi-user.target.wants/vmtoolsd.service && \
    test -z "$(find /dest -name 'libtirpc*' -o -name netconfig -o -name bindresvport.blacklist)" && \
    test ! -e /dest/usr/libexec

# Final layer: vmtoolsd, the vmware-* helpers, their plugins and the shared
# libraries the base image lacks. Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/open-vm-tools:TAG / /
# Or install it as a system extension: kairos-agent sysext install open-vm-tools
# As a system extension only /usr is merged, so the default power scripts and
# tools.conf example under /etc/vmware-tools are not there; vmtoolsd runs
# without them and skips the power-operation scripts.
FROM scratch AS default
COPY --from=merge /dest/ /

# Smoke-test the built layer against a Hadron base image. Any RUN failure
# here fails the build and gates the release step in CI. Kept fully offline;
# the CI runner is not a VMware guest, so only commands that do not need the
# hypervisor backdoor are run.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /layer/
# As a system extension the layer is merged over the base's /usr. It must not
# carry a file the base already has, or it would replace the base's copy.
RUN set -eu; \
    clash=$(cd /layer && find . ! -type d | while read -r f; do [ ! -e "/${f#./}" ] || echo "${f#./}"; done); \
    if [ -n "$clash" ]; then echo "layer overlays base files: $clash" >&2; exit 1; fi
RUN test ! -e /layer/usr/libexec
RUN cp -a /layer/. / && rm -rf /layer
# Every binary and plugin must resolve all of its libraries against the base
# image plus the layer.
RUN set -eu; \
    for f in /usr/bin/vmtoolsd /usr/bin/vmware-toolbox-cmd /usr/bin/vmware-rpctool \
             $(find /usr/lib/open-vm-tools/plugins -name '*.so'); do \
      out=$(ldd "$f" 2>&1); \
      if echo "$out" | grep -q 'not found\|Error'; then echo "$f: $out" >&2; exit 1; fi; \
    done
# Outside a VMware guest every tool refuses to start. The helpers say so, which
# shows they load and run; vmtoolsd exits 1 without a message, and anything
# from 126 up would mean it could not be executed or crashed.
RUN vmware-checkvm 2>&1 | grep -q 'must be run inside a virtual machine'
RUN vmware-toolbox-cmd --version 2>&1 | grep -q 'must be run inside a virtual machine'
RUN vmware-rpctool 2>&1 | grep -q 'must be run inside a virtual machine'
RUN set +e; vmtoolsd --version; rc=$?; test "$rc" -eq 1
RUN test -f /usr/lib/open-vm-tools/plugins/vmsvc/libtimeSync.so
RUN test -f /usr/lib/open-vm-tools/plugins/vmsvc/libdeployPkgPlugin.so
RUN grep -q '^ConditionVirtualization=vmware' /usr/lib/systemd/system/vmtoolsd.service
RUN test -L /usr/lib/systemd/system/multi-user.target.wants/vmtoolsd.service
