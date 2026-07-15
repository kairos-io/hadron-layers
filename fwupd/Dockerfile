# HADRON_TOOLCHAIN_VERSION is provided centrally via docker-bake.hcl.
ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
# Install it at the top so we dont need to reinstall on each target
RUN pip3 install meson ninja jinja2
# create the empty dir which will be the target of our installs on each target
RUN mkdir -p /output
WORKDIR /sources

# fwupd
ARG FWUPD_VERSION=2.1.6
RUN curl -L https://github.com/fwupd/fwupd/releases/download/${FWUPD_VERSION}/fwupd-${FWUPD_VERSION}.tar.xz -o fwupd.tar.xz

# glib. GNOME sources are grouped by major.minor series under
# /sources/glib/<major>.<minor>/, and only even minor versions are stable
# (2.86.x, 2.88.x, ...); odd minor versions are dev releases. Pin to the
# latest stable series and derive the directory segment from the version
# so future bumps do not have to touch the URL.
ARG GLIB_VERSION=2.88.2
RUN GLIB_SERIES="${GLIB_VERSION%.*}" && \
    curl -L "https://download.gnome.org/sources/glib/${GLIB_SERIES}/glib-${GLIB_VERSION}.tar.xz" -o glib.tar.xz

ARG PCRE2_VERSION=10.47
RUN curl -L https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz -o pcre2.tar.gz

ARG LIBXMLB_VERSION=0.3.28
RUN curl -L https://github.com/hughsie/libxmlb/releases/download/${LIBXMLB_VERSION}/libxmlb-${LIBXMLB_VERSION}.tar.xz -o libxmlb.tar.xz

ARG LIBUSB_VERSION=1.0.30
RUN curl -L https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2 -o libusb.tar.bz2

ARG LIBJCAT_VERSION=0.2.6
RUN curl -L https://github.com/hughsie/libjcat/releases/download/${LIBJCAT_VERSION}/libjcat-${LIBJCAT_VERSION}.tar.xz -o libjcat.tar.xz

ARG JSON_GLIB_VERSION=1.10.8
RUN curl -L https://gitlab.gnome.org/GNOME/json-glib/-/archive/${JSON_GLIB_VERSION}/json-glib-${JSON_GLIB_VERSION}.tar.gz -o json-glib.tar.gz

ARG GETTEXT_VERSION=1.0
RUN curl -L https://ftp.gnu.org/pub/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.gz -o gettext.tar.gz

ARG SQLITE3_VERSION=3.53.3
RUN curl -L https://github.com/sqlite/sqlite/archive/refs/tags/version-${SQLITE3_VERSION}.tar.gz -o sqlite3.tar.gz

ARG LIBFFI_VERSION=3.7.1
RUN curl -L https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz -o libffi.tar.gz

# libucontext provides POSIX ucontext functions absent from musl libc.
# libsystemd.so and libudev.so.1 in the hadron toolchain were compiled
# against it, so it must be present at link time and at runtime.
ARG LIBUCONTEXT_VERSION=1.5.2
RUN curl -L https://github.com/kaniini/libucontext/archive/refs/tags/libucontext-${LIBUCONTEXT_VERSION}.tar.gz -o libucontext.tar.gz


RUN tar -xf pcre2.tar.gz && mv pcre2-* pcre2
RUN tar -xf glib.tar.xz && mv glib-* glib
RUN tar -xf libxmlb.tar.xz && mv libxmlb-* libxmlb
RUN tar -xf libusb.tar.bz2 && mv libusb-* libusb
RUN tar -xf json-glib.tar.gz && mv json-glib-* json-glib
RUN tar -xf libjcat.tar.xz && mv libjcat-* libjcat
RUN tar -xf gettext.tar.gz && mv gettext-* gettext
RUN tar -xf fwupd.tar.xz && mv fwupd-* fwupd
RUN tar -xf sqlite3.tar.gz && mv sqlite-version-* sqlite3
RUN tar -xf libffi.tar.gz && mv libffi-* libffi
RUN tar -xf libucontext.tar.gz && mv libucontext-libucontext-* libucontext


FROM downloader AS pcre2
WORKDIR /sources/pcre2
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-jit --enable-utf --enable-unicode-properties --disable-dependency-tracking
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS glib2
COPY --from=pcre2 /output/ /
WORKDIR /sources/glib
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dselinux=disabled -Dxattr=false \
    -Dlibmount=disabled -Dman-pages=disabled -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled \
    -Ddocumentation=false -Dtests=false -Dinstalled_tests=false -Dnls=disabled \
    -Dglib_debug=disabled -Dglib_assert=false -Dglib_checks=false -Dlibelf=disabled -Dintrospection=disabled
RUN DESTDIR=/output ninja -C buildDir install

FROM downloader AS libxmlb
COPY --from=glib2 /output /
COPY --from=pcre2 /output /
WORKDIR /sources/libxmlb
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dgtkdoc=false -Dtests=false \
    -Dintrospection=false -Dstemmer=false -Dcli=false -Dlzma=disabled -Dzstd=disabled
RUN DESTDIR=/output ninja -C buildDir install

FROM downloader AS libusb
WORKDIR /sources/libusb
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS json-glib
COPY --from=glib2 /output /
COPY --from=pcre2 /output /
WORKDIR /sources/json-glib
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dintrospection=disabled -Dtests=false -Dinstalled_tests=false -Dconformance=false
RUN DESTDIR=/output ninja -C buildDir install

FROM downloader AS gettext
WORKDIR /sources/gettext
RUN ./configure ${COMMON_CONFIGURE_ARGS} --enable-threads=posix --disable-java --disable-dependency-tracking --disable-examples
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/output
# This contains a gazillion hello world examples in a gazillion languages, which we don't need.
RUN rm -r /output/usr/share/doc

FROM downloader AS sqlite3
WORKDIR /sources/sqlite3
ENV CFLAGS="${CFLAGS//-Os/-O2} -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_UNLOCK_NOTIFY \
	-DSQLITE_ENABLE_RTREE \
	-DSQLITE_ENABLE_GEOPOLY \
	-DSQLITE_USE_URI \
	-DSQLITE_ENABLE_DBSTAT_VTAB \
	-DSQLITE_SOUNDEX \
	-DSQLITE_MAX_VARIABLE_NUMBER=250000"
# remove lto flag from sqlite as it causes issues with linking later
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--enable-lto/}"
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
		--enable-threadsafe \
		--enable-session \
		--enable-static \
		--enable-fts3 \
		--enable-fts4 \
		--enable-fts5 \
		--soname=legacy
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} DESTDIR=/output install

# Libffi is a runtime dep of fwupd
# we have it on the toolchain for building but not on the hadron image, so we need to build it and copy the libs to the final image if the binaries require it during runtime
FROM downloader AS libffi
WORKDIR /sources/libffi
# --disable-multi-os-directory makes sure we dont install the libs under /usr/lib64
# https://github.com/libffi/libffi/issues/127
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-docs --libdir=/usr/lib --disable-multi-os-directory
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS libucontext
ARG TARGETARCH
WORKDIR /sources/libucontext
# libucontext uses its own arch naming; map Docker's TARGETARCH to it
RUN case "${TARGETARCH}" in \
      amd64) ARCH=x86_64  ;; \
      arm64) ARCH=aarch64 ;; \
      *)     ARCH="${TARGETARCH}" ;; \
    esac && \
    make ARCH="${ARCH}" && \
    make ARCH="${ARCH}" DESTDIR=/output prefix=/usr install

FROM downloader AS libjcat
COPY --from=glib2 /output /
COPY --from=pcre2 /output /
COPY --from=json-glib /output /
WORKDIR /sources/libjcat
RUN meson setup buildDir ${COMMON_MESON_FLAGS} -Dtests=false -Dintrospection=false -Dgnutls_ed25519=false -Dgnutls_pkcs7=false -Dgpg=false -Dopenssl_pkcs7=true
RUN DESTDIR=/output ninja -C buildDir install

FROM downloader AS fwupd
COPY --from=pcre2 /output/ /
COPY --from=glib2 /output/ /
COPY --from=libxmlb /output/ /
COPY --from=libusb /output/ /
COPY --from=json-glib /output/ /
COPY --from=gettext /output/ /
COPY --from=sqlite3 /output/ /
COPY --from=libjcat /output/ /
COPY --from=libucontext /output/ /
WORKDIR /sources/fwupd
# localstatedir is where it will store things like metadata. Options track
# fwupd >= 2.1: cbor, libarchive, plugin_flashrom and protobuf were removed
# upstream; logind and udev_hotplug were added and are disabled here since
# Hadron layers ship no systemd-logind and no persistent udev daemon.
RUN meson setup buildDir ${COMMON_MESON_FLAGS} --localstatedir=/usr/local -Dintrospection=disabled -Dbash_completion=false \
    -Dblkid=disabled -Dbluez=disabled -Ddocs=disabled -Dfish_completion=false -Dgnutls=disabled \
    -Dfirmware-packager=false -Dhsi=disabled -Dlibdrm=disabled -Dlibmnl=disabled -Dman=false \
    -Dlogind=disabled -Dudev_hotplug=false \
    -Dp2p_policy=none -Dpassim=disabled -Dpolkit=disabled -Dqubes=false -Dsupported_build=disabled \
    -Dtests=false -Dumockdev_tests=disabled -Dvalgrind=disabled -Db_lto=true -Dvendor_ids_dir=/usr/share/hwdata/ -Dplugin_uefi_capsule_splash=false
RUN DESTDIR=/output ninja -C buildDir install


# Merge all built outputs, strip dev artifacts, and keep only the runtime
# files needed by fwupd (binaries, shared libs, libexec helpers, runtime data).
FROM downloader AS merge
COPY --from=pcre2 /output/ /output/
COPY --from=glib2 /output/ /output/
COPY --from=libxmlb /output/ /output/
COPY --from=libusb /output/ /output/
COPY --from=json-glib /output/ /output/
COPY --from=gettext /output/ /output/
COPY --from=sqlite3 /output/ /output/
COPY --from=fwupd /output/ /output/
COPY --from=libffi /output/ /output/
COPY --from=libucontext /output/ /output/
COPY --from=libjcat /output/ /output/
RUN find /output -name "*.h"  -delete && \
    find /output -name "*.a"  -delete && \
    find /output -name "*.la" -delete && \
    find /output -name "*.pc" -delete && \
    rm -rf /output/usr/include \
           /output/usr/share/man \
           /output/usr/share/doc \
           /output/usr/share/info \
           /output/usr/share/aclocal \
           /output/usr/share/gettext \
           /output/usr/share/locale

# Final layer: only the built fwupd binaries and their runtime dependencies.
# Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/fwupd:TAG / /
# Or create a sysextension with the help of Auroraboot (https://github.com/kairos-io/auroraboot)
FROM scratch AS default
COPY --from=merge /output/etc/ /etc/
COPY --from=merge /output/usr/bin/ /usr/bin/
COPY --from=merge /output/usr/lib/ /usr/lib/
COPY --from=merge /output/usr/libexec/ /usr/libexec/
COPY --from=merge /output/usr/share/dbus-1/ /usr/share/dbus-1/
COPY --from=merge /output/usr/share/fwupd/ /usr/share/fwupd/
COPY --from=merge /output/usr/share/icons/ /usr/share/icons/
COPY --from=merge /output/usr/share/metainfo/ /usr/share/metainfo/

# Smoke-test the built layer against a Hadron base image. Any RUN failure
# here fails the build and gates the release step in CI. fwupd depends on
# a long transitive stack (glib, libxmlb, libjcat, sqlite, libusb, libffi,
# gettext) — a version check catches broken linkage, missing symbols and
# runtime loader misconfiguration in the assembled layer.
# HADRON_VERSION is pinned centrally in docker-bake.hcl and bumped by
# Renovate when a newer semver tag is published to GHCR.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /
# fwupdtool is the standalone tool — links the same libfwupd /
# libfwupdplugin stack as the daemon but does not need a running fwupd
# on DBus, so it exercises the full transitive dep chain (glib, libxmlb,
# libjcat, sqlite, libusb, libffi, gettext) at runtime. get-plugins
# additionally forces the plugin loader to initialize.
RUN fwupdtool --version
RUN fwupdtool get-plugins --json > /dev/null
