# This dockerfile builds git from source using the Hadron toolchain image.
# HADRON_TOOLCHAIN_VERSION is provided centrally via docker-bake.hcl.

ARG HADRON_TOOLCHAIN_VERSION
ARG HADRON_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS builder

ARG GIT_VERSION=2.55.0
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
# NO_RUST disables the experimental libgitcore.a Rust build introduced in
# git 2.55. It requires cargo which the hadron-toolchain image does not
# ship. Rust is optional through the git 2.x series and mandatory from
# git 3.0; drop NO_RUST once the toolchain provides cargo.
RUN make install prefix=/usr DESTDIR=/output NO_TCLTK=YesPlease NO_GETTEXT=YesPlease NO_RUST=YesPlease

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
#   COPY --from=ghcr.io/kairos-io/git:TAG / /
# Or create a sysextension with the help of Auroraboot (https://github.com/kairos-io/auroraboot)
FROM scratch AS default
COPY --from=merge /output/ /

# Smoke-test the built layer against a Hadron base image. Any RUN failure
# here fails the build and gates the release step in CI. Kept fully offline
# so the test is deterministic and does not depend on external network.
# HADRON_VERSION is pinned centrally in docker-bake.hcl and bumped by
# Renovate when a newer semver tag is published to GHCR.
FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS test
COPY --from=default / /
RUN git --version
RUN set -eux; \
    export HOME=/tmp; \
    git config --global user.email test@hadron.local; \
    git config --global user.name test; \
    mkdir -p /tmp/repo && cd /tmp/repo; \
    git init -q -b main; \
    echo hello > file.txt; \
    git add file.txt; \
    git commit -q -m initial; \
    git log --oneline | grep -q initial; \
    git checkout -q -b feature; \
    echo world >> file.txt; \
    git commit -q -am update; \
    git checkout -q main; \
    git merge -q --no-ff feature -m merge; \
    [ "$(git log --oneline | wc -l)" = 3 ]
