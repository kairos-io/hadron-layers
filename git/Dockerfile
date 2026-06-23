# This dockerfile builds git from source using the Hadron toolchain image.
# HADRON_TOOLCHAIN_VERSION is provided centrally via docker-bake.hcl.

ARG HADRON_TOOLCHAIN_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS builder

ARG GIT_VERSION=2.52.0
WORKDIR /build
RUN curl -L https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz -o git.tar.xz && tar -xf git.tar.xz && rm git.tar.xz && mv git-* git-src
WORKDIR /build/git-src
# git's autoconf has run-time tests with no cross-compile fallback. COMMON_CONFIGURE_ARGS
# passes --host=${TARGET} (vendor "hadron") and --build (vendor "pc"), which differ and make
# autoconf assume cross-compilation, so configure aborts with "cannot run test program while
# cross compiling". Override --build to ${TARGET} so it always matches --host (on any arch)
# and the build is treated as native. See #238.
RUN ./configure ${COMMON_CONFIGURE_ARGS} --build=${TARGET} \
    --without-tcltk --without-gettext
RUN make install prefix=/usr DESTDIR=/output NO_TCLTK=YesPlease NO_GETTEXT=YesPlease

# Strip dev artifacts from the install tree so the final layer only ships
# runtime binaries, libexec helpers, shared libraries, and data files.
FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS merge
COPY --from=builder /output/ /output/
RUN find /output -name "*.h"  -delete && \
    find /output -name "*.a"  -delete && \
    find /output -name "*.la" -delete && \
    find /output -name "*.pc" -delete && \
    rm -rf /output/usr/include \
           /output/usr/share/man \
           /output/usr/share/doc \
           /output/usr/share/info \
           /output/usr/share/aclocal

# Final layer: only the built git binaries and their runtime dependencies.
# Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layer-git:TAG / /
# Or create a sysextension with the help of Auroraboot (https://github.com/kairos-io/auroraboot)
FROM scratch AS default
COPY --from=merge /output/ /
