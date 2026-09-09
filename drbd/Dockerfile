# DRBD 9 out-of-tree kernel module + drbd-utils, packaged as a Hadron layer.
#
# DRBD 9 (from LINBIT) is distributed out-of-tree only. Compared to the in-tree
# DRBD 8 the kernel ships, it adds multi-node replication and quorum, which
# LINSTOR/Piraeus require. Because it is an *update* to a module that also
# exists in-tree, it is installed under
#     /usr/lib/modules/$(KERNELRELEASE)/updates/
# so depmod resolves it ahead of the in-tree kernel/ copy.
# (Hadron uses UsrMerge: /lib is a symlink to usr/lib.)
#
# HADRON_TOOLCHAIN_VERSION defaults to a known-good version but is a build ARG
# on purpose: a kernel module is tied to the exact kernel of the toolchain
# image it is built against. The consumer must run a Hadron release whose
# kernel matches this toolchain. In this repository's CI the value is supplied
# centrally from docker-bake.hcl.
ARG HADRON_TOOLCHAIN_VERSION=v0.5.2

# ── Kernel module ───────────────────────────────────────────────────────────
# The toolchain image ships the kernel .config, Module.symvers and the release
# strings under /usr/share/kernel-misc, but not the kernel source tree. Fetch
# the matching kernel source and run `modules_prepare` so the out-of-tree DRBD
# module can be compiled against it (the same approach Hadron uses for its own
# out-of-tree module examples).
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS module-builder
ARG DRBD_VERSION=9.3.3
ARG TARGETARCH
WORKDIR /build

# Kernel ARCH string used by kbuild and by DRBD's Makefile. The toolchain sets a
# global ARCH env for its own userspace builds, so we always pass this value
# explicitly to the kernel/DRBD make invocations below.
RUN case "${TARGETARCH}" in \
      amd64)   echo x86_64 > /karch ;; \
      arm64)   echo arm64  > /karch ;; \
      riscv64) echo riscv  > /karch ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac

# Prepare a build tree for the exact kernel shipped by the toolchain/base image.
RUN kver=$(cat /usr/share/kernel-misc/kernel-version) && series="v$(echo "${kver}" | cut -d. -f1).x" && \
    curl -fL "https://cdn.kernel.org/pub/linux/kernel/${series}/linux-${kver}.tar.xz" -o linux.tar.xz
RUN tar -xf linux.tar.xz && rm linux.tar.xz && mv linux-* linux
WORKDIR /build/linux
# The out-of-tree module is unsigned; the base kernel does not enforce module
# signatures (CONFIG_MODULE_SIG_FORCE is off), so it loads (tainted) at runtime.
# Disable signing in the build tree so `modules_prepare` never needs the
# (absent) kernel signing key. Module signing is not part of the module
# vermagic, so this does not affect loadability. LOCALVERSION is kept as-is so
# the vermagic release string matches the running kernel.
RUN cp /usr/share/kernel-misc/kernel-config .config && \
    ./scripts/config --disable MODULE_SIG --disable MODULE_SIG_ALL --disable MODULE_SIG_FORCE && \
    ARCH="$(cat /karch)" make -s olddefconfig && \
    ARCH="$(cat /karch)" make -s -j"$(nproc)" modules_prepare && \
    cp /usr/share/kernel-misc/Module.symvers .

# Build and install the DRBD 9 module from the LINBIT release tarball. The
# release tarball ships the pre-generated compat sources; the GitHub archive
# would additionally require coccinelle (spatch) at build time.
WORKDIR /build
RUN curl -fL "https://pkg.linbit.com/downloads/drbd/9/drbd-${DRBD_VERSION}.tar.gz" -o drbd.tar.gz
RUN tar -xf drbd.tar.gz && rm drbd.tar.gz && mv drbd-*/ drbd
WORKDIR /build/drbd
# Mirror the toolchain's default CFLAGS/LDFLAGS but drop `-flto=auto`. Kbuild
# ignores CFLAGS for kernel objects (uses KCFLAGS), but DRBD's top-level
# Makefile builds a small buildtag helper with $(CC) $(CFLAGS), and LTO for a
# one-shot helper is fragile.
ENV CFLAGS="-Os -pipe -fomit-frame-pointer -fno-unroll-loops -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections"
ENV LDFLAGS="-Wl,--gc-sections -Wl,--as-needed"
# DRBD's Makefile passes INSTALL_MOD_DIR=updates to the kernel's
# modules_install, so every module lands under lib/modules/${kver}/updates/ directly.
RUN kver=$(cat /usr/share/kernel-misc/kernel-release) && \
    ARCH="$(cat /karch)" make -j"$(nproc)" KDIR=/build/linux KVER="${kver}" && \
    ARCH="$(cat /karch)" make install DESTDIR=/dest KDIR=/build/linux KVER="${kver}"

# ── Userspace tools ─────────────────────────────────────────────────────────
# drbdadm / drbdsetup / drbdmeta for managing the DRBD 9 module. The LINBIT
# release tarball ships a pre-generated ./configure.
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS utils-builder
ARG DRBD_UTILS_VERSION=9.34.0
WORKDIR /build
RUN curl -fL "https://pkg.linbit.com/downloads/drbd/utils/drbd-utils-${DRBD_UTILS_VERSION}.tar.gz" -o drbd-utils.tar.gz
RUN tar -xf drbd-utils.tar.gz && rm drbd-utils.tar.gz && mv drbd-utils-* drbd-utils
WORKDIR /build/drbd-utils
# Only the DRBD 9 tooling is needed; drop legacy 8.3/8.4 support, docs and the
# cluster-manager integrations to keep the layer small.
RUN ./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc \
      --without-manual \
      --without-83support --without-84support \
      --with-systemdsystemunitdir=/usr/lib/systemd/system \
      --with-tmpfilesdir=/usr/lib/tmpfiles.d \
      --without-heartbeat --without-pacemaker --without-rgmanager --without-bashcompletion
RUN make -s -j"$(nproc)"
RUN make -s -j"$(nproc)" install DESTDIR=/dest
RUN rm -rf /dest/usr/share/man && \
    # Hadron uses UsrMerge: /var/run is a symlink to /run in the base image.
    # drbd-utils installs /var/run/drbd/ as a real directory, which would
    # cause "cannot copy to non-directory" when overlaying this layer.
    # The --with-tmpfilesdir=/usr/lib/tmpfiles.d flag above installs a
    # tmpfiles.d config that re-creates the runtime directory at boot instead.
    rm -rf /dest/var/run

# Final layer: the out-of-tree DRBD 9 module (in updates/) and the drbd-utils
# userspace tools. Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/drbd:TAG / /
# Or create a sysextension with the help of Auroraboot (https://github.com/kairos-io/auroraboot)
# The consumer image is expected to run `depmod` at build/boot so the added
# module under updates/ is indexed and wins over the in-tree DRBD 8.
FROM scratch AS default
COPY --from=module-builder /dest/lib/modules/ /usr/lib/modules/
COPY --from=utils-builder  /dest/            /

# Smoke-test the built layer. Any RUN failure here fails the build and gates
# the release step in CI. The kernel module cannot be inserted (the build
# kernel differs from the CI host kernel), so the test is purely static:
# verify the DRBD .ko is present under updates/ and confirm the userspace
# tools are installed. Only `drbdadm --version` is invoked (it's standalone);
# `drbdsetup`/`drbdmeta --version` probe the host kernel for a running drbd
# module and fail on non-Hadron CI kernels, so those are verified by presence
# + executable bit instead. The toolchain image is reused as the test base
# because it is already pulled during the build and ships kmod (modinfo).
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS test
COPY --from=default / /
RUN set -eux; \
    kver=$(ls /lib/modules); \
    drbd_ko=$(find "/lib/modules/${kver}/updates" \( -name 'drbd.ko' -o -name 'drbd.ko.zst' \) | head -1); \
    test -n "${drbd_ko}"; \
    modinfo "${drbd_ko}" | grep -qi '^version:'; \
    drbdadm --version | grep -qi 'DRBDADM_VERSION='; \
    command -v drbdsetup >/dev/null && [ -x "$(command -v drbdsetup)" ]; \
    command -v drbdmeta  >/dev/null && [ -x "$(command -v drbdmeta)"  ]
