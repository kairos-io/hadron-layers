# HADRON_TOOLCHAIN_VERSION is provided centrally via docker-bake.hcl.
ARG HADRON_TOOLCHAIN_VERSION

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_TOOLCHAIN_VERSION} AS downloader
RUN mkdir -p /output

WORKDIR /sources

ARG GNUPG_VERSION=2.5.21
RUN curl -L https://gnupg.org/ftp/gcrypt/gnupg/gnupg-${GNUPG_VERSION}.tar.bz2 -o gnupg.tar.bz2

ARG LIBGPG_ERROR_VERSION=1.61
RUN curl -L https://gnupg.org/ftp/gcrypt/gpgrt/libgpg-error-${LIBGPG_ERROR_VERSION}.tar.bz2 -o libgpg-error.tar.bz2

ARG LIBGCRYPT_VERSION=1.12.2
RUN curl -L https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2 -o libgcrypt.tar.bz2

ARG LIBASSUAN_VERSION=3.0.2
RUN curl -L https://gnupg.org/ftp/gcrypt/libassuan/libassuan-${LIBASSUAN_VERSION}.tar.bz2 -o libassuan.tar.bz2

ARG LIBKSBA_VERSION=1.8.0
RUN curl -L https://gnupg.org/ftp/gcrypt/libksba/libksba-${LIBKSBA_VERSION}.tar.bz2 -o libksba.tar.bz2

ARG NPTH_VERSION=1.8
RUN curl -L https://gnupg.org/ftp/gcrypt/npth/npth-${NPTH_VERSION}.tar.bz2 -o npth.tar.bz2

ARG SQLITE3_VERSION=3.53.3
RUN curl -L https://github.com/sqlite/sqlite/archive/refs/tags/version-${SQLITE3_VERSION}.tar.gz -o sqlite3.tar.gz

RUN tar -xf gnupg.tar.bz2 && mv gnupg-* gnupg
RUN tar -xf libgpg-error.tar.bz2 && mv libgpg-error-* libgpg-error
RUN tar -xf libgcrypt.tar.bz2 && mv libgcrypt-* libgcrypt
RUN tar -xf libassuan.tar.bz2 && mv libassuan-* libassuan
RUN tar -xf libksba.tar.bz2 && mv libksba-* libksba
RUN tar -xf npth.tar.bz2 && mv npth-* npth
RUN tar -xf sqlite3.tar.gz && mv sqlite-version-* sqlite3


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


FROM downloader AS libgpg-error
WORKDIR /sources/libgpg-error
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc --disable-tests
RUN make -s -j${JOBS} && make -s -j${JOBS} install DESTDIR=/output


FROM downloader AS libgcrypt
COPY --from=libgpg-error /output/ /
WORKDIR /sources/libgcrypt
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc --disable-tests
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS libassuan
COPY --from=libgpg-error /output/ /
WORKDIR /sources/libassuan
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc --disable-tests
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS libksba
COPY --from=libgpg-error /output/ /
WORKDIR /sources/libksba
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc --disable-tests
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

FROM downloader AS npth
COPY --from=libgpg-error /output/ /
WORKDIR /sources/npth
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc --disable-tests
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output

# gpg required to verify the signatures
FROM downloader AS gpg
COPY --from=sqlite3 /output/ /
COPY --from=libgpg-error /output/ /
COPY --from=libgcrypt /output/ /
COPY --from=libksba /output/ /
COPY --from=libassuan /output/ /
COPY --from=npth /output/ /
WORKDIR /sources/gnupg
# remove --quiet flag from configure args
ENV COMMON_CONFIGURE_ARGS="${COMMON_CONFIGURE_ARGS//--quiet/}"
RUN ./configure ${COMMON_CONFIGURE_ARGS} --disable-dependency-tracking --disable-doc \
    --disable-gpgsm --disable-scdaemon --disable-dirmngr --disable-keyboxd --disable-tpm2d --disable-gpgtar \
    --disable-tofu --disable-libdns --disable-photo-viewers --disable-card-support --disable-ccid-driver --disable-ntbtls \
    --disable-ldap --disable-nls --disable-tests --disable-wks-tools
RUN make -s -j${JOBS}
RUN make -s -j${JOBS} install DESTDIR=/output


# Merge all built outputs and strip dev artifacts (headers, static libs, pkgconfig,
# man pages) so the final layer only contains runtime binaries and shared libraries.
FROM downloader AS merge
COPY --from=sqlite3 /output/ /output/
COPY --from=libgpg-error /output/ /output/
COPY --from=libgcrypt /output/ /output/
COPY --from=libksba /output/ /output/
COPY --from=libassuan /output/ /output/
COPY --from=npth /output/ /output/
COPY --from=gpg /output/ /output/
RUN find /output -name "*.h"  -delete && \
    find /output -name "*.a"  -delete && \
    find /output -name "*.la" -delete && \
    find /output -name "*.pc" -delete && \
    rm -rf /output/usr/include \
           /output/usr/share/man \
           /output/usr/share/doc \
           /output/usr/share/info \
           /output/usr/share/aclocal \
           /output/usr/share/common-lisp

# Final layer: only the built gpg binaries and their runtime dependencies.
# Use as a layer on top of Hadron:
#   FROM ghcr.io/kairos-io/hadron:VERSION
#   COPY --from=ghcr.io/kairos-io/hadron-layer-gpg:TAG / /
# Or create a sysextension with the help of Auroraboot (https://github.com/kairos-io/auroraboot)
FROM scratch AS default
COPY --from=merge /output/ /

# Smoke-test the built layer against a Hadron base image. Any RUN failure
# here fails the build and gates the release step in CI. Runs an offline
# sign/verify roundtrip with an ephemeral keypair to exercise libgcrypt,
# libgpg-error, libassuan and libksba in one shot.
FROM ghcr.io/kairos-io/hadron:latest AS test
COPY --from=default / /
RUN gpg --version
RUN gpgv --version
RUN set -eux; \
    export GNUPGHOME=$(mktemp -d); \
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-gen-key 'Hadron Test <test@hadron.local>' rsa2048 default 1y; \
    gpg --list-keys | grep -q test@hadron.local; \
    echo "hadron layer smoke test" > /tmp/msg; \
    gpg --batch --pinentry-mode loopback --passphrase '' --sign /tmp/msg; \
    gpg --verify /tmp/msg.gpg; \
    rm -rf "$GNUPGHOME" /tmp/msg /tmp/msg.gpg
