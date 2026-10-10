# OpenZFS kernel module + userspace tools, packaged as a Hadron layer.
#
# Built like the drbd layer: the module is compiled against a kernel tree
# prepared from the toolchain's own .config and Module.symvers, and installed
# under /usr/lib/modules/$(KERNELRELEASE)/updates/. Unlike DRBD there is no
# in-tree ZFS, so updates/ only keeps the layout consistent across layers.
#
# HADRON_TOOLCHAIN_VERSION has a default for standalone builds; CI supplies it
# from docker-bake.hcl. The consumer must run a Hadron release whose kernel
# matches this toolchain.
ARG ZFS_VERSION=2.4.4
ARG TIRPC_VERSION=1.3.6
ARG TIRPC_SHA256=bbd26a8f0df5690a62a47f6aa30f797f3ef8d02560d1bc449a83066b5a1d3508
ARG HADRON_TOOLCHAIN_VERSION=v0.5.3
ARG HADRON_VERSION=v0.5.3

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS zfs-source
ARG ZFS_VERSION
WORKDIR /build
# The release ships a clearsigned .sha256.asc next to the tarball. Only its
# hash line is checked, which catches a truncated or corrupted download; the
# signature is not verified.
RUN curl -fL "https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz" -o "zfs-${ZFS_VERSION}.tar.gz" && \
    curl -fL "https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.sha256.asc" -o zfs.sha256.asc && \
    grep -E "^[0-9a-f]{64}  zfs-${ZFS_VERSION}\.tar\.gz$" zfs.sha256.asc | sha256sum -c - && \
    tar -xf "zfs-${ZFS_VERSION}.tar.gz" && rm "zfs-${ZFS_VERSION}.tar.gz" zfs.sha256.asc && mv zfs-* zfs

# ── Kernel module ───────────────────────────────────────────────────────────
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS module-builder
ARG TARGETARCH
WORKDIR /build

# The toolchain sets a global ARCH for its own userspace builds, so the kernel
# ARCH string is passed explicitly to every kernel/module make invocation.
RUN case "${TARGETARCH}" in \
      amd64)   echo x86_64 > /karch ;; \
      arm64)   echo arm64  > /karch ;; \
      riscv64) echo riscv  > /karch ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac

RUN kver=$(cat /usr/share/kernel-misc/kernel-version) && series="v$(echo "${kver}" | cut -d. -f1).x" && \
    curl -fL "https://cdn.kernel.org/pub/linux/kernel/${series}/linux-${kver}.tar.xz" -o linux.tar.xz
RUN tar -xf linux.tar.xz && rm linux.tar.xz && mv linux-* linux
WORKDIR /build/linux
# Same as the drbd layer: the module is unsigned and the base kernel does not
# enforce signatures, so signing is disabled in the build tree only.
RUN cp /usr/share/kernel-misc/kernel-config .config && \
    ./scripts/config --disable MODULE_SIG --disable MODULE_SIG_ALL --disable MODULE_SIG_FORCE && \
    ARCH="$(cat /karch)" make -s olddefconfig && \
    ARCH="$(cat /karch)" make -s -j"$(nproc)" modules_prepare && \
    cp /usr/share/kernel-misc/Module.symvers .

COPY --from=zfs-source /build/zfs /build/zfs
WORKDIR /build/zfs
RUN kver=$(cat /usr/share/kernel-misc/kernel-release) && \
    ARCH="$(cat /karch)" ./configure --with-config=kernel \
      --with-linux=/build/linux --with-linux-obj=/build/linux && \
    ARCH="$(cat /karch)" make -s -j"$(nproc)" -C module && \
    ARCH="$(cat /karch)" make -C module install DESTDIR=/dest INSTALL_MOD_DIR=updates KERNELRELEASE="${kver}"

# ── libtirpc (build-time only) ──────────────────────────────────────────────
# libnvpair uses XDR from Sun RPC, which musl lacks and the toolchain does not
# ship. The hadron base image already carries libtirpc.so.3, so it is
# installed into this builder for linking only and never reaches the layer:
# shipping a second copy would shadow the base's, which mount.nfs also uses.
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS tirpc-builder
ARG TIRPC_VERSION
ARG TIRPC_SHA256
WORKDIR /build
RUN curl -fL "https://downloads.sourceforge.net/libtirpc/libtirpc-${TIRPC_VERSION}.tar.bz2" -o tirpc.tar.bz2 && \
    echo "${TIRPC_SHA256}  tirpc.tar.bz2" | sha256sum -c - && \
    tar -xf tirpc.tar.bz2 && rm tirpc.tar.bz2 && mv libtirpc-* libtirpc
WORKDIR /build/libtirpc
# musl ships no <sys/queue.h> (Alpine takes it from bsd-compat-headers), and
# GCC 15 defaults to C23, where libtirpc's K&R prototypes no longer compile.
RUN curl -fL https://raw.githubusercontent.com/bminor/glibc/glibc-2.42/misc/sys/queue.h -o /usr/include/sys/queue.h && \
    echo "8b284031772b1ba2035d9b05b24f2cb9b23e7bd324bcccb5e3fcc57d34aafa48  /usr/include/sys/queue.h" | sha256sum -c -
RUN CFLAGS="-std=gnu17 -O2" ./configure --prefix=/usr --sysconfdir=/etc --disable-gssapi --disable-static && \
    make -s -j"$(nproc)" && make -s install

# ── Userspace tools ─────────────────────────────────────────────────────────
FROM tirpc-builder AS utils-builder
COPY --from=zfs-source /build/zfs /build/zfs
WORKDIR /build/zfs
# The toolchain has no systemd for configure to detect, so the units are
# requested explicitly; without them the pool is never imported at boot.
RUN ./configure --with-config=user --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
      --with-udevdir=/usr/lib/udev --with-systemdunitdir=/usr/lib/systemd/system \
      --with-systemdpresetdir=/usr/lib/systemd/system-preset \
      --enable-systemd --disable-pyzfs --disable-sysvinit && \
    make -s -j"$(nproc)" && make -s install DESTDIR=/dest

# ── Merge + strip ───────────────────────────────────────────────────────────
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS merge
COPY --from=utils-builder /dest/ /dest/
# Hadron is UsrMerge: /bin, /sbin and /lib are symlinks into /usr, and a real
# directory there cannot be copied over the base image. The python tools are
# dropped because Hadron ships no python3.
RUN for d in bin sbin lib; do \
      if [ -d "/dest/$d" ] && [ ! -L "/dest/$d" ]; then \
        mkdir -p "/dest/usr/$d" && cp -a "/dest/$d/." "/dest/usr/$d/" && rm -rf "/dest/$d"; \
      fi; \
    done && \
    rm -rf /dest/usr/include /dest/usr/share/man /dest/usr/share/doc \
           /dest/usr/lib/pkgconfig /dest/usr/share/pkgconfig \
           /dest/usr/share/zfs/zfs-tests /dest/usr/share/zfs/test-runner /dest/usr/share/zfs/runfiles \
           /dest/usr/share/zfs/*.sh /dest/usr/sbin/ztest /dest/usr/bin/raidz_test \
           /dest/usr/lib/dracut /dest/usr/share/initramfs-tools \
           /dest/etc/bash_completion.d /dest/usr/share/bash-completion /dest/etc/zfs/*.example \
           /dest/var/run && \
    rm -f /dest/usr/bin/dbufstat /dest/usr/bin/zarcstat /dest/usr/bin/zarcsummary /dest/usr/bin/zilstat && \
    find /dest -name '*.a' -delete && \
    find /dest -name '*.la' -delete && \
    test -z "$(find /dest -name 'libtirpc*' -o -name netconfig -o -name bindresvport.blacklist)"

# ── Final layer ─────────────────────────────────────────────────────────────
# Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/zfs:TAG / /
# The consumer image is expected to run `depmod` so the module under updates/
# is indexed. Kairos keeps /etc/zfs persistent on an installed system, but in
# recovery mode and on the first boot there is no zpool.cache yet, so enabling
# zfs-import-scan.service as well imports pools in every mode. The root is
# read-only, so create pools with mountpoint=none or a mountpoint under a
# writable path.
FROM scratch AS default
COPY --from=module-builder /dest/lib/modules/ /usr/lib/modules/
COPY --from=merge /dest/ /

# Smoke-test on the Hadron base image rather than the toolchain: the toolchain
# lacks libucontext, which the base image's libudev needs, so zpool and zfs
# only run here. The module cannot be loaded (the CI kernel is not Hadron's),
# so it is checked statically. Its kernel comes from the layer, not from the
# base: HADRON_TOOLCHAIN_VERSION and HADRON_VERSION are bumped by different
# bots, and while they disagree the dependency checks are skipped instead of
# failing both bump PRs.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default /usr/lib/modules/ /tmp/layer-modules/
COPY --from=default / /
RUN set -eux; \
    kver=$(ls /tmp/layer-modules); \
    ko=$(find "/usr/lib/modules/${kver}/updates" \( -name 'zfs.ko' -o -name 'zfs.ko.*' \) | head -1); \
    test -n "${ko}"; \
    modinfo "${ko}" | grep -q "^vermagic: *${kver} "; \
    if [ -d "/usr/lib/modules/${kver}/kernel" ]; then \
      depmod "${kver}"; \
      modprobe --dry-run --set-version "${kver}" zfs; \
    else \
      echo "base image kernel is $(ls /usr/lib/modules | grep -vx "${kver}"), layer built for ${kver}: skipping depmod/modprobe"; \
    fi; \
    zfs version 2>&1 | grep -q 'ZFS modules cannot be auto-loaded'; \
    zpool version 2>&1 | grep -q 'ZFS modules cannot be auto-loaded'; \
    for b in mount.zfs zed zdb; do command -v "$b"; done; \
    test -f /usr/lib/systemd/system/zfs-import-scan.service; \
    test -f /usr/lib/udev/rules.d/60-zvol.rules
