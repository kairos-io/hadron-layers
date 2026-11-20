# This dockerfile builds htop from source using the Hadron toolchain image.
# HADRON_TOOLCHAIN_VERSION is provided centrally via docker-bake.hcl.
#
# htop needs ncurses. The Hadron base image ships only libtinfo and no
# libncursesw, and the toolchain ships no ncurses at all. Shipping our own
# shared ncurses would put a second libtinfo next to the base's copy, and as a
# system extension it would overlay the base's file with a different build.
# So ncurses is built as a static library only, linked into htop, and the
# layer ships the htop binary and its desktop files, nothing the base has.
# At run time htop reads the base image's terminfo database.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION
# ncurses comes from the checksummed source cache that Hadron itself builds
# from, at the version the base image ships (NCURSES_VERSION in
# kairos-io/hadron's Dockerfile).
ARG NCURSES_VERSION=6.6

FROM ghcr.io/kairos-io/hadron-sources/ncurses:${NCURSES_VERSION} AS ncurses-download

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
WORKDIR /sources

ARG HTOP_VERSION=3.5.3
RUN curl -fL https://github.com/htop-dev/htop/releases/download/${HTOP_VERSION}/htop-${HTOP_VERSION}.tar.xz -o htop.tar.xz

COPY --from=ncurses-download /sources/downloads/ncurses.tar.gz /sources/

RUN tar -xf htop.tar.xz && mv htop-* htop
RUN tar -xf ncurses.tar.gz && mv ncurses-* ncurses

# Static, wide-character ncurses for htop to link against. It is installed
# into /deps, not /output, so none of it reaches the layer. The terminfo
# search path points at the base image's database.
FROM downloader AS ncurses
WORKDIR /sources/ncurses
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--enable-shared/}"
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
    --without-shared \
    --with-normal \
    --enable-widec \
    --enable-pc-files \
    --with-pkg-config-libdir=/usr/lib/pkgconfig \
    --with-terminfo-dirs=/etc/terminfo:/usr/share/terminfo \
    --with-default-terminfo-dir=/usr/share/terminfo \
    --without-ada \
    --without-cxx-binding \
    --without-manpages \
    --without-progs \
    --without-tests \
    --without-debug
RUN make -j"${JOBS}"
RUN make DESTDIR=/deps install.libs install.includes

FROM downloader AS builder
COPY --from=ncurses /deps/ /
WORKDIR /sources/htop
RUN ./configure ${COMMON_CONFIGURE_ARGS} \
    --enable-unicode \
    --disable-sensors \
    --disable-capabilities \
    --disable-delayacct \
    --disable-hwloc \
    --disable-unwind
RUN make -j"${JOBS}"
RUN make DESTDIR=/output install

# Strip dev artifacts from the install tree so the final layer only ships
# the binary and its data files.
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS merge
COPY --from=builder /output/ /output/
RUN rm -rf /output/usr/include \
           /output/usr/lib/pkgconfig \
           /output/usr/share/man \
           /output/usr/share/doc \
           /output/usr/share/info

# Final layer: only the htop binary and its desktop entry and icons.
# Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layers/htop:TAG / /
# Or install it as a system extension: kairos-agent sysext install htop
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
RUN htop --version
# htop links ncurses statically: only the C library is dynamic.
RUN set -eux; \
    libs=$(ldd /usr/bin/htop | grep -v -e 'ld-musl' -e 'libc\.' -e 'linux-vdso' || true); \
    [ -z "$libs" ]
# Draw one screen on a pseudo terminal and quit, to prove the static ncurses
# finds the base image's terminfo database and htop reads /proc.
RUN set -eux; \
    export TERM=xterm-256color HOME=/tmp; \
    script -q -c 'htop -n 1 -d 1' /dev/null </dev/null >/tmp/htop.out 2>&1 & pid=$!; \
    sleep 3; kill "$pid" 2>/dev/null || true; \
    grep -q 'Load average' /tmp/htop.out; \
    grep -q 'PID USER' /tmp/htop.out
