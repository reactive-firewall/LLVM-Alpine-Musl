# syntax=docker/dockerfile:1

# ---- fetcher stage: install and cache required Alpine packages and fetch release tarballs ----

# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS fetcher

# - Use pinned versions -
# Versions are passed through by Docker.
# shellcheck disable=SC2154
ARG LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION:-1.3}
# shellcheck disable=SC2154
ARG LLVM_VERSION=${LLVM_VERSION:-22.1.5}
# shellcheck disable=SC2154
ARG MUSL_VERSION=${MUSL_VERSION:-1.2.6}

# OTHER VARS - BUILD HOST ONLY (NOT USED ATM)
# shellcheck disable=SC2154
#ARG HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION:-"17.2"}

# Set Source URL environment variables
ARG LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION:-"1.3"}
ENV LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION}
ENV LIBEXECINFO_URL="https://github.com/reactive-firewall/libexecinfo/raw/refs/tags/v${LIBEXECINFO_VERSION}/libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2"
ENV LIBCXXRT_URL="https://github.com/reactive-firewall/libcxxrt/archive/refs/heads/master.tar.gz"
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"

# OTHER VARS - BUNDLE ONLY (NOT USED ATM)
#ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"

# Set Source URL environment variables
ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"

# label the fetcher
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="cURL License"
LABEL org.opencontainers.image.description="Transient source fetching container. Do not bundle."

# Install necessary packages (for fetcher)
# ca-certificates - MPL AND MIT - do not bundle - just to verify certificates (weak)
# alpine - MIT - do not bundle - just need an OS (weak)
# curl - curl License / MIT (direct)
# bsdtar - BSD-2 - used to unarchive during bootstrap (transient)

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add \
    ca-certificates \
    curl \
    cmd:bsdtar && \
  update-ca-certificates

# Stage fetched sources for an otherwise hermetic build
# just need a place to fetch
RUN mkdir -p /fetch
WORKDIR /fetch

# Fetch the signed release tarballs (or supply via build-args)
# Download musl
RUN curl -fSLo musl-${MUSL_VERSION}.tar.gz \
      --retry 5 \
      --retry-connrefused \
      --retry-delay 2 \
      --ssl-no-revoke \
    --url "$MUSL_URL" && \
    bsdtar -xzf musl-${MUSL_VERSION}.tar.gz && \
    rm musl-${MUSL_VERSION}.tar.gz && \
    mv /fetch/musl-${MUSL_VERSION} /fetch/musl
# get libexecinfo (patched mirror)
RUN curl -fSLo libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 \
    --retry 3 \
    --retry-connrefused \
    --retry-delay 2 \
    --ssl-no-revoke \
    --url "$LIBEXECINFO_URL" && \
    bsdtar -xzf libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 && \
    rm libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 && \
    mv /fetch/libexecinfo-${LIBEXECINFO_VERSION}r /fetch/libexecinfo && \
    rm /fetch/libexecinfo/patches.tar.bz2
# get libcxxrt (mirror)
RUN curl -fSLo libcxxrt-project.tar.gz \
    --retry 3 \
    --retry-connrefused \
    --retry-delay 2 \
    --ssl-no-revoke \
    --url "$LIBCXXRT_URL" && \
    bsdtar -xzf libcxxrt-project.tar.gz && \
    rm libcxxrt-project.tar.gz && \
    mv /fetch/libcxxrt-master /fetch/libcxxrt
# get llvm-project
RUN curl -fSLo llvmorg-${LLVM_VERSION}.tar.gz \
    --retry 3 \
    --retry-connrefused \
    --retry-delay 2 \
    --ssl-no-revoke \
    --url "$LLVM_URL" && \
    bsdtar -xzf llvmorg-${LLVM_VERSION}.tar.gz && \
    rm llvmorg-${LLVM_VERSION}.tar.gz && \
    mv /fetch/llvm-project-llvmorg-${LLVM_VERSION} /fetch/llvmorg

# OPTIONAL - UNUSED by default (DO NOT BUNDLE)
# get HOST linux Headers
#RUN curl -fsSLo linux-6.${HOST_HEADERS_VERSION}.tar.gz \
#    --url "https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz" && \
#    bsdtar -xzf linux-6.${HOST_HEADERS_VERSION}.tar.gz && \
#    rm linux-6.${HOST_HEADERS_VERSION}.tar.gz && \
#    mv /fetch/linux-6.${HOST_HEADERS_VERSION} /fetch/linux


# --- Strip-to-headers Stage: prepare stripped linux headers for musl sysroot ---
# shellcheck disable=SC2154
#FROM --platform="linux/${TARGETARCH}" alpine:latest AS linux-trampoline

#ARG HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION:-"17.2"}
#ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"

# DO NOT VENDOR
#LABEL org.opencontainers.image.vendor="NULL"
# note as GPL poisoned (transient)
#LABEL org.opencontainers.image.licenses="GPL-2.0"
#LABEL org.opencontainers.image.description="OPTIONAL, transient public headers extraction trampoline. Do not bundle."

#RUN set -eux \
#    && apk add --no-cache \
#        cmd:bsdtar \
#        clang \
#        cmd:clang++ \
#        llvm \
#        libc++ \
#        libc++-dev \
#        compiler-rt \
#        llvm-runtimes \
#        cmd:llvm-ar \
#        lld \
#        make \
#        binutils \
#        curl \
#        ca-certificates \
#        build-base \
#        gzip \
#        perl \
#        paxctl

# copy optional linux sources (for musl to use headers)
#COPY --from=fetcher /fetch/linux /build/linux
#ENV CC=clang
#ENV CXX=clang++
#ENV AR=llvm-ar
#ENV ASM=clang
#ENV RANLIB=llvm-ranlib
#ENV LDFLAGS="-fuse-ld=lld"

#WORKDIR /build/linux

#RUN make headers -j$(nproc) && \
#    find usr/include -type f ! -name '*.h' -delete

# clean up tools for smaller image
#RUN set -eux \
#    && apk del --no-cache \
#        cmd:bsdtar \
#        clang \
#        cmd:clang++ \
#        llvm \
#        libc++ \
#        libc++-dev \
#        compiler-rt \
#        llvm-runtimes \
#        cmd:llvm-ar \
#        lld \
#        make \
#        binutils \
#        curl \
#        ca-certificates \
#        build-base \
#        gzip \
#        perl \
#        paxctl

# --- Prepare Stage: prepare a sysroot for bootstrapping with musl ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS sysroot-bootstrap

# Use pinned versions
# version is passed through by Docker.
# shellcheck disable=SC2154
ARG LLVM_VERSION=${LLVM_VERSION:-22.1.5}
# shellcheck disable=SC2154
ARG MUSL_VERSION=${MUSL_VERSION:-1.2.6}

# Configure or apply override for musl related environment variables
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
ENV MUSL_PREFIX="/usr"
ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

# Configure or apply override for LLVM related environment variables
# Compiler runtime library
ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"
ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"
# Targets & triples
ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
# Sysroot path
ENV SYSROOT="/sysroot"

# Just Need a bootstrap host to build our bootstrap host.
# WORKAROUND: Install necessary packages (for bootstrapping a musl sysroot)
# alpine - MIT - do not bundle - just need an OS (weak)
# cmd:file - BSD-2-Clause - optional for tests (weak)
# binutils - GPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-3-Clause
#            - do not bundle
#            - just to bootstrap compiler builtins (transient)
#            - and just to provide a c++ implementation for LLVM (transient) - see llvm-runtime
#            - and optionally just to provide a zlib implementation (transient)
#            - and installed by build-base (weak)
# build-base - MIT - used to bootstrap - (transient)
# cmd:make - GPL-3.0-or-later - do not bundle - just need make to bootstrap musl (weak)
# compiler-rt - Apache-2.0 WITH LLVM-exception / Apache-2.0 - just need a compiler runtime (transient)
# cmd:clang - Apache-2.0 WITH LLVM-exception / Apache-2.0 - used to compile musl - (direct)
# libc++ / libc++-dev - Apache-2.0 WITH LLVM-exception / Apache-2.0
#              - just need a c++ implementation while bootstrapping clang_rt.builtins (transient)
#              - and just to provide a c++ implementation for LLVM (transient)
# llvm - Apache-2.0 WITH LLVM-exception / Apache-2.0 - just need a working toolchain (weak)
# lld - Apache-2.0 WITH LLVM-exception / Apache-2.0 - just need a working linker (transient)
# llvm - Apache-2.0 WITH LLVM-exception / Apache-2.0 - just need a working toolchain (weak)
# llvm-runtimes - Apache-2.0 WITH LLVM-exception / Apache-2.0
#                 - just need a compiler runtime (transient)
#                 - and just to provide a c++ implementation for LLVM (transient)
#                 - and just need a unwinder implementation for compiler runtime (transient)
# does not use cmd:bsdtar nor gzip

RUN set -eux \
    && apk add --no-cache \
        cmd:clang \
        llvm \
        libc++ \
        libc++-dev \
        compiler-rt \
        llvm-runtimes \
        cmd:llvm-ar \
        lld \
        cmd:make \
        binutils \
        build-base \
    && mkdir -pv /build && mkdir -pv "${SYSROOT}"

# Label the sysroot-bootstrap
# DO NOT VENDOR
#LABEL org.opencontainers.image.vendor="NULL"
# note as Apache-2.0 albeit GPL poisoned (transient)
LABEL org.opencontainers.image.licenses="Apache-2.0 WITH LLVM-exception OR GPL-3.0"
LABEL org.opencontainers.image.description="Transient container for bootstrapping a sysroot with musl. Do not bundle."

# Initialize container working directory to better ensure overall reproducibility
WORKDIR /tmp

# --- Prepare sysroot skeleton ---

# IMPORTANT:
# carefully craft symlinks to only look deeper, build tools like ninja don't resolve symlinks well
# see https://github.com/ninja-build/ninja/issues/1330

RUN set -eux && \
    mkdir -pv "${SYSROOT}"/dev && \
    mkdir -pv "${SYSROOT}"/proc && \
    mkdir -pv "${SYSROOT}"/run && \
    mkdir -pv "${SYSROOT}"/sys && \
    mkdir -pv "${SYSROOT}"/share && \
    mkdir -pv "${SYSROOT}"/man && \
    mkdir -pv "${SYSROOT}"/tmp && \
    mkdir -pv "${SYSROOT}"/etc && \
    mkdir -pv "${SYSROOT}/usr/lib" && \
    mkdir -pv "${SYSROOT}/usr/libexec" && \
    mkdir -pv "${SYSROOT}/usr/bin" && \
    mkdir -pv "${SYSROOT}/usr/sbin" && \
    ln -sfv usr/bin "${SYSROOT}/bin" && \
    ln -sfv usr/sbin "${SYSROOT}/sbin" && \
    ln -sfv usr/lib "${SYSROOT}/lib" && \
    ln -sfv usr/libexec "${SYSROOT}/libexec" && \
    ln -sfv ../etc "${SYSROOT}/usr/etc" && \
    ln -sfv ../share "${SYSROOT}/usr/share" && \
    ln -sfv ../man "${SYSROOT}/usr/man"

# Some systems expect /lib64 -> /lib for x86_64. Create symlink if appropriate (unsupported by musl).
RUN set -eux; \
    if [ "$(uname -m)" = "x86_64" ]; then \
      [ -d "${SYSROOT}"/lib64 ] || [ -L "${SYSROOT}"/lib64 ] || ln -svf usr/lib "${SYSROOT}"/lib64; \
      [ -d "${SYSROOT}"/usr/lib64 ] || [ -L "${SYSROOT}"/usr/lib64 ] || ln -svf lib "${SYSROOT}"/usr/lib64; \
    fi

WORKDIR /build

# Configure bootstrapping toolchain related environment variables
# prefer LLVM's toolchain (clang, lld, llvm-ar, llvm-ranlib, etc.)
ENV CC=clang
ENV CPP="${CC:-clang} -E"
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="${CC:-clang} -integrated-as -c"
ENV ASM="${CC:-clang} -integrated-as -S"
ENV LD=ld.lld
ENV RANLIB=llvm-ranlib

# Configure bootstrapping tool flags via more environment variables
#
# Key Bootstrapping compiler Flags (for musl-based builds)
# Use -fPIC everywhere for position independent code
# Musl Libc understands -D_ALL_SOURCE (but defaults to -D_DEFAULT_SOURCE / -D_BSD_SOURCE)
# Musl can expose some POSIX interfaces, so use -D_POSIX_C_SOURCE=200809L to expose those.
# MAY want try -D_POSIX_C_SOURCE=202405L instead for v1.2.6+ (TODO: review)
# Musl can expose some XOPEN interfaces too, so use -D_XOPEN_SOURCE=700 to configure those.
# musl should be given these values too
ENV CFLAGS="-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -fPIC"
# musl provides a C aware dynamic loader/linker implementation, once built
# but can't use -Wl,--dynamic-linker=/lib/ld-musl-{x86_64,aarch64,armv7}.so.1 just yet
# Key Linker Flags (for musl bootstraping)
# Use -fPIC everywhere for position independent code (yes when linking too)
# Also pass --pic-veneer to the linker whenever supported (e.g. lld)
# Use -fuse-ld=lld to prefer linking with LLVM's lld (simplifies cross-target linking)
# Also pass -z relro to the linker whenever supported (helps prevent runtime GOT/PLT overwrites)
# Also pass -z now to the linker whenever supported (helps prevent lazy-binding attacks)
ENV LDFLAGS="-fPIC -fuse-ld=lld -Wl,--sysroot=/sysroot -Wl,--pic-veneer -Wl,-z,relro -Wl,-z,now"
# musl is C but some of the clang_rt builtins are C++
# Use -stdlib=libc++ to specify using LLVM's libc++ implementation (mostly just to be consistent)
# Use -fPIC everywhere for position independent code
# Use -target ${TARGET_TRIPLE} to avoid auto-detection while bootstrapping
ENV CXXFLAGS="-stdlib=libc++ -fPIC -target ${TARGET_TRIPLE}"

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# An 'epoch' based date-string is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

# Copy sources (for musl headers)
COPY --from=fetcher /fetch/musl /build/musl

# OPTIONAL - Copy OS headers to $SYSROOT - UNUSED by default (for a more OS agnostic bootstrap)

# musl's source looks for at-least the following headers to pull-in ...
# TODO: add shims if relevant or clean-room replacements if possible
# linux/kd.h
# linux/soundcard.h
# linux/vt.h

# OPTIONAL - musl build works without linux headers (unused for improved build isolation)
#COPY --from=linux-trampoline /build/linux/usr/include /sysroot/usr/include

# Copy LLVM toolchain sources (for compiler_rt, or rather the clang_rt builtins for now)
COPY --from=fetcher /fetch/llvmorg /build/llvm


# --- Prepare Stage 1 of 3: prepare sysroot with musl headers ---
WORKDIR /build/musl

# Configure, build, and install musl headers using LLVM tools
# IMPORTANT: cleanup the headers build after installing headers (see stage 3 of bootstrapping sysroot)
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
      --enable-wrapper=clang \
      --disable-gcc-wrapper \
      CC=clang \
      CXX=clang++ \
      AR=llvm-ar RANLIB=llvm-ranlib \
      LDFLAGS="${LDFLAGS}" \
      CXXFLAGS="${CXXFLAGS}" \
      CFLAGS="${CFLAGS} -rtlib=compiler-rt -fno-math-errno -fPIC -fno-common" && \
    make -j"$(nproc)" && \
    DESTDIR="${SYSROOT}" make install-headers && \
    rm -rf ./build

# OPTIONAL - Ensure we have the musl headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include && \
    file ${SYSROOT}${MUSL_PREFIX}/include/* || true ;


# --- Prepare Stage 2 of 3: prepare sysroot with builtins for TARGET_TRIPLE ---
WORKDIR /build/llvm

# install additional tools for building llvm clang_rt builtins
# cmake - BSD-3-Clause - used as a pre-build tool while bootstrapping - (weak)
# cmd:clang++ - Apache-2.0 WITH LLVM-exception / Apache-2.0 - used to compile parts of clang_rt - (weak)
# cmd:find - GPL-3.0-or-later - do not bundle - just need a tool to iterate over files and filter results - (weak)
# cmd:perl - Artistic-1.0-Perl OR GPL-1.0 - do not bundle - used by llvm build automation (weak)
# cmd:paxctl - GPL-2.0-only - might be used for testing hardened ELF stuff (UNUSED)
# python3 - PSF-2.0 / Python Software Foundation license 2.0 - do not bundle (transient)
# samurai - Apache-2.0 - do not bundle - just need a build-tool implementation (weak)
# zlib-dev - Zlib / - see https://zlib.net/zlib_license.html - used by LLVM toolchain (transient)
RUN set -eux \
    && apk add --no-cache \
        cmake \
        cmd:clang++ \
        cmd:find \
        cmd:perl \
        pkgconfig \
        python3 \
        samurai \
        zlib-dev


# --- Precompile CC builtins: prepare sysroot with clang builtins for TARGET_TRIPLE ---
RUN cmake -S compiler-rt -B build-compiler-rt -G "Ninja" \
      -DCMAKE_INSTALL_PREFIX="${SYSROOT}${MUSL_PREFIX}" \
      -DLLVM_CMAKE_DIR=/build/llvm/cmake/modules \
      -DLLVM_MAIN_SRC_DIR=/build/llvm/llvm \
      -DCOMPILER_RT_BUILD_BUILTINS=ON \
      -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_BUILD_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
      -DCOMPILER_RT_BUILD_XRAY=OFF \
      -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
      -DCOMPILER_RT_BUILD_ORC=OFF \
      -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-fPIC -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_SYSTEM_NAME=Generic \
      -DLIBC_TARGET_TRIPLE=${TARGET_TRIPLE} \
      -DCMAKE_LINKER=lld \
      -DCMAKE_SYSROOT="${SYSROOT}" && \
      cmake --build build-compiler-rt && \
      cmake --install build-compiler-rt && \
      rm -rfv build-compiler-rt

# Cleanup and purge transitive stuff once not needed
RUN set -eux \
    && apk del --no-cache \
        samurai \
        cmake \
        python3 \
        pkgconfig \
        perl \
        paxctl 2>/dev/null || true ;

# Ensure we have the clang builtins lib
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/generic/ || true;
# TODO: test for expected clang_rt.* lib


# --- Prepare Stage 3 of 3: compile musl with compiler_rt ---
WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
      --enable-wrapper=clang \
      --disable-gcc-wrapper \
      CC=clang \
      AR=llvm-ar RANLIB=llvm-ranlib \
      LDFLAGS="${LDFLAGS}" \
      LIBCC="-l${SYSROOT}${MUSL_PREFIX}/lib/generic/${LLVM_RTLIB}" \
      CXXFLAGS="${CXXFLAGS}" \
      CFLAGS="${CFLAGS} --sysroot=$SYSROOT -rtlib=compiler-rt -fno-math-errno -fPIC -fno-common -fuse-ld=lld" && \
    make -j"$(nproc)" && \
    DESTDIR=${SYSROOT} make install

# TODO: implement bootstraping tool to walk dirs and find files with glob names and
#       then update those matches filesystem dates (and decouple from overkill find tool here)
# Strip unneeded symbols from shared objects to save space (optional)
RUN set -eux \
    && if command -v llvm-strip >/dev/null 2>&1; then \
         find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.so*" -exec llvm-strip --strip-unneeded {} + || true; \
         find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.o*" -exec llvm-strip --strip-unneeded {} + || true; \
       else \
         find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.so*" -exec strip --strip-unneeded {} + || true; \
         find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.o*" -exec strip --strip-unneeded {} + || true; \
       fi

# Ensure loader has canonical name (example: /lib/libc.so ->/lib/ld-musl-x86_64.so.1)
RUN set -eux \
    && ln -fns libc.so "${SYSROOT}${MUSL_PREFIX}/lib/${MUSL_LDLIB}" \
    && ln -fns "${MUSL_LDLIB}" "${SYSROOT}${MUSL_PREFIX}/lib/ld-musl.so.1"

# TODO: implement bootstraping tool to walk dirs and find files with glob names and
#       then update those matches filesystem dates (and decouple from overkill find tool here)
# touch artifacts to make more reproducible (optional)
RUN find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.so" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.o" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.a" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/include -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/bin -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true;

# Ensure we have the dynamic loader and libs present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/lib || true && \
    file ${SYSROOT}${MUSL_PREFIX}/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true && \
    file ${SYSROOT}${MUSL_PREFIX}/include/* || true

# Ensure we have the libc linking wrapper present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/bin || true && \
    file ${SYSROOT}${MUSL_PREFIX}/bin/* || true

# Cleanup and purge transient packages (no-longer needed)
RUN set -eux \
    && apk del --no-cache \
        binutils \
        build-base \
        cmd:clang \
        cmd:clang++ \
        cmd:llvm-ar \
        cmd:make \
        compiler-rt \
        libc++ \
        libc++-dev \
        lld \
        llvm \
        llvm-runtimes \
        make \
        cmd:find \
        zlib-dev || true;

# --- Prepare Stage: Bootstrap sysroot with musl and builtins ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS sysroot

# Use pinned versions
# version is passed through by Docker.
# shellcheck disable=SC2154
ARG LLVM_VERSION=${LLVM_VERSION:-22.1.5}
# shellcheck disable=SC2154
ARG MUSL_VERSION=${MUSL_VERSION:-1.2.6}

# Configure or apply override for musl related environment variables
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
ENV MUSL_PREFIX="/usr"
ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

# Configure or apply override for LLVM related environment variables
# Compiler runtime library
ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"
ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"
# Targets & triples
ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
# Sysroot path
ENV SYSROOT="/sysroot"

# Label the sysroot-trampoline
# Do not need to vendor
LABEL org.opencontainers.image.vendor="individual"
# note as Apache-2.0 WITH LLVM-exception (transient)
LABEL org.opencontainers.image.licenses="Apache-2.0 WITH LLVM-exception"
LABEL org.opencontainers.image.description="Transient container for a sysroot with musl."


# Configure bootstrapping toolchain related environment variables (for providence)
# prefer LLVM's toolchain (clang, lld, llvm-ar, llvm-ranlib, etc.)
ENV CC=clang
ENV CPP="${CC:-clang} -E"
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="${CC:-clang} -integrated-as -c"
ENV ASM="${CC:-clang} -integrated-as -S"
ENV LD=ld.lld
ENV RANLIB=llvm-ranlib

# Configure bootstrapping tool flags via more environment variables (for providence)
#
# Key Bootstrapping compiler Flags (for musl-based builds)
# Use -fPIC everywhere for position independent code
# Musl Libc understands -D_ALL_SOURCE (but defaults to -D_DEFAULT_SOURCE / -D_BSD_SOURCE)
# Musl can expose some POSIX interfaces, so use -D_POSIX_C_SOURCE=200809L to expose those.
# MAY want try -D_POSIX_C_SOURCE=202405L instead for v1.2.6+ (TODO: review)
# Musl can expose some XOPEN interfaces too, so use -D_XOPEN_SOURCE=700 to configure those.
# musl should be given these values too
ENV CFLAGS="-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -fPIC"
# musl provides a C aware dynamic loader/linker implementation, now built
# can use -Wl,--dynamic-linker=/lib/ld-musl-{x86_64,aarch64,armv7}.so.1 (but match bootstrap)
# Key Linker Flags (for musl bootstraping)
# Use -fPIC everywhere for position independent code (yes when linking too)
# Also pass --pic-veneer to the linker whenever supported (e.g. lld)
# Use -fuse-ld=lld to prefer linking with LLVM's lld (simplifies cross-target linking)
# Also pass -z relro to the linker whenever supported (helps prevent runtime GOT/PLT overwrites)
# Also pass -z now to the linker whenever supported (helps prevent lazy-binding attacks)
ENV LDFLAGS="-fPIC -fuse-ld=lld -Wl,--sysroot=/sysroot -Wl,--pic-veneer -Wl,-z,relro -Wl,-z,now"
# musl is C but some of the clang_rt builtins are C++
# Use -stdlib=libc++ to specify using LLVM's libc++ implementation (mostly just to be consistent)
# Use -fPIC everywhere for position independent code
# Use -target ${TARGET_TRIPLE} to avoid auto-detection while bootstrapping
ENV CXXFLAGS="-stdlib=libc++ -fPIC -target ${TARGET_TRIPLE}"

# Set TZ to UTC (for consistency)
ENV TZ='UTC+0'

# An 'epoch' based date-string is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

# --- runtime Trampoline Stage: Copy just the bootstrapped sysroot ---
COPY --from=sysroot-bootstrap /sysroot /sysroot

# Ensure the dynamic loader is configured to search paths correctly
COPY payloads/etc/ld-musl-x86_64.path /etc/ld-musl-x86_64.path
RUN set -eux; \
    if [ "$(uname -m)" = "x86_64" ]; then \
      [ -L "${SYSROOT}"/etc/ld-musl-i486.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i486.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-i586.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i586.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-i686.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i686.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-x86h.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-x86_64h.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-generic.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-generic.path; \
    fi ;

COPY payloads/etc/ld-musl-aarch64.path /etc/ld-musl-aarch64.path
RUN set -eux; \
    if [ "$(uname -m)" = "aarch64" ]; then \
      [ -L "${SYSROOT}"/etc/ld-musl-generic.path ] || ln -svf ld-musl-aarch64.path "${SYSROOT}"/etc/ld-musl-generic.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-armv8.path ] || ln -svf ld-musl-aarch64.path "${SYSROOT}"/etc/ld-musl-armv8.path; \
    fi;

COPY payloads/etc/ld-musl-arm.path /etc/ld-musl-arm.path
RUN set -eux; \
    [ -L "${SYSROOT}"/etc/ld-musl-armv7.path ] || ln -svf ld-musl-arm.path "${SYSROOT}"/etc/ld-musl-armv7.path; \
    [ -L "${SYSROOT}"/etc/ld-musl-armhf.path ] || ln -svf ld-musl-arm.path "${SYSROOT}"/etc/ld-musl-armhf.path;

RUN printf '#! /bin/sh --norc\n%s\n' "no_op_cmd() { return 0; } ; no_op_cmd ;" >"${SYSROOT}/bin/:" && \
    chmod 755 "${SYSROOT}/bin/:"


# --- unwind-base: bootstrap unwind using distro clang/llvm to compile a minimal unwind library ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-unwind-base

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot

# copy ehframe.ld script
COPY payloads/ld.libunwind/ehframe.ld /bootstrap/ehframe.ld

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# Install distro packages that provide clang able to cross-emit --target. Adjust names for Alpine tag.
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm \
    lld \
    libc++ \
    libc++-dev \
    compiler-rt \
    cmd:llvm-ar \
    llvm-runtimes \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    pkgconfig \
    cmd:clang-cpp \
    cmd:llvm-strip \
    cmd:find

#    cmd:llvm-otool \
#    cmd:llvm-nm

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

# --- unwind-base: bootstrap unwind using distro clang/llvm to compile a minimal unwind library ---
FROM --platform="linux/${TARGETARCH}" build-unwind-base AS build-unwind-static

WORKDIR /bootstrap

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# may need -Wl,--sysroot=/sysroot
# may want to play around with -Wl,--allow-shlib-undefined to allow __eh_* undefs (see ehframe.ld)
ENV LDFLAGS="-Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic -Wl,--unique -Wl,--dynamic-linker=/sysroot/lib/${MUSL_LDLIB} -Wl,--pic-veneer -Wl,-z,relro -Wl,-z,now -fPIC -fuse-ld=lld --unwindlib=none"
# does NOT require -D__linux__
ENV CFLAGS="--target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT:-/sysroot}/usr/include"
ENV CXXFLAGS="--target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0"

WORKDIR /bootstrap/llvmorg

# might need LDFLAGS="-Wl,--exclude-libs,libssp_nonshared.a"
# also might need -DCMAKE_C_FLAGS="-fno-stack-protector" -DCMAKE_CXX_FLAGS="-fno-stack-protector"

# Build minimal static llvm libunwind (install to sysroot)
RUN cmake -S runtimes -B build-libunwind -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT:-/sysroot}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm/cmake/modules \
    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
    -DClang_DIR=/bootstrap/llvmorg/clang \
    -DLLVM_ENABLE_RUNTIMES="libunwind" \
    -DLIBUNWIND_WEAK_PTHREAD_LIB=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBUNWIND_HAS_NODEFAULTLIBS_FLAG=OFF \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -Qunused-arguments" \
    -DLIBUNWIND_HAS_DL_LIB=OFF \
    -DLIBUNWIND_IS_BAREMETAL=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DLIBUNWIND_ENABLE_STATIC=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang-cpp \
    -DCMAKE_LINKER=lld && \
    apk del --no-cache \
        g++ \
        cmd:g++ \
        cmd:find && \
    ls -lap /bootstrap/llvmorg/build-libunwind/ && \
    cmake --build build-libunwind && \
    cmake --install build-libunwind && \
    rm -vfr /bootstrap/llvmorg/build-libunwind/

# prepare static libunwind overlay stage
RUN mkdir -pv /stage-static/usr/include/mach-o && mkdir -pv /stage-static/usr/lib && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a ; do \
          cp -vn ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} /stage-static/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" /stage-static/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        llvm \
        lld \
        libc++ \
        libc++-dev \
        compiler-rt \
        cmd:llvm-ar \
        llvm-runtimes \
        cmake \
        python3 \
        samurai

# --- build-unwind: bootstrap unwind using distro clang/llvm to compile a minimal unwind library ---
FROM --platform="linux/${TARGETARCH}" build-unwind-base AS build-unwind

WORKDIR /bootstrap

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CPP=clang-cpp
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# may need -Xlinker --sysroot=/sysroot OR -Xlinker --dynamic-linker=/lib/libc.so
# may need to play around with -Wl,--allow-shlib-undefined to allow __eh_* undefs
# may want --unwindlib=none when building libunwind
# may want -Xlinker --exclude-libs=libgcc_s.so.1
ENV LDFLAGS="-Xlinker --sysroot=/sysroot -Xlinker -L -Xlinker /sysroot/usr/lib -Xlinker -L -Xlinker /sysroot/lib -Xlinker -L -Xlinker /sysroot/usr/lib/generic -Xlinker --unique -Xlinker --dynamic-linker=/sysroot/lib/${MUSL_LDLIB} -fPIC -Xlinker --pic-veneer -Xlinker -z -Xlinker relro -Xlinker -z -Xlinker now -fuse-ld=lld -Xlinker --script=/bootstrap/ehframe.ld"
# may require -D__linux__
ENV CFLAGS="-rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT:-/sysroot}/usr/include -iwithsysroot /usr/include"
ENV CXXFLAGS="-rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0"

WORKDIR /bootstrap/llvmorg

# might need LDFLAGS="-Wl,--exclude-libs,libssp_nonshared.a"
# also might need -DCMAKE_C_FLAGS="-fno-stack-protector" -DCMAKE_CXX_FLAGS="-fno-stack-protector"

# and again for shared lib (but use clang++ for first pass)
RUN cmake -S runtimes -B build-libunwind -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT:-/sysroot}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm/cmake/modules \
    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
    -DClang_DIR=/bootstrap/llvmorg/clang \
    -DLLVM_ENABLE_RUNTIMES="libunwind" \
    -DLIBUNWIND_WEAK_PTHREAD_LIB=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -v -Qunused-arguments -Xlinker --eh-frame-hdr -Xlinker --verbose" \
    -DLIBUNWIND_HAS_DL_LIB=OFF \
    -DLIBUNWIND_IS_BAREMETAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_LINKER=lld && \
    apk del --no-cache \
        g++ \
        cmd:g++ && \
    ls -lap /bootstrap/llvmorg/build-libunwind/ && \
    cmake --build build-libunwind && \
    cmake --install build-libunwind && \
    rm -vfr /bootstrap/llvmorg/build-libunwind/

# check on the lib
#RUN printf "%s\n" "Bootstrapped Libs (dynamic):" && \
#    ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/generic/ || true ; \
#    printf "%s\n" "Bootstrapped Headers:" && \
#    ls -lapr ${SYSROOT}/usr/include/ || true

# bring in the staged files from static
COPY --from=build-unwind-static /stage-static /stage
# move the changed files out to stage

RUN for UNWIND_FILE_ARTIFACT in usr/lib/libunwind.so.1.0 ; do \
          cp -vn ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} /stage/${UNWIND_FILE_ARTIFACT} || true ; \
    done ; \
    if [ -f usr/lib/libunwind.so.1.0 ] ; then \
      if command -v llvm-strip >/dev/null 2>&1; then \
         llvm-strip --strip-unneeded /stage/usr/lib/libunwind.so.1.0 + || true; \
      else \
         strip --strip-unneeded /stage/usr/lib/libunwind.so.1.0 + || true; \
      fi ; \
      touch -d "${SOME_DATE_EPOCH}" /stage/usr/lib/libunwind.so.1.0 || true ; \
    fi

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        llvm \
        libc++ \
        libc++-dev \
        compiler-rt \
        llvm-runtimes \
        cmake \
        samurai \
        python3 ;

# --- build-libcxxrt: bootstrap libcxxrt using distro clang/llvm to compile a libcxxrt library ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-libcxxrt

WORKDIR /bootstrap

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=fetcher /fetch/libcxxrt /bootstrap/libcxxrt-project
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage

# Copy shims/unwind_shim.h into the image build context before building the image
COPY shims/unwind_shim.h /tmp/unwind_shim.h

# Copy Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# may need -Wl,--sysroot=/sysroot
# may want linker flag -Wl,--nostdlib to prevent linking to any std c++
ENV LDFLAGS="-v -fuse-ld=lld -Xlinker --sysroot=/sysroot -Xlinker -L -Xlinker /sysroot/usr/lib -Xlinker -L -Xlinker /sysroot/lib -Xlinker -L -Xlinker /sysroot/usr/lib/generic"
# Does NOT require -D__ELF__
ENV CFLAGS="--target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_BSD_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot ${SYSROOT:-/sysroot} -I${SYSROOT:-/sysroot}/usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-ffunction-sections -fdata-sections --unwindlib=/sysroot/usr/lib/libunwind.so.1.0"

# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYSROOT:-/sysroot}/lib/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYSROOT:-/sysroot}/lib/libunwind.so

# install minimal build tooling (musl-based; no libstdc++/glibc packages used)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    compiler-rt \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    cmd:clang-cpp \
    cmd:lld \
    cmd:llvm-ar \
    cmd:llvm-ranlib \
    cmd:llvm-objdump \
    cmd:llvm-readelf \
    file \
    cmd:find

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

RUN mkdir -p /bootstrap/libcxxrt && cd libcxxrt-project && \
  cmake -S . -B ../libcxxrt -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Generic-Musl \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_SYSROOT=${SYSROOT:-/sysroot} \
    -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_C_FLAGS="-std=c11 ${CFLAGS} -Qunused-arguments" \
    -DCMAKE_CXX_FLAGS="-std=c++11 ${CXXFLAGS} ${CFLAGS} -Qunused-arguments" \
    -DLIBCXXRT_ENABLE_EXCEPTIONS=ON \
    -DLIBCXXRT_ENABLE_THREADS=ON \
    -DLIBCXXRT_USE_COMPILER_RT=ON \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_LINKER=lld \
    -DCMAKE_LINKER_FLAGS="${CFLAGS} ${LDFLAGS} -Xlinker --exclude-libs=libgcc_s.so.1" && \
  cd /bootstrap && \
  cmake --build libcxxrt -- -j$(nproc) && \
  ls -l libcxxrt/lib && \
  apk del --no-cache \
    g++ \
    cmd:g++ ;\
  if [ -f libcxxrt/lib/libcxxrt.so ] ; then \
      if command -v llvm-strip >/dev/null 2>&1; then \
         llvm-strip --strip-unneeded libcxxrt/lib/libcxxrt.so || true; \
      else \
         strip --strip-unneeded libcxxrt/lib/libcxxrt.so || true; \
      fi ; \
      file "libcxxrt/lib/libcxxrt.so" 2>/dev/null || true;\
      { llvm-objdump -harp libcxxrt/lib/libcxxrt.so || true ;} 2>/dev/null | grep -iF "musl" ;\
      install -m 0644 libcxxrt/lib/libcxxrt.so "${SYSROOT:-/sysroot}/usr/lib/libcxxrt.so" ;\
      touch -d "${SOME_DATE_EPOCH}" "${SYSROOT:-/sysroot}/usr/lib/libcxxrt.so" || true ; \
  fi ;\
  if [ -r "libcxxrt/src/cxxabi.h" ] ; then \
    file "libcxxrt/src/cxxabi.h" 2>/dev/null || true;\
    { wc -l libcxxrt/src/cxxabi.h || true ;} 2>/dev/null;\
    mkdir -m 0755 -p "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi" ;\
    install -m 0644 "libcxxrt/src/unwind.h" "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-cxxabi.h" ;\
    install -m 0644 "/stage/usr/include/__libunwind_config.h" "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/__libunwind_config.h" ;\
    install -m 0644 "/stage/usr/include/unwind.h" "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-llvm.h" ;\
    install -m 0644 /tmp/unwind_shim.h "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind.h" ;\
    install -m 0644 "libcxxrt/src/unwind-arm.h "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-arm.h" ;\
    install -m 0644 "libcxxrt/src/unwind-itanium.h "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-itanium.h" ;\
    install -m 0644 libcxxrt/src/cxxabi.h "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/cxxabi.h" ;\
    touch -d "${SOME_DATE_EPOCH}" "${SYSROOT:-/sysroot}/usr/lib/libcxxrt.so" || true ; \
  fi ;

RUN ls -1 "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind.h" && \
    ls -1 "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-cxxabi.h" && \
    ls -1 "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/unwind-llvm.h" && \
    ls -1 "${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi/cxxabi.h" && \
    { llvm-objdump -harp ${SYSROOT:-/sysroot}/usr/lib/libcxxrt.so || true ;} 2>/dev/null | grep -iF "musl" || true ;

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        compiler-rt \
        cmd:clang++ \
        cmake \
        samurai \
        python3 ;

# --- Lib C++ headers ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS libcxxheaders

WORKDIR /bootstrap

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage
COPY --from=build-libcxxrt /sysroot /stage-cxxrt

# Copy custom Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Platforms/Generic-Musl-Libcxxrt.cmake /tmp/Generic-Musl-Libcxxrt.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# may need -Xlinker --sysroot=/sysroot
# may want linker flag -Xlinker --nostdlib to prevent linking to any std c++
ENV LDFLAGS="-v -Xlinker --sysroot=/sysroot -Xlinker -L -Xlinker /sysroot/usr/lib -Xlinker -L -Xlinker /sysroot/lib -Xlinker -L -Xlinker /sysroot/usr/lib/generic"
# Does NOT require -D__ELF__
ENV CFLAGS="--target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot ${SYSROOT:-/sysroot} -iwithsysroot /usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-iwithsysroot /usr/include/c++/v1 -ffunction-sections -fdata-sections --unwindlib=/sysroot/usr/lib/libunwind.so.1.0"

# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYSROOT:-/sysroot}/lib/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYSROOT:-/sysroot}/lib/libunwind.so

# overlay the libcxxrt
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi && \
    for CXXRT_FILE_ARTIFACT in usr/include/c++/v1/cxxabi/cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind-llvm.h \
        usr/include/c++/v1/cxxabi/unwind-cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind-arm.h \
        usr/include/c++/v1/cxxabi/unwind-itanium.h \
        usr/include/c++/v1/cxxabi/unwind.h \
        usr/lib/libcxxrt.so ; do \
          cp -vf /stage-cxxrt/${CXXRT_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
    done ;

# install minimal build tooling (musl-based; no libstdc++/glibc packages used)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm-libs \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    cmd:clang-cpp \
    cmd:lld \
    cmd:llvm-ar \
    cmd:llvm-ranlib \
    file \
    cmd:find

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl-Libcxxrt.cmake /usr/share/cmake/Modules/Platform/Generic-Musl-Libcxxrt.cmake \
 && rm /tmp/Generic-Musl-Libcxxrt.cmake \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

# mock the sysroot for headers
RUN mkdir -pv /headers && \
    mkdir -pv /headers/dev && \
    mkdir -pv /headers/proc && \
    mkdir -pv /headers/run && \
    mkdir -pv /headers/sys && \
    mkdir -pv /headers/share && \
    mkdir -pv /headers/man && \
    mkdir -pv /headers/tmp && \
    mkdir -pv /headers/etc && \
    mkdir -pv /headers/usr/include && \
    for MUSL_SDK_FILE_ARTIFACT in bin sbin lib libexec \
        usr/bin usr/sbin usr/lib usr/libexec \
        usr/share usr/man \
        usr/include/arpa \
        usr/include/bits \
        usr/include/generic \
        usr/include/mach-o \
        usr/include/net \
        usr/include/netinet \
        usr/include/netpacket \
        usr/include/scsi \
        usr/include/sys ; do \
          if [ -d ${SYSROOT}/${MUSL_SDK_FILE_ARTIFACT} ] ; then \
            ln -svf ${SYSROOT}/${MUSL_SDK_FILE_ARTIFACT} /headers/${MUSL_SDK_FILE_ARTIFACT} || true ; \
            touch -d "${SOME_DATE_EPOCH}" /headers/${MUSL_SDK_FILE_ARTIFACT} || true ; \
          fi ; \
    done ;\
    find ${SYSROOT:-/sysroot}/usr/include -maxdepth 1 -type f -iname "*.h" -exec sh -c 'for f; do ln -svf "$f" /headers/usr/include/$(basename "$f"); done' _ {} + || true;

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

WORKDIR /bootstrap/llvmorg

# may want unused -DLIBCXX_HAS_GCC_LIB=NO
# may want unused -DLIBCXX_HAS_GCC_S_LIB=NO
# Should keep unused '-DLLVM_ENABLE_RUNTIMES= ' to ensure headers focused build

# Configure/install libc++ headers only into a "headers" sysroot
# -> install prefix is /headers/usr so final headers appear under /headers/usr/include
RUN mkdir -p build-libcxx-config && \
    cd build-libcxx-config; \
    cmake -G Ninja ../libcxx -Wno-dev \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_INSTALL_PREFIX=/headers/usr \
      -DLIBCXX_INSTALL_INCLUDE_TARGET_DIR=include/c++/v1 \
      -DLIBCXX_INSTALL_HEADERS=ON \
      -DLIBCXX_ENABLE_SHARED=OFF \
      -DLIBCXX_ENABLE_STATIC=OFF \
      -DLIBCXX_CXX_ABI=none \
      -DLIBCXX_ABI_VERSION=1 \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBCXX_ENABLE_THREADS=ON \
      -DLIBCXX_HAS_PTHREAD_API=ON \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXX_HARDENING_MODE=extensive \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CFLAGS} ${CXXFLAGS} -Qunused-arguments" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=lld \
      -DLLVM_ENABLE_RUNTIMES= \
      -DLIBCXX_INCLUDE_TESTS=OFF \
    ;\
    cmake --build . || true ;\
    python3 ../libcxx/utils/generate_iwyu_mapping.py -o include/c++/v1/libcxx.imp || true ;\
    cmake --install . || true ;

WORKDIR /bootstrap/llvmorg

ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot /headers -iwithsysroot /usr/include/c++/v1 -iwithsysroot /usr/include"
ENV CXXFLAGS="--unwindlib=/sysroot/usr/lib/libunwind.so.1.0 -cxx-isystem /headers/usr/include/c++/v1"

# Install libcxxabi headers too (ABI types required by libc++ headers)
RUN mkdir -p build-libcxxabi-config && \
    cd build-libcxxabi-config && \
    cmake -G Ninja \
      ../libcxxabi \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_INSTALL_PREFIX=/headers/usr \
      -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
      -DLIBCXXABI_INSTALL_HEADERS=ON \
      -DLIBCXXABI_ENABLE_SHARED=OFF \
      -DLIBCXXABI_ENABLE_STATIC=ON \
      -DLIBCXXABI_INSTALL_INCLUDE_TARGET_DIR=include/c++/v1 \
      -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
      -DLIBCXXABI_LIBUNWIND_INCLUDES=${SYSROOT:-/sysroot}/usr/include \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_THREADS=ON \
      -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
      -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=FALSE \
      -DLIBCXXABI_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXXABI_HAS_GCC_S_LIB=NO \
      -DLIBCXXABI_LIBCXX_PATH="/bootstrap/llvmorg/libcxx" \
      -DLIBCXXABI_LIBCXX_LIBRARY_PATH=/bootstrap/llvmorg/build-libcxx-config/lib \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS} ${CFLAGS} -Qunused-arguments" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=lld \
      -DLLVM_ENABLE_RUNTIMES= \
      -DLIBCXXABI_INCLUDE_TESTS=OFF \
    ;\
    cmake --build . || true ;\
    cmake --install . || true ;\
    [ -d /headers/usr/include/c++/v1 ] && \
    [ -f /headers/usr/include/c++/v1/__config ] && \
    [ -f /headers/usr/include/c++/v1/__cxxabi_config.h ] && \
    [ -f /headers/usr/include/c++/v1/cxxabi.h ] || \
    printf "\n%s\n\n" "Warning: missing expected C++ headers" ;

# Quick, trivial compile-time test that the headers are usable:
# compile-only (no linking) a small C++ snippet using the installed headers.
RUN set -eux; \
    printf "%s\n" "Test Headers:" && \
    printf '%s\n' '#include <vector>' '#include <string>' 'int main() {' '  std::vector<std::string> v;' '  v.push_back("ok");' '  return (int)v.size();' '}' > /tmp/test.cpp; \
    clang++ -v -fsyntax-only -std=c++17 -isystem /headers/usr/include /tmp/test.cpp ;

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        g++ \
        cmd:g++ \
        cmake \
        samurai \
        python3 && \
    rm -rf /bootstrap/build-libcxx-config /bootstrap/build-libcxxabi-config /tmp/test.cpp && \
    find /headers/usr/include -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true ;

# unlink mocking of /sysroot in /headers
RUN for MUSL_SDK_FILE_ARTIFACT in bin sbin lib libexec \
        usr/bin usr/sbin usr/lib usr/libexec \
        usr/share usr/man \
        usr/include/arpa \
        usr/include/bits \
        usr/include/generic \
        usr/include/mach-o \
        usr/include/net \
        usr/include/netinet \
        usr/include/netpacket \
        usr/include/scsi \
        usr/include/sys ; do \
          if [ -L ${SYSROOT}/${MUSL_SDK_FILE_ARTIFACT} ] ; then \
            rm -vf -- /headers/${MUSL_SDK_FILE_ARTIFACT} || true ; \
          fi ; \
    done ; \
    find /headers/usr/include -maxdepth 1 -type l -iname "*.h" -exec rm -vf -- {} + || true;

# The resulting "headers" sysroot:
# /headers/usr/include    <-- contains libc++ and libcxxabi headers and generated config headers
# Keep them in this stage so a later stage can COPY --from=libcxxheaders /headers /headers

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l -r /headers/usr/include || true && \
    find /headers/usr/include -type f -exec file {} + || true;

# --- MARK 1 of 3 for round-trip bootstrap build of libcxxabi.so
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-libcxx-bs

WORKDIR /work

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /work/llvm-project
COPY --from=sysroot /sysroot /sysroot
COPY --from=fetcher /fetch/libcxxrt/src /sysroot/usr/include/c++/v1/cxxabi
COPY --from=build-unwind /stage /stage
COPY --from=build-libcxxrt /sysroot /stage-cxxrt

# Copy dummy cxx-headers shim into image
COPY shims/cxx-headers.c /work/cxx-headers.c

# Copy custom Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Platforms/Generic-Musl-Libcxxrt.cmake /tmp/Generic-Musl-Libcxxrt.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

# Copy helper scripts and sources into the image
# (Ensure these files exist next to the Dockerfile when building)
COPY payloads/bin/run_cmake_build.sh /work/run_cmake_build.sh
COPY payloads/bin/run_post_build_strip.sh /work/run_post_build_strip.sh
COPY payloads/bin/run_dir_check.sh /work/run_dir_check.sh
COPY shims/bootstrap_cxa_stubs.cpp /work/bootstrap_cxa_stubs.cpp
COPY shims/__stack_chk_fail_local.c /work/__stack_chk_fail_local.c
COPY payloads/tests/test_exception.cpp /work/test_exception.cpp

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

# musl libc checks TZ
# shellcheck disable=SC2154
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT=/sysroot
ENV MUSL_PREFIX="/usr"
ENV SYS_LIB=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib
ENV SYS_INCLUDE=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/include


# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYS_LIB}/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYS_LIB}/libunwind.so

# overlay the libcxxrt
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi && \
    for CXXRT_FILE_ARTIFACT in usr/include/c++/v1/cxxabi/cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind-llvm.h \
        usr/include/c++/v1/cxxabi/unwind-cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind.h \
        usr/lib/libcxxrt.so ; do \
          cp -vf /stage-cxxrt/${CXXRT_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
    done ;

# install minimal build tooling (musl-based; no libstdc++/glibc packages used)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm-libs \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    cmd:clang-cpp \
    cmd:lld \
    cmd:llvm-ar \
    cmd:llvm-ranlib \
    cmd:llvm-strip \
    cmd:llvm-readelf \
    cmd:llvm-objdump \
    file \
    cmd:find

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && install -m 0644 /tmp/Generic-Musl-Libcxxrt.cmake /usr/share/cmake/Modules/Platform/Generic-Musl-Libcxxrt.cmake \
 && rm /tmp/Generic-Musl-Libcxxrt.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

RUN chmod +x /work/run_cmake_build.sh && chmod +x /work/run_dir_check.sh

# Create helper dirs
RUN mkdir -p /work/builds/opt/libcxx-bootstrap1 /work/builds/opt/libcxxabi-final /work/builds/opt/libcxx-final /work/builds && \
    cp -pfr ${SYSROOT:-/sysroot}/ /work/builds/opt/libcxx-bootstrap0 && \
    cp -pfr ${SYSROOT:-/sysroot}/ /work/builds/opt/libcxxabi-bootstrap0 && \
    /work/run_dir_check.sh /work/builds/opt/libcxx-bootstrap0/usr 5 && \
    /work/run_dir_check.sh /work/builds/opt/libcxxabi-bootstrap0/usr 5 ;

ENV HOST_CC=${CC}
ENV HOST_CXX=clang++
ENV HOST_LD=lld

# may need -Xlinker --sysroot=/sysroot
# may want linker flag -Xlinker --nostdlib to prevent linking to any std c++
# may want to link -Xlinker -l${LLVM_RTLIB_STUB}
ENV LDFLAGS="-fuse-ld=lld -v -Xlinker --trace-symbol=_Unwind_Resume -Xlinker --sysroot=${SYSROOT:-/sysroot} -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker -L -Xlinker ${SYSROOT:-/sysroot}/lib -Xlinker -L -Xlinker ${SYS_LIB}/generic -Xlinker -l${LLVM_RTLIB_STUB} -Xlinker --exclude-libs=libgcc_s.so.1 -Xlinker --exclude-libs=libgcc_s.so -Xlinker --dynamic-linker=${SYSROOT:-/sysroot}/lib/${MUSL_LDLIB}"
# Does NOT require -D__ELF__
ENV CFLAGS="--no-default-config --target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT:-/sysroot}/usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-ffunction-sections -fdata-sections --unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

# force the correct libunwinder
ENV CXX_UNWINDER_FLAGS="--unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

RUN "${HOST_CC}" $CFLAGS -fuse-ld=lld $LDFLAGS -O2 -Qunused-arguments -x c -c /work/__stack_chk_fail_local.c -o /work/__stack_chk_fail_local.o && \
    llvm-ar --format=bsd rcs ${SYSROOT:-/sysroot}/usr/lib/generic/libssp_nonshared.a /work/__stack_chk_fail_local.o && \
    ln -svf generic/libssp_nonshared.a ${SYSROOT:-/sysroot}/usr/lib/libssp_nonshared.a

RUN "${HOST_CXX}" $CXXFLAGS $CFLAGS -fuse-ld=lld -Xlinker -Bdynamic -Xlinker --relocatable $LDFLAGS -Qunused-arguments -x c++ -fno-rtti -fno-exceptions -c /work/bootstrap_cxa_stubs.cpp -o /work/bootstrap_cxa_stubs.o && \
    llvm-ar --format=bsd rcs /work/libbootstrap_cxa.a /work/bootstrap_cxa_stubs.o

# may want to play with LIBCXX_TARGET_SUBDIR

# Stage 1: Build libc++ (bootstrap0) but link against existing libcxxabi (libcxxrt) in sysroot
RUN mkdir -p /work/build-libcxx-bootstrap0 && cd /work/build-libcxx-bootstrap0 && \
    /work/run_cmake_build.sh /work/llvm-project/libcxx /work/build-libcxx-bootstrap0 \
      -G Ninja \
      -DCMAKE_C_COMPILER=${HOST_CC} \
      -DCMAKE_CXX_COMPILER=${HOST_CXX} \
      -DCMAKE_LINKER=${HOST_LD} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Generic-Musl-Libcxxrt \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${HOST_TRIPLE} \
      -DCMAKE_SYSROOT=${SYSROOT:-/sysroot} \
      -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
      -DCMAKE_INSTALL_PREFIX=/work/builds/opt/libcxx-bootstrap0 \
      -DLIBCXX_ENABLE_SHARED=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_ENABLE_EXCEPTIONS=ON \
      -DLIBCXX_ENABLE_RTTI=ON \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBCXX_ENABLE_THREADS=ON \
      -DLIBCXX_HAS_PTHREAD_API=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=NO \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXX_HARDENING_MODE=extensive \
      -DLIBCXX_ABI_VERSION=1 \
      -DLIBCXX_CXX_ABI=libcxxrt \
      -DLIBCXX_CXX_ABI_LIBRARY_PATH=${SYS_LIB} \
      -DLIBCXX_CXX_ABI_INCLUDE_PATHS="${SYS_INCLUDE}/c++/v1/cxxabi" \
      -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
      -DLIBCXX_ENABLE_NEW_DELETE_DEFINITIONS=ON \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS} ${CFLAGS} -Qunused-arguments" \
      -DLIBCXX_LINK_FLAGS="${CXX_UNWINDER_FLAGS} -v ${LDFLAGS} -Xlinker --verbose" \
      -DCMAKE_EXE_LINKER_FLAGS="${CXX_UNWINDER_FLAGS} -Xlinker -Bdynamic -Xlinker --whole-archive -Xlinker /work/libbootstrap_cxa.a -Xlinker --no-whole-archive -Xlinker --rpath=/work/builds/opt/libcxx-bootstrap0/lib -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker --rpath-link=${SYS_LIB}" \
      -DCMAKE_INSTALL_RPATH=/work/builds/opt/libcxx-bootstrap0/lib \
      -DLLVM_ENABLE_RUNTIMES= \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DLIBCXX_INCLUDE_TESTS=OFF && \
    python3 ../llvm-project/libcxx/utils/generate_iwyu_mapping.py -o include/c++/v1/libcxx.imp || true ;\
    cmake --install /work/build-libcxx-bootstrap0 ;

# WORKAROUND https://github.com/llvm/llvm-project/issues/116088
RUN "${CC}" $CXXFLAGS $CFLAGS -Qunused-arguments -fuse-ld=lld -Qunused-arguments -Xlinker --dynamic-linker=${SYSROOT:-/sysroot}/lib/${MUSL_LDLIB:-ld-musl-generic.so} -c /work/cxx-headers.c -o /work/cxx-headers.o && \
    "${CC}" $CFLAGS $CXX_UNWINDER_FLAGS -Qunused-arguments -shared -Xlinker --shared /work/cxx-headers.o -o /work/libcxx-headers.so \
      -fuse-ld=lld -Xlinker --hash-style=both -Xlinker --dynamic-linker=${SYSROOT:-/sysroot}/lib/${MUSL_LDLIB:-ld-musl-generic.so} \
      -Xlinker --nostdlib -Xlinker -Bdynamic -Xlinker --sysroot=${SYSROOT:-/sysroot} -Xlinker -L -Xlinker ${SYSROOT:-/sysroot}/lib -Xlinker --soname=libcxx-headers.so \
      -Xlinker --auxiliary=libc++.so \
      -Xlinker --auxiliary=libcxxrt.so \
      -Xlinker --auxiliary=libc.so \
      -Xlinker --no-gnu-unique -Xlinker --unique \
      -Xlinker --Bno-symbolic \
      -Xlinker --rpath=${SYSROOT:-/sysroot}/usr/lib \
      -Xlinker -z -Xlinker relro -Xlinker -z -Xlinker now && \
    if command -v llvm-strip >/dev/null 2>&1; then \
         llvm-strip --strip-unneeded /work/libcxx-headers.so || true; \
      else \
         strip --strip-unneeded /work/libcxx-headers.so || true; \
      fi ; \
    install -m 0755 /work/libcxx-headers.so ${SYSROOT:-/sysroot}/usr/lib/libcxx-headers.so && \
    file ${SYSROOT:-/sysroot}/usr/lib/libcxx-headers.so && \
    llvm-objdump -harp ${SYSROOT:-/sysroot}/usr/lib/libcxx-headers.so | grep -iFe "AUXILIARY" ;

# Stage 2: Build libc++abi against libc++ bootstrap0 (abi-bootstrap0)
# If you still want to build libc++abi in-stage using bootstrap libc++, point to both the sysroot (for libunwind) and the bootstrap libc++ install.
RUN mkdir -p /work/build-libcxxabi-bootstrap0 && cd /work/build-libcxxabi-bootstrap0 && \
    /work/run_cmake_build.sh /work/llvm-project/libcxxabi /work/build-libcxxabi-bootstrap0 \
      -G Ninja \
      -DCMAKE_C_COMPILER=${HOST_CC} \
      -DCMAKE_CXX_COMPILER=${HOST_CXX} \
      -DCMAKE_LINKER=${HOST_LD} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${HOST_TRIPLE} \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_SYSROOT=${SYSROOT:-/sysroot} \
      -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
      -DCMAKE_INSTALL_PREFIX=/work/builds/opt/libcxxabi-bootstrap0 \
      -DCMAKE_INSTALL_RPATH=/work/builds/opt/libcxxabi-bootstrap0/lib \
      -DLIBCXXABI_LIBCXX_PATH=/work/build-libcxx-bootstrap0 \
      -DLIBCXXABI_LIBCXX_LIBRARY_PATH=/work/builds/opt/libcxx-bootstrap0/lib \
      -DLIBCXXABI_ENABLE_SHARED=ON \
      -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
      -DLIBCXXABI_LIBUNWIND_INCLUDES=/stage/usr/include \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_THREADS=ON \
      -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
      -DLIBCXXABI_HAS_C_LIB=ON \
      -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=FALSE \
      -DLIBCXXABI_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXXABI_HAS_GCC_S_LIB=NO \
      -DCMAKE_PREFIX_PATH=/work/builds/opt/libcxx-bootstrap0 \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS} -I/work/builds/opt/libcxx-bootstrap0/include/c++/v1 -I/work/builds/opt/libcxx-bootstrap0/include/c++/v1 -I/work/llvm-project/libcxx/src -I/work/builds/opt/libcxx-bootstrap0/include ${CFLAGS} -Qunused-arguments -I/work/builds/opt/libcxx-bootstrap0/include -isystem ${SYS_INCLUDE} -fuse-ld=lld" \
      -DCMAKE_LINK_FLAGS="-rtlib=compiler-rt $CXX_UNWINDER_FLAGS -fno-math-errno -fPIC -fuse-ld=lld -v -Xlinker --why-live=_Unwind_Resume -Xlinker --nostdlib ${LDFLAGS} -Xlinker -L -Xlinker /work/builds/opt/libcxx-bootstrap0/lib -Xlinker --verbose -Xlinker --rpath=/work/builds/opt/libcxx-bootstrap0/lib:${SYSROOT:-/sysroot}/usr/lib:/work/builds/opt/libcxx-bootstrap0/lib" \
      -DCMAKE_EXE_LINKER_FLAGS="-Xlinker -L -Xlinker /work/builds/opt/libcxx-bootstrap0/lib -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker --rpath=/work/builds/opt/libcxxabi-bootstrap0/lib:/work/builds/opt/libcxx-bootstrap0/lib:${SYS_LIB}" \
      -DLLVM_ENABLE_RUNTIMES= \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
      -DLIBCXXABI_INCLUDE_TESTS=OFF && \
    cmake --install /work/build-libcxxabi-bootstrap0

WORKDIR /work

# cleanup and reset the llvm project source for next stage
RUN mkdir -p -m 755 /bootstrap-stage && \
    { rm -vfr /work/llvm-project || true ;} && \
    rm -vfr /work/build-libcxxabi-bootstrap0 && \
    rm -vfr /work/build-libcxx-bootstrap0 && \
    { rm -vf /work/libbootstrap_cxa.{a,o,c,cpp} || true ;} && \
    { rm -vf /work/libssp_nonshared.{a,o,c} || true ;} && \
    chmod +x /work/run_post_build_strip.sh && \
    ls -lp /work/ ;

# DEBUG missing stuff
RUN ls -lap /work/builds/opt/libcxx-bootstrap0/lib && \
    for SOME_LIB_NAME in "libc++" "libc++experimental" "libc++abi" ; do \
      for SOME_SUFFIX in ".so" ".so.1" ".so.1.0" ; do \
        if [ -f "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" ] ; then \
          if command -v llvm-strip >/dev/null 2>&1; then \
             llvm-strip --strip-unneeded "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          else \
             strip --strip-unneeded "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          fi ; \
          llvm-objdump -hd "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" ;\
        fi ; \
        if [ -f "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" ] ; then \
          if command -v llvm-strip >/dev/null 2>&1; then \
             llvm-strip --strip-unneeded "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          else \
             strip --strip-unneeded "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          fi ; \
          llvm-objdump -hd "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" ;\
        fi ; \
      done ;\
      for SOME_SUFFIX_R2 in ".a" ".so" ".so.1" ".so.1.0" ; do \
        if [ -f "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ] ; then \
          install -m 755 "/work/builds/opt/libcxx-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ;\
          /work/run_post_build_strip.sh "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ;\
          file "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" || true; \
        fi ; \
        if [ -f "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ] ; then \
          install -m 755 "/work/builds/opt/libcxxabi-bootstrap0/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ;\
          /work/run_post_build_strip.sh "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ;\
          file "${SYSROOT:-/sysroot}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" || true; \
        fi ; \
      done ;\
    done ;

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        g++ \
        cmd:g++ \
        cmake \
        samurai \
        python3

# --- MARK 2 of 3 for round-trip bootstrap build of libcxxabi.so
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-libcxx-stage0

WORKDIR /work

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /work/llvm-project
COPY --from=sysroot /sysroot /sysroot
# should not need this now
# COPY --from=fetcher /fetch/libcxxrt/src /sysroot/usr/include/c++/v1/cxxabi
COPY --from=build-unwind /stage /stage
COPY --from=build-libcxxrt /sysroot /stage-cxxrt
COPY --from=libcxxheaders /headers/usr/include/c++ /sysroot/usr/include/c++
COPY --from=build-libcxx-bs /sysroot /stage-bootstrap

# skip dummy cxx-headers shim into image
# COPY shims/cxx-headers.c /work/cxx-headers.c

# Copy custom Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

# Copy helper scripts and sources into the image
# (Ensure these files exist next to the Dockerfile when building)
COPY payloads/bin/run_cmake_build.sh /work/run_cmake_build.sh
COPY payloads/bin/run_post_build_strip.sh /work/run_post_build_strip.sh
COPY payloads/bin/run_dir_check.sh /work/run_dir_check.sh
COPY payloads/tests/test_exception.cpp /work/test_exception.cpp

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

# musl libc checks TZ
# shellcheck disable=SC2154
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT=/sysroot
ENV MUSL_PREFIX="/usr"
ENV SYS_LIB=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib
ENV SYS_INCLUDE=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/include


# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYS_LIB}/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYS_LIB}/libunwind.so

# overlay the libcxxrt
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi && \
    for CXXRT_FILE_ARTIFACT in usr/include/c++/v1/cxxabi/cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind-llvm.h \
        usr/include/c++/v1/cxxabi/unwind-cxxabi.h \
        usr/include/c++/v1/cxxabi/unwind.h \
        usr/lib/libcxxrt.so ; do \
          cp -vf /stage-cxxrt/${CXXRT_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
    done ;

# overlay the bootstrapped libcxx and abi
# skipping libssp_nonshared.a as unneeded now (hopefully)
RUN  touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/usr/lib && \
    for CXXSTD_FILE_ARTIFACT in usr/lib/libc++.a \
        usr/lib/libc++.so \
        usr/lib/libc++abi.so \
        usr/lib/libc++experimental.a ; do \
          if [ -f /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ] ; then \
            cp -vf /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
            touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
          fi ;\
    done ;

# install minimal build tooling (musl-based; no libstdc++/glibc packages used)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm-libs \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    cmd:clang-cpp \
    cmd:lld \
    cmd:llvm-ar \
    cmd:llvm-ranlib \
    cmd:llvm-strip \
    cmd:llvm-readelf \
    cmd:llvm-objdump \
    file \
    cmd:find

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

RUN chmod +x /work/run_cmake_build.sh && \
    chmod +x /work/run_dir_check.sh && \
    chmod +x /work/run_post_build_strip.sh ;

# Create helper dirs
RUN mkdir -p /work/builds/opt/libcxx-final /work/builds && \
    cp -pfr ${SYSROOT:-/sysroot}/ /work/builds/opt/libcxx-bootstrap1 && \
    cp -pfr ${SYSROOT:-/sysroot}/ /work/builds/opt/libcxxabi-final && \
    /work/run_dir_check.sh /work/builds/opt/libcxx-bootstrap1/usr 5 && \
    /work/run_dir_check.sh /work/builds/opt/libcxxabi-final/usr 5 ;

ENV HOST_CC=${CC}
ENV HOST_CXX=clang++
ENV HOST_LD=lld

# may need -Xlinker --sysroot=/sysroot
# may want linker flag -Xlinker --nostdlib to prevent linking to any std c++
# may want to link -Xlinker -l${LLVM_RTLIB_STUB}
ENV LDFLAGS="-fuse-ld=lld -v -Xlinker --trace-symbol=_Unwind_Resume -Xlinker --sysroot=${SYSROOT:-/sysroot} -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker -L -Xlinker ${SYSROOT:-/sysroot}/lib -Xlinker -L -Xlinker ${SYS_LIB}/generic -Xlinker -l${LLVM_RTLIB_STUB} -Xlinker --exclude-libs=libgcc_s.so.1 -Xlinker --exclude-libs=libgcc_s.so -Xlinker --dynamic-linker=${SYSROOT:-/sysroot}/lib/${MUSL_LDLIB}"
# Does NOT require -D__ELF__
ENV CFLAGS="--no-default-config --target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT:-/sysroot}/usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-ffunction-sections -fdata-sections --unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

# force the correct libunwinder
ENV CXX_UNWINDER_FLAGS="--unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

# stage 3 changes from stage 1
# use new staging path
# swap the linker script logic to OFF
# swap to abi NEW/DELETE DEFINITIONS and thus disable LIBCXX_ENABLE_NEW_DELETE_DEFINITIONS
# use ABI=libcxxabi (from stage 2)

# Stage 3: Rebuild libc++ linking against libcxxabi-bootstrap0 (round-trip libc++ bootstrap1)
RUN mkdir -p /work/build-libcxx-bootstrap1 && cd /work/build-libcxx-bootstrap1 && \
    /work/run_cmake_build.sh /work/llvm-project/runtimes /work/build-libcxx-bootstrap1 \
      -G Ninja \
      -DCMAKE_C_COMPILER=${HOST_CC} \
      -DCMAKE_CXX_COMPILER=${HOST_CXX} \
      -DCMAKE_LINKER=${HOST_LD} \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DLLVM_RUNTIMES_TARGET=${TARGET_TRIPLE} \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
      -DCMAKE_SYSROOT=${SYSROOT:-/sysroot} \
      -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
      -DCMAKE_INSTALL_PREFIX=/work/builds/opt/libcxx-bootstrap1 \
      -DLIBCXX_ENABLE_SHARED=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_ENABLE_EXCEPTIONS=ON \
      -DLIBCXX_ENABLE_RTTI=ON \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBCXX_ENABLE_THREADS=ON \
      -DLIBCXX_HAS_PTHREAD_API=ON \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXX_HARDENING_MODE=extensive \
      -DLIBCXX_ABI_VERSION=1 \
      -DLIBCXX_CXX_ABI=libcxxabi \
      -DLIBCXX_CXX_ABI_LIBRARY_PATH=${SYS_LIB} \
      -DLIBCXX_CXX_ABI_INCLUDE_PATHS="${SYS_INCLUDE}/c++/v1" \
      -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
      -DLIBCXX_ENABLE_NEW_DELETE_DEFINITIONS=OFF \
      -DLIBCXXABI_USE_LLVM_UNWINDER=NO \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_SHARED=ON \
      -DLIBCXXABI_ENABLE_STATIC=OFF \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
      -DLIBCXXABI_LIBUNWIND_INCLUDES=/stage/usr/include \
      -DLIBCXXABI_ENABLE_THREADS=ON \
      -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
      -DLIBCXXABI_HAS_C_LIB=ON \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS} ${CFLAGS} -Qunused-arguments" \
      -DLIBCXX_LINK_FLAGS="${CXX_UNWINDER_FLAGS} -v ${LDFLAGS} -Xlinker --verbose" \
      -DCMAKE_EXE_LINKER_FLAGS="${CXX_UNWINDER_FLAGS} -Xlinker -Bdynamic -Xlinker -L -Xlinker /work/builds/opt/libcxx-bootstrap1/lib -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker --rpath=/work/builds/opt/libcxx-bootstrap1/lib -Xlinker --rpath-link=${SYS_LIB}" \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER && \
    { find /work/build-libcxx-bootstrap1 -type f -iname "*.so" -exec file {} + || true ;} && \
    cmake --install /work/build-libcxx-bootstrap1 && \
    { find /work/build-libcxx-bootstrap1 -type f -iname "*.so" -exec file {} + || true ;} ;

# see https://libcxx.llvm.org/Modules.html for /stage0-modules/share/libc++/v1/
RUN ls -lap /work/builds/opt/libcxx-bootstrap1/lib ;\
    mkdir -m 755 -p /stage0-modules/usr/share/libc++/ && \
    mkdir -m 755 -p /stage0-modules/usr/lib/ && \
    mkdir -m 755 -p /stage0-cxx/usr/include/c++/ && \
    cp -pfr /work/builds/opt/libcxx-bootstrap1/include/c++/v1 /stage0-cxx/usr/include/c++/v1 && \
    cp -vpfr /work/builds/opt/libcxx-bootstrap1/usr/lib /stage0-cxx/usr/lib && \
    cp -pfr /work/builds/opt/libcxx-bootstrap1/share/libc++/v1 /stage0-modules/usr/share/libc++/v1 && \
    /work/run_dir_check.sh /stage0-cxx/usr/lib 4 && \
    /work/run_dir_check.sh /stage0-modules/usr/share/libc++/v1 3 && \
    /work/run_dir_check.sh /stage0-cxx/usr/include/c++/v1 10 && \
    { find /stage0-modules/usr/share/ -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true ;} && \
    { find /stage0-cxx/usr/include/ -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true ;} && \
    mv -vf /stage0-cxx/usr/lib/libc++.modules.json /stage0-modules/usr/lib/libc++.modules.json && \
    /work/run_dir_check.sh /stage0-modules/usr/lib 1 ;\
    for SOME_LIB_NAME in "libc++" "libc++experimental" "libc++abi" ; do \
      for SOME_SUFFIX in ".so" ".so.1" ".so.1.0" ; do \
        if [ -f "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" ] ; then \
          if command -v llvm-strip >/dev/null 2>&1; then \
             llvm-strip --strip-unneeded "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          else \
             strip --strip-unneeded "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
          fi ; \
          /work/run_post_build_strip.sh "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX:-}" || true; \
        fi ; \
      done ;\
      for SOME_SUFFIX_R2 in ".a" ".so" ".so.1" ".so.1.0" ; do \
        if [ -f "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ] ; then \
          file "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" || true; \
          rm -f "/${SYSROOT}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" && \
          install -m 755 "/stage0-cxx/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" "/${SYSROOT}/usr/lib/${SOME_LIB_NAME}${SOME_SUFFIX_R2:-}" ;\
        fi ; \
      done ;\
    done ;

# Build test program and link against final libs
RUN ${HOST_CXX} -std=c++17 -stdlib=libc++ -nostdinc -nostdinc++ \
    --sysroot=${SYSROOT:-/sysroot} \
    -cxx-isystem /usr/include/c++/v1 \
    -isystem /usr/include -I${SYSROOT:-/sysroot}/usr/include/c++/v1 -I${SYSROOT:-/sysroot}/usr/include \
    -unwindlib=libunwind ${CFLAGS} \
    -x c++ /work/test_exception.cpp -o /work/test_exception \
    -fuse-ld=lld -L/work/builds/opt/libcxx-bootstrap1/lib -lunwind -lc++ -lc++abi \
    -Xlinker --sysroot=${SYSROOT} -Xlinker --rpath="/work/builds/opt/libcxx-bootstrap1/lib:${SYS_LIB}" ;

# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache \
        g++ \
        cmd:g++ \
        cmake \
        samurai \
        python3

# --- MARK 3 of 3 for round-trip bootstrap build of libcxxabi.so
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-libcxx

WORKDIR /work

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /work/llvm-project
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage
COPY --from=build-libcxx-stage0 /stage0-cxx /stage0-cxx
COPY --from=build-libcxx-stage0 /stage0-modules /stage0-cxx-modules
COPY --from=libcxxheaders /headers/usr/include/c++ /sysroot/usr/include/c++

# Copy custom Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

# Copy helper scripts and sources into the image
# (Ensure these files exist next to the Dockerfile when building)
COPY payloads/bin/run_cmake_build.sh /work/run_cmake_build.sh
COPY payloads/bin/run_post_build_strip.sh /work/run_post_build_strip.sh
COPY payloads/bin/run_dir_check.sh /work/run_dir_check.sh
COPY payloads/tests/test_exception.cpp /work/test_exception.cpp

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

# musl libc checks TZ
# shellcheck disable=SC2154
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV SYSROOT=/sysroot
ENV MUSL_PREFIX="/usr"
ENV SYS_LIB=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib
ENV SYS_INCLUDE=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/include


# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYS_LIB}/libunwind.so.1 && \
    ln -fns libunwind.so.1.0 ${SYS_LIB}/libunwind.so

# overlay the libcxxrt (should no-longer be needed in step 4)
#RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/c++/v1/cxxabi && \
#    for CXXRT_FILE_ARTIFACT in usr/include/c++/v1/cxxabi/cxxabi.h \
#        usr/include/c++/v1/cxxabi/unwind-llvm.h \
#        usr/include/c++/v1/cxxabi/unwind-cxxabi.h \
#        usr/include/c++/v1/cxxabi/unwind.h \
#        usr/lib/libcxxrt.so ; do \
#          cp -vf /stage-cxxrt/${CXXRT_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
#          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXRT_FILE_ARTIFACT} || true ; \
#    done ;

# overlay the bootstrapped libcxx and abi
# (no longer needs libssp_nonshared.a in step 4)
RUN  touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/usr/lib && \
    for CXXSTD_FILE_ARTIFACT in usr/lib/libc++.a \
        usr/lib/libc++.so \
        usr/lib/libc++abi.so \
        usr/lib/libc++experimental.a ; do \
          if [ -f /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ] ; then \
            install -m 755 /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
            touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
          fi ;\
    done ;\
    rm -fr ${SYSROOT:-/sysroot}/usr/include/c++/v1/ || true ;\
    cp -rf /stage0-cxx/usr/include/c++/v1 ${SYSROOT:-/sysroot}/usr/include/c++/v1

# install minimal build tooling (musl-based; no libstdc++/glibc packages used)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm-libs \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    cmd:clang-cpp \
    cmd:lld \
    cmd:llvm-ar \
    cmd:llvm-ranlib \
    cmd:llvm-strip \
    cmd:llvm-readelf \
    cmd:llvm-objdump \
    file \
    cmd:find

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

RUN chmod +x /work/run_cmake_build.sh && chmod +x /work/run_dir_check.sh ;

# Create helper dirs
RUN mkdir -p /work/builds/opt/ && \
    cp -pfr ${SYSROOT:-/sysroot} /work/builds/opt/libcxx-final && \
    /work/run_dir_check.sh /work/builds/opt/libcxx-final/usr 5 ;


ENV HOST_CC=${CC}
ENV HOST_CXX=clang++
ENV HOST_LD=lld

# DEBUG Mark 1
RUN printf "%s\n" "Rebuild (reproducible) stage libc++" && \
    printf "%s\n" "CMake Version: $(cmake --version)" && \
    printf "%s\n" "Clang-cpp Version: $(clang-cpp --version)" && \
    printf "%s\n" "Clang++ Version: $(clang++ --version)" && \
    printf "%s\n" "Installed Libraries:" && \
    ls -1 ${SYSROOT:-/sysroot}/usr/lib/ && ls -1 ${SYSROOT:-/sysroot}/usr/lib/generic/ && \
    printf "\n"

# may need -Xlinker --sysroot=/sysroot
# may want linker flag -Xlinker --nostdlib to prevent linking to any std c++
# may want to link -Xlinker -l${LLVM_RTLIB_STUB}
ENV LDFLAGS="-fuse-ld=lld -v -Xlinker --trace-symbol=_Unwind_Resume -Xlinker --sysroot=${SYSROOT:-/sysroot} -Xlinker -L -Xlinker ${SYS_LIB} -Xlinker -L -Xlinker ${SYSROOT:-/sysroot}/lib -Xlinker -L -Xlinker ${SYS_LIB}/generic -Xlinker -l${LLVM_RTLIB_STUB} -Xlinker --exclude-libs=libgcc_s.so.1 -Xlinker --exclude-libs=libgcc_s.so -Xlinker --dynamic-linker=${SYSROOT:-/sysroot}/lib/${MUSL_LDLIB}"
# Does NOT require -D__ELF__
ENV CFLAGS="--no-default-config --target=${TARGET_TRIPLE} -rtlib=compiler-rt -fPIC -Xlinker --pic-veneer -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT:-/sysroot}/usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-ffunction-sections -fdata-sections --unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

# force the correct libunwinder
ENV CXX_UNWINDER_FLAGS="--unwindlib=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/lib/libunwind.so.1.0"

# Stage 4 of 4: Reproduce build against stage 3 build
#
# Changes from stage 3 ...
# built against stage 3 (just need reproducibility and tests)
# Removed -DCMAKE_EXE_LINKER_FLAGS=... stuff
# swap enable order of runtimes (trivial config test)

# --- Stage 4: Build libc++ linking against libcxxabi from stage0-cxx (round-trip libc++ bootstrap1) ---
RUN mkdir -p /work/build-libcxx-final && cd /work/build-libcxx-final && \
    /work/run_cmake_build.sh /work/llvm-project/runtimes /work/build-libcxx-final \
      -G Ninja \
      -DCMAKE_C_COMPILER=${HOST_CC} \
      -DCMAKE_CXX_COMPILER=${HOST_CXX} \
      -DCMAKE_LINKER=${HOST_LD} \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_RUNTIMES="libcxxabi;libcxx" \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DLLVM_RUNTIMES_TARGET=${TARGET_TRIPLE} \
      -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
      -DCMAKE_SYSROOT=${SYSROOT:-/sysroot} \
      -DCMAKE_FIND_ROOT_PATH=${SYSROOT:-/sysroot} \
      -DCMAKE_INSTALL_PREFIX=/work/builds/opt/libcxx-final \
      -DLIBCXX_ENABLE_SHARED=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXX_ENABLE_EXCEPTIONS=ON \
      -DLIBCXX_ENABLE_RTTI=ON \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBCXX_ENABLE_THREADS=ON \
      -DLIBCXX_HAS_PTHREAD_API=ON \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXX_HARDENING_MODE=extensive \
      -DLIBCXX_ABI_VERSION=1 \
      -DLIBCXX_CXX_ABI=libcxxabi \
      -DLIBCXX_CXX_ABI_LIBRARY_PATH=${SYS_LIB} \
      -DLIBCXX_CXX_ABI_INCLUDE_PATHS="${SYS_INCLUDE}/c++/v1" \
      -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
      -DLIBCXX_ENABLE_NEW_DELETE_DEFINITIONS=OFF \
      -DLIBCXXABI_USE_LLVM_UNWINDER=NO \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_SHARED=ON \
      -DLIBCXXABI_ENABLE_STATIC=OFF \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
      -DLIBCXXABI_LIBUNWIND_INCLUDES=/stage/usr/include \
      -DLIBCXXABI_ENABLE_THREADS=ON \
      -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
      -DLIBCXXABI_HAS_C_LIB=ON \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CXXFLAGS} ${CFLAGS} -Qunused-arguments" \
      -DLIBCXX_LINK_FLAGS="${CXX_UNWINDER_FLAGS} -v ${LDFLAGS} -Xlinker --verbose" \
      -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
      -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER && \
    { find /work/build-libcxx-final -type f -iname "*.so" -exec file {} + || true ;} && \
    cmake --install /work/build-libcxx-final && \
    { find /work/builds/opt/libcxx-final -type f -iname "*.so" -exec file {} + || true ;} ;

# --- Stage 5: smoke test ---
# Build test program and link against final libs
# should work in c++17 mode now
RUN ${HOST_CXX} -std=c++17 -stdlib=libc++ -nostdinc -nostdinc++ \
    -resource-dir /empty-resource-dir \
    --sysroot=${SYSROOT:-/sysroot} \
    -cxx-isystem /usr/include/c++/v1 \
    -isystem /usr/include -I${SYSROOT:-/sysroot}/usr/include/c++/v1 -I${SYSROOT:-/sysroot}/usr/include \
    -unwindlib=libunwind ${CFLAGS} \
    -x c++ /work/test_exception.cpp -o /work/test_exception \
    -fuse-ld=lld -L/work/builds/opt/libcxx-final/lib -lunwind -lc++ -lc++abi \
    -Xlinker --sysroot=${SYSROOT:-/sysroot} -Xlinker --rpath="/work/builds/opt/libcxx-final/lib:${SYS_LIB}" ;

# TODO: cleanup and remove no-longer needed packages

# Run the built smoke test
RUN file /work/test_exception && \
    /work/test_exception

CMD ["/work/test_exception"]

# --- bootstrap: bootstrap environment using distro clang/llvm to compile a minimal clang toolchain ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS bootstrap

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage
COPY --from=build-libcxx /work/builds/opt/libcxx-final /stage-cxx-root
# should not need
#COPY --from=build-libcxxrt /sysroot /stage-libcxxrt
#COPY --from=libcxxheaders /headers /stage-cxx

COPY payloads/bin/run_post_build_strip.sh /bootstrap/bin/run_post_build_strip.sh

# Copy custom Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl/Platforms/Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl/Linkers/Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB_STUB
ENV LLVM_RTLIB_STUB="${LLVM_RTLIB_STUB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB:-lib${LLVM_RTLIB_STUB}.a}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=lld
# will use /sysroot/usr/bin/ld.musl-clang later
#ENV LD=/sysroot/usr/bin/ld.musl-clang

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

ENV LDFLAGS="-v -Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic"
ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot ${SYSROOT:-/sysroot} -iwithsysroot /usr/include"
ENV CXXFLAGS="-stdlib=libc++ -cxx-isystem /sysroot/usr/include/c++/v1 --unwindlib=/sysroot/usr/lib/libunwind.so.1.0"

# overlay the unwinder
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYSROOT:-/sysroot}/lib/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYSROOT:-/sysroot}/lib/libunwind.so

# Ensure we have the unwinder and libc headers present (sysroot paths)
RUN ls -l ${SYSROOT:-/sysroot}${MUSL_PREFIX}/include || true \
    && file ${SYSROOT:-/sysroot}${MUSL_PREFIX}/include/* || true

# overlay the standard c++ library (from stage-cxx-root)
# skip usr/lib/libc++.a for now
RUN mkdir -pv ${SYSROOT:-/sysroot}/usr/include/c++/v1 && \
    for CXXSTD_FILE_ARTIFACT in usr/lib/libc++.so \
        usr/lib/libc++abi.so \
        usr/lib/libc++experimental.a ; do \
          if [ -f /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ] ; then \
            install -m 755 /stage-bootstrap/${CXXSTD_FILE_ARTIFACT} ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
            touch -d "${SOME_DATE_EPOCH}" ${SYSROOT:-/sysroot}/${CXXSTD_FILE_ARTIFACT} || true ; \
          fi ;\
    done ;\
    cp -f /stage0-cxx/usr/include/c++/v1/ ${SYSROOT:-/sysroot}/usr/include/c++/v1/ && \
    /bootstrap/bin/run_dir_check.sh ${SYSROOT:-/sysroot}/usr/include/c++/v1 10 ;

#check the lib directories too
# check on the lib
RUN printf "%s\n" "Bootstrapped Libs (pre-c++):" && \
    ls -lap ${SYSROOT:-/sysroot}/lib/ && file ${SYSROOT:-/sysroot}/lib/generic/* || true ;\
    ls -lap ${SYSROOT:-/sysroot}/lib/generic/ && file ${SYSROOT:-/sysroot}/lib/generic/* || true ;\
    printf "%s\n" "Bootstrapped Headers:" && \
    ls -lapr ${SYSROOT:-/sysroot}/usr/include/ || true

# Install distro packages that provide clang able to cross-emit --target. Adjust names for Alpine tag.
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    cmd:clang \
    llvm \
    lld \
    compiler-rt \
    cmd:llvm-ar \
    cmake \
    python3 \
    samurai \
    cmd:grep \
    pkgconfig \
    file \
    cmd:clang-cpp \
    cmd:clang++ \
    cmd:find \
    cmd:llvm-otool \
    cmd:llvm-objdump \
    cmd:llvm-ranlib \
    cmd:llvm-nm \
    cmd:llvm-strip

# Install into Alpine cmake's Platform dir as PlatformGeneric-Musl.cmake
RUN mkdir -p /usr/share/cmake/Modules/Platform \
 && install -m 0644 /tmp/Generic-Musl.cmake /usr/share/cmake/Modules/Platform/Generic-Musl.cmake \
 && rm /tmp/Generic-Musl.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform \
 && mkdir -p /usr/share/cmake/Modules/Platform/Linker \
 && install -m 0644 /tmp/Generic-Musl-Linker.cmake /usr/share/cmake/Modules/Platform/Linker/Generic-Musl-Linker.cmake \
 && rm /tmp/Generic-Musl-Linker.cmake \
 && chmod -R a+rX /usr/share/cmake/Modules/Platform/Linker

WORKDIR /bootstrap/llvmorg

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN apk add --no-cache \
    cmd:g++
# but we remove it anyway afterwards

# DEBUG Mark 2
RUN printf "%s\n" "CMake Version: $(cmake --version)" && \
    printf "%s\n" "Clang-cpp Version: $(clang-cpp --version)" && \
    printf "%s\n" "Clang++ Version: $(clang++ --version)" && \
    printf "%s\n" "Installed Libraries:" && \
    ls -1 ${SYSROOT:-/sysroot}/usr/lib/ && ls -1 ${SYSROOT:-/sysroot}/usr/lib/generic/ && \
    printf "\n"

# Ensure we have the dynamic loader and libs present (sysroot paths)
#RUN ls -l ${SYSROOT:-/sysroot}${MUSL_PREFIX}/lib || true \
#    && file ${SYSROOT:-/sysroot}/usr/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l ${SYSROOT:-/sysroot}/usr/include || true \
    && file ${SYSROOT:-/sysroot}/usr/include/* || true

# Ensure we have the c++abi lib and headers present (sysroot paths)
RUN ls -l ${SYSROOT:-/sysroot}${MUSL_PREFIX}/lib || true \
    && file ${SYSROOT:-/sysroot}${MUSL_PREFIX}/lib/* || true

# Ensure we have the libc++ headers present (sysroot paths)
RUN ls -l ${SYSROOT:-/sysroot}${MUSL_PREFIX}/include/c++/v1 || true \
    && file ${SYSROOT:-/sysroot}${MUSL_PREFIX}/include/c++/v1/* || true

# Build minimal clang (install to sysroot)
RUN cmake -S llvm -B build-llvm -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT:-/sysroot}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg \
    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
    -DClang_DIR=/bootstrap/llvmorg/clang \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_SYSTEM_NAME=Generic-Musl \
    -DCMAKE_SYSROOT="${SYSROOT:-/sysroot}" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DTARGET_TRIPLE=${TARGET_TRIPLE} \
    -DHOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments -Wl,--dynamic-linker=/lib/${MUSL_LDLIB} ${LDFLAGS}" \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++ -rtlib=compiler-rt -fPIC -Qunused-arguments -Wl,--dynamic-linker=/lib/${MUSL_LDLIB} ${LDFLAGS}" \
    -DLLVM_ENABLE_LIBCXX=true \
    -DLLVM_ENABLE_ZSTD=false \
    -DLLVM_ENABLE_ZLIB=false \
    -DCMAKE_LINKER=ld.lld \
    -DCXX_SUPPORTS_CUSTOM_LINKER=true \
    -DLLVM_ENABLE_LIBXML2=0 && \
    cmake --build build-llvm && \
    cmake --install build-llvm

# additional tools for building llvm
RUN set -eux \
    && apk add --no-cache \
        cmd:find

# check on the lib
RUN ls -lap ${SYSROOT:-/sysroot}/lib/ && ls -lap ${SYSROOT:-/sysroot}/lib/linux/ || true

RUN find ${SYSROOT:-/sysroot} -type f -iname "*.so*" 2>/dev/null || true
RUN find ${SYSROOT:-/sysroot} -type f -iname "*.a" 2>/dev/null || true
RUN find ${SYSROOT:-/sysroot} -type f -iname "clang*" 2>/dev/null || true

ENV BOOTSTRAP_CLANG=/opt/llvm-bootstrap/bin/clang
ENV BOOTSTRAP_CLANGXX=/opt/llvm-bootstrap/bin/clang++
ENV PATH=/opt/llvm-bootstrap/bin:$PATH

# MARK MUSL

# Stage 3: build full LLVM runtimes using bootstrap compiler and toolchain file
FROM --platform=linux/${TARGETARCH} alpine:latest AS runtimes-build
ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.6"}
ENV MUSL_VERSION=${MUSL_VERSION}
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
ENV MUSL_PREFIX="/staging/usr/"
ENV CFLAGS="-stdlib=libc++ -rtlib=compiler-rt"


WORKDIR /build
# install build deps (no gcc)
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add \
    cmake \
    samurai \
    python3 \
    musl-dev \
    pkgconf \
    zlib-dev \
    perl \
    libc++ \
    cmd:lld \
    cmd:bash \
    build-base \
    cmd:dash \
    lld \
    llvm \
    llvm-dev \
    libc++-dev \
    compiler-rt \
    llvm-runtimes \
    cmd:find

# Copy musl runtime artifacts from builder:
# - dynamic loader (ld-musl-*.so.1)
# - libmusl shared object(s) (libc.so.*)
# - crt*.o (for static linking if needed)
# - headers
COPY --from=bootstrap /sysroot /sysroot
# Copy bootstrap compiler and sources
COPY --from=fetcher /fetch/llvmorg /build/llvmorg

# map clang bootstrap to sysroot headers
RUN ln -sf /opt/llvm-bootstrap/include/clang /sysroot/usr/include/clang && \
    ln -sf /opt/llvm-bootstrap/include/clang-c /sysroot/usr/include/clang-c && \
    ln -sf /opt/llvm-bootstrap/include/lld /sysroot/usr/include/lld && \
    ln -sf /opt/llvm-bootstrap/include/llvm /sysroot/usr/include/llvm && \
    ln -sf /opt/llvm-bootstrap/include/llvm-c /sysroot/usr/include/llvm-c && \
    ln -sf /usr/include/c++ /sysroot/usr/include/c++ && \
    mkdir -pv /sysroot/usr/lib/ && \
    ln -sf /usr/lib/'libc++.so.1.0' /sysroot/usr/lib/'libc++.so.1.0' && \
    ln -sf /usr/lib/'libc++abi.so.1.0' /sysroot/usr/lib/'libc++abi.so.1.0' && \
    ln -sf "libc++.so.1.0" /sysroot/usr/lib/'libc++.so.1' && \
    ln -sf "libc++abi.so.1.0" /sysroot/usr/lib/'libc++abi.so.1'


# Copy the toolchain file into the image
COPY Generic-Musl/llvm-musl-toolchain.cmake /build/llvm-musl-toolchain.cmake

ENV BOOTSTRAP_CLANG=/opt/llvm-bootstrap/bin/clang
ENV BOOTSTRAP_CLANGXX=/opt/llvm-bootstrap/bin/clang++
ENV PATH=/opt/llvm-bootstrap/bin:$PATH

## DEBUG CODE A

# CHECK toolchain paths
RUN for SOME_FILE in \
    /opt/llvm-bootstrap/bin \
    /opt/llvm-bootstrap/include \
    /sysroot/lib \
    /sysroot/usr/lib \
    /sysroot/usr/include \
    /usr/include \
    /sysroot/usr/include/c++ \
    /usr/include/c++ \
    /sysroot/usr/include/c++/./ ; do \
      printf '\nListing %s:\n' "${SOME_FILE}" && \
      ls -lap "${SOME_FILE}" ; done ;


RUN ls -lap /opt/llvm-bootstrap/lib || true ;

RUN find /sysroot/ -type d -iname "*c++" 2>/dev/null || true ;

RUN printf "%s\n" "TARGET_TRIPLE is set to: $TARGET_TRIPLE" && \
    printf "%s\n" "HOST_TRIPLE is set to: $HOST_TRIPLE" && \
    printf "%s\n" "BOOTSTRAP_CLANG is set to: $BOOTSTRAP_CLANG" && \
    printf "%s\n" "BOOTSTRAP_CLANGXX is set to: $BOOTSTRAP_CLANGXX"

## END DEBUG CODE A

ENV SYSROOT=/sysroot

# Build runtimes using the toolchain file
RUN mkdir -p /build/llvm-build && cd /build/llvmorg/llvm && \
    cmake -S . -B /build/llvm-build -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=/build/llvm-musl-toolchain.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/llvm-final \
      -DTARGET_TRIPLE=${TARGET_TRIPLE} \
      -DHOST_TRIPLE=${HOST_TRIPLE} \
      -DSYSROOT=/sysroot \
      -DCMAKE_SYSROOT=/sysroot \
      -DBOOTSTRAP_CLANG="${BOOTSTRAP_CLANG}" \
      -DBOOTSTRAP_CLANGXX="${BOOTSTRAP_CLANGXX}" \
      -DLLVM_ENABLE_RUNTIMES="libunwind;libcxx;libcxxabi" && \
    cmake --build /build/llvm-build --target install-runtimes -j$(nproc)

## DEBUG CODE B

# CHECK toolchain paths
RUN ls -lap /sysroot/bin && \
    ls -lap /sysroot/include && \
    ls -lap /sysroot/lib && \
    ls -lap /sysroot/opt/llvm-final/llvm/bin && \
    ls -lap /sysroot/opt/llvm-final/llvm

# CHECK lib paths
RUN for d in /sysroot/usr/lib /sysroot/lib /sysroot/usr/local/lib /sysroot/usr/share/lib /sysroot/usr/libexec; do \
      echo "$d" ; \
      [ -d "$d" ] && ls -lap "$d"; \
    done ;

RUN dash /usr/bin/pick-and-anvil.sh || true ;

# VALIDATE CLANG
RUN printf "%s\n" 'int main() {return 0;}' > sanity.c && \
    /home/builder/llvm/bin/clang -target ${TARGET_TRIPLE} -fPIC -static -nostdlib -o sanity.o -c sanity.c && \
    /home/builder/llvm/bin/clang -Os sanity.o -fuse-ld=lld sanity

# Create a directory for the tests
RUN mkdir -p /tests

# Create test source files
RUN echo '#include <stdio.h>\nint main() { printf("Hello, World!\\n"); return 0; }' > /tests/test_syntax.c
RUN echo '#include <stdio.h>\nint main() { int a = 5; float b = 3.2; double c = 4.5; printf("Sum: %f\\n", a + b + c); return 0; }' > /tests/test_data_types.c
RUN echo '#include <stdio.h>\nint main() { for (int i = 0; i < 5; i++) { printf("Iteration: %d\\n", i); } return 0; }' > /tests/test_control_structures.c
RUN echo '#include <stdio.h>\nint add(int x, int y) { return x + y; }\nint main() { printf("Sum: %d\\n", add(3, 4)); return 0; }' > /tests/test_functions.c
RUN echo '#include <assert.h>\nint main() { static_assert(1 == 1, "This should always be true"); return 0; }' > /tests/test_c11_features.c
RUN echo '#include <iostream>\nclass Base { public: virtual void show() { std::cout << "Base class" << std::endl; }}; class Derived : public Base { public: void show() override { std::cout << "Derived class" << std::endl; }}; int main() { Base* b = new Derived(); b->show(); delete b; return 0; }' > /tests/test_classes.cpp
RUN echo '#include <iostream>\n#include <vector>\n#include <algorithm>\nint main() { std::vector<int> vec = {1, 2, 3, 4, 5}; std::for_each(vec.begin(), vec.end(), [](int n) { std::cout << n << " "; }); std::cout << std::endl; return 0; }' > /tests/test_lambda.cpp
RUN echo '#include <iostream>\n#include <stdexcept>\nint main() { try { throw std::runtime_error("An error occurred"); } catch (const std::exception& e) { std::cout << "Caught exception: " << e.what() << std::endl; } return 0; }' > /tests/test_exceptions.cpp
RUN echo '#include <iostream>\ntemplate <typename T> T add(T a, T b) { return a + b; }\nint main() { std::cout << "Sum: " << add(3, 4) << std::endl; return 0; }' > /tests/test_templates.cpp
RUN echo '#include <iostream>\n#include <memory>\nclass MyClass { public: MyClass() { std::cout << "Constructor" << std::endl; } ~MyClass() { std::cout << "Destructor" << std::endl; }};\nint main() { std::unique_ptr<MyClass> ptr(new MyClass()); return 0; }' > /tests/test_smart_pointers.cpp
RUN echo '#include <iostream>\n#include <vector>\nint main() { std::vector<int> vec = {1, 2, 3, 4, 5}; for (int n : vec) { std::cout << n << " "; } std::cout << std::endl; return 0; }' > /tests/test_range_based_for.cpp
RUN echo '#include <iostream>\nconstexpr int square(int x) { return x * x; }\nint main() { std::cout << "Square of 5: " << square(5) << std::endl; return 0; }' > /tests/test_constexpr.cpp
RUN echo '#include <stdio.h>\n#include <pthread.h>\nvoid* print_message(void* ptr) { char* message = (char*)ptr; printf("%s\\n", message); return NULL; }\nint main() { pthread_t thread1; const char* message1 = "Thread 1"; pthread_create(&thread1, NULL, print_message, (void*)message1); pthread_join(thread1, NULL); return 0; }' > /tests/test_threading.c

# Compile and run tests
RUN /home/builder/llvm/bin/clang -target ${TARGET_TRIPLE} -o /tests/test_s

## END DEBUG CODE B

# ---- final stage: artifact only ----
# Final artifact stage: copy llvm-alpine-musl
FROM scratch AS llvm-alpine-musl

LABEL version="20260401"
LABEL org.opencontainers.image.title="llvm-alpine-musl"
LABEL org.opencontainers.image.description="Hermetically built llvm-alpine-musl."
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="MIT"

# provenance ENV (kept intentionally)
ARG LLVM_VERSION=${LLVM_VERSION:-"22.1.4"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

COPY --from=runtimes-build /sysroot /
