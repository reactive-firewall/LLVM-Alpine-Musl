# syntax=docker/dockerfile:1

# ---- fetcher stage: install and cache required Alpine packages and fetch release tarballs ----

# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS fetcher

# Set environment variables
ARG LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION:-"1.3"}
ENV LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION}
ENV LIBEXECINFO_URL="https://github.com/reactive-firewall/libexecinfo/raw/refs/tags/v${LIBEXECINFO_VERSION}/libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2"
ARG LLVM_VERSION=${LLVM_VERSION:-"22.1.3"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.6"}
ENV MUSL_VERSION=${MUSL_VERSION}
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"

WORKDIR /fetch
ENV CC=clang
ENV CXX=clang-cpp
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"

# OTHER VARS - BUNDLE ONLY (NOT USED ATM)
ARG HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION:-"17.2"}
ENV HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION}
ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"


# Install necessary packages
# ca-certificates - MPL AND MIT - do not bundle - just to verify certificates (weak)
# alpine - MIT - do not bundle - just need an OS (weak)
# curl - curl License / MIT (direct)
# bsdtar - BSD-2 - used to unarchive during bootstrap (transient)
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="cURL License"

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add \
    ca-certificates \
    curl \
    cmd:bsdtar && \
  update-ca-certificates

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
# OPTIONAL
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
#ENV HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION}
#ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"

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
#       binutils \
#        curl \
#        ca-certificates \
#        build-base \
#        gzip \
#        perl \
#        paxctl

# copy optional linux sources (for musl headers)
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


# --- Prepare Stage: prepare sysroot for musl headers ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS sysroot

# version is passed through by Docker.
# shellcheck disable=SC2154
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.6"}
ENV MUSL_VERSION=${MUSL_VERSION}
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
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
ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

# does not use cmd:bsdtar nor gzip

RUN set -eux \
    && apk add --no-cache \
        clang \
        llvm \
        libc++ \
        libc++-dev \
        compiler-rt \
        llvm-runtimes \
        cmd:llvm-ar \
        lld \
        make \
        binutils \
        curl \
        ca-certificates \
        build-base \
    && mkdir -pv /build && mkdir -pv "${SYSROOT}"

WORKDIR /staging

# IMPORTANT:
# carefully craft symlinks to only look deeper, build tools like ninja don't resolve symlinks well
# see https://github.com/ninja-build/ninja/issues/1330

RUN mkdir -pv ${MUSL_PREFIX} && \
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
      [ -d "${SYSROOT}"/lib64 ] || ln -svf usr/lib "${SYSROOT}"/lib64; \
      [ -d "${SYSROOT}"/usr/lib64 ] || ln -svf lib "${SYSROOT}"/usr/lib64; \
    fi

WORKDIR /build

ENV CC=clang
ENV CPP=clang-cpp
ENV AR=llvm-ar
ENV AS="clang -integrated-as -c"
ENV ASM=clang
ENV RANLIB=llvm-ranlib
ENV LD=ld.lld
# can't use -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 yet
ENV LDFLAGS="-fuse-ld=lld -Wl,--sysroot=/sysroot"

# musl libc checks TZ
# format is
# [SUS/POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap08.html#tag_08_03)
# Set TZ to UTC
ENV TZ='UTC+0'

# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

# copy sources (for musl headers)
COPY --from=fetcher /fetch/musl /build/musl

# OPTIONAL - copy headers to $SYSROOT

# linux/kd.h
# linux/soundcard.h
# linux/vt.h

# DEBUG: works without linux headers
#COPY --from=linux-trampoline /build/linux/usr/include /sysroot/usr/include

# copy llvm sources (for compiler_rt)
COPY --from=fetcher /fetch/llvmorg /build/llvm

# MAY want -D_POSIX_C_SOURCE=202405L for v1.2.6 (TODO: review)
# musl should be given these values too
ENV CFLAGS="-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700"

# --- Prepare Stage: prepare musl sysroot with headers ---
WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
      --enable-wrapper=clang \
      CC=clang \
      CXX=clang++ \
      AR=llvm-ar RANLIB=llvm-ranlib \
      LDFLAGS="${LDFLAGS}" \
      CFLAGS="${CFLAGS} -stdlib=libc++ -rtlib=compiler-rt -fno-math-errno -fPIC -fno-common" && \
    make -j"$(nproc)" && \
    DESTDIR="${SYSROOT}" make install-headers && \
    rm -rfv ./build

# Ensure we have the dynamic loader and libs present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true \
    && file ${SYSROOT}${MUSL_PREFIX}/include/* || true


# --- Prepare Stage: prepare musl sysroot for TARGET_TRIPLE ---
WORKDIR /build/llvm

ENV CXXFLAGS="-stdlib=libc++ -fPIC -target ${TARGET_TRIPLE}"

# additional tools for building llvm
# python3 license: PSF-2.0
RUN set -eux \
    && apk add --no-cache \
        samurai \
        cmd:clang++ \
        cmake \
        python3 \
        pkgconfig \
        zlib-dev \
        perl \
        paxctl \
        cmd:find


# --- Precompile CC Stage0: prepare musl sysroot with clang builtins for TARGET_TRIPLE ---
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
      -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_ASM_COMPILER=clang \
      -DCMAKE_SYSTEM_NAME=Generic \
      -DLIBC_TARGET_TRIPLE=${TARGET_TRIPLE} \
      -DCMAKE_SYSROOT="${SYSROOT}" && \
      cmake --build build-compiler-rt && \
      cmake --install build-compiler-rt && \
      rm -rfv build-compiler-rt

RUN set -eux \
    && apk del --no-cache \
        samurai \
        cmake \
        python3 \
        pkgconfig \
        zlib-dev 2>/dev/null

# Ensure we have the clang builtins lib
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/generic/ || true;


# --- runtime Trampoline Stage: compile musl sysroot with compiler_rt ---
WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
      --enable-wrapper=clang \
      CC=clang \
      AR=llvm-ar RANLIB=llvm-ranlib \
      LDFLAGS="${LDFLAGS}" \
      LIBCC="-l${SYSROOT}${MUSL_PREFIX}/lib/Generic/${LLVM_RTLIB}" \
      CFLAGS="${CFLAGS} --sysroot=$SYSROOT -rtlib=compiler-rt -fno-math-errno -fPIC -fno-common -fuse-ld=lld" && \
    make -j"$(nproc)" && \
    DESTDIR=${SYSROOT} make install

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

# purge transient packages
RUN set -eux \
    && apk del --no-cache \
        cmd:clang++ \
        perl \
        paxctl \
        cmd:find

# Ensure the dynamic loader is configured to search paths correctly
COPY ld-musl-x86_64.path /etc/ld-musl-x86_64.path
RUN set -eux; \
    if [ "$(uname -m)" = "x86_64" ]; then \
      [ -L "${SYSROOT}"/etc/ld-musl-i486.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i486.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-i586.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i586.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-i686.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-i686.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-x86h.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-x86_64h.path; \
      [ -L "${SYSROOT}"/etc/ld-musl-generic.path ] || ln -svf ld-musl-x86_64.path "${SYSROOT}"/etc/ld-musl-generic.path; \
    fi ;

COPY ld-musl-aarch64.path /etc/ld-musl-aarch64.path
RUN set -eux; \
    if [ "$(uname -m)" = "aarch64" ]; then \
      [ -L "${SYSROOT}"/etc/ld-musl-generic.path ] || ln -svf ld-musl-aarch64.path "${SYSROOT}"/etc/ld-musl-generic.path; \
    fi;

COPY ld-musl-arm.path /etc/ld-musl-arm.path
RUN set -eux; \
    [ -L "${SYSROOT}"/etc/ld-musl-armv7.path ] || ln -svf ld-musl-arm.path "${SYSROOT}"/etc/ld-musl-armv7.path; \
    [ -L "${SYSROOT}"/etc/ld-musl-armv8.path ] || ln -svf ld-musl-arm.path "${SYSROOT}"/etc/ld-musl-armv8.path;


# --- unwind-base: bootstrap unwind using distro clang/llvm to compile a minimal unwind library ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS build-unwind-base

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot

# copy ehframe.ld script
COPY ehframe.ld /bootstrap/ehframe.ld

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
ENV LDFLAGS="-Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic -Wl,--unique -Wl,--dynamic-linker=/sysroot/lib/${MUSL_LDLIB} -fuse-ld=lld -unwindlib=none"
# does NOT require -D__linux__
ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT}/usr/include"
ENV CXXFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0"

WORKDIR /bootstrap/llvmorg

# might need LDFLAGS="-Wl,--exclude-libs,libssp_nonshared.a"
# also might need -DCMAKE_C_FLAGS="-fno-stack-protector" -DCMAKE_CXX_FLAGS="-fno-stack-protector"

# Build minimal llvm libunwind (install to sysroot)
RUN cmake -S runtimes -B build-libunwind -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
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

# check on the lib
#RUN printf "%s\n" "Bootstrapped Libs (static):" && \
#    ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/generic/ || true ; \
#    printf "%s\n" "Bootstrapped Headers:" && \
#    ls -lapr ${SYSROOT}/usr/include/ || true

# move the changed files out to stage

RUN mkdir -pv /stage-static/usr/include/mach-o && mkdir -pv /stage-static/usr/lib && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a ; do \
          cp -vn ${SYSROOT}/${UNWIND_FILE_ARTIFACT} /stage-static/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" /stage-static/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

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

# may need -Wl,--sysroot=/sysroot OR -Wl,--dynamic-linker=/lib/libc.so
# may need to play around with -Wl,--allow-shlib-undefined to allow __eh_* undefs
# may want -unwindlib=none when building libunwind
ENV LDFLAGS="-Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic -Wl,--unique -Wl,--dynamic-linker=/sysroot/lib/${MUSL_LDLIB} -fuse-ld=lld -Wl,-T,/bootstrap/ehframe.ld"
# may require -D__linux__
ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT}/usr/include -iwithsysroot /usr/include"
ENV CXXFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0"

WORKDIR /bootstrap/llvmorg

# might need LDFLAGS="-Wl,--exclude-libs,libssp_nonshared.a"
# also might need -DCMAKE_C_FLAGS="-fno-stack-protector" -DCMAKE_CXX_FLAGS="-fno-stack-protector"

# and again for shared lib (but use clang++ for first pass)
RUN cmake -S runtimes -B build-libunwind -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
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
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -v -Qunused-arguments -Wl,--eh-frame-hdr -Wl,--verbose" \
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
          cp -vn ${SYSROOT}/${UNWIND_FILE_ARTIFACT} /stage/${UNWIND_FILE_ARTIFACT} || true ; \
    done ; \
    if [ -f usr/lib/libunwind.so.1.0 ] ; then \
      if command -v llvm-strip >/dev/null 2>&1; then \
         llvm-strip --strip-unneeded /stage/usr/lib/libunwind.so.1.0 + || true; \
      else \
         strip --strip-unneeded /stage/usr/lib/libunwind.so.1.0 + || true; \
      fi ; \
      touch -d "${SOME_DATE_EPOCH}" /stage/usr/lib/libunwind.so.1.0 || true ; \
    fi


# --- Lib C++ headers ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS libcxxheaders

WORKDIR /bootstrap

# copy sources (llvmorg is the llvm-project checkout root)
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage

# Copy your Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

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
ENV LDFLAGS="-v -Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic"
# Does NOT may require -D__ELF__
ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot ${SYSROOT} -iwithsysroot /usr/include"
# might need -nostdinc++
ENV CXXFLAGS="-iwithsysroot /usr/include/c++/v1 -ffunction-sections -fdata-sections -unwindlib=/sysroot/usr/lib/libunwind.so.1.0"

# overlay the unwinder
RUN mkdir -pv ${SYSROOT}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYSROOT}/lib/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYSROOT}/lib/libunwind.so

# Ensure we have the unwinder and libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true \
    && file ${SYSROOT}${MUSL_PREFIX}/include/* || true

#check the lib directories too
# check on the lib
RUN printf "%s\n" "Bootstrapped Libs (pre-c++):" && \
    ls -lap ${SYSROOT}/lib/ && file ${SYSROOT}/lib/generic/* || true ;\
    ls -lap ${SYSROOT}/lib/generic/ && file ${SYSROOT}/lib/generic/* || true ;\
    printf "%s\n" "Bootstrapped Headers:" && \
    ls -lapr ${SYSROOT}/usr/include/ || true

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
    done ; \
    find /headers/usr/include -type f -iname "*.h" -depth 1 -exec sh -c 'for f; do ln -svf "$f" /headers/usr/include/$(basename "$f"); done' _ {} + || true;

# WORKAROUND: cmake still thinks that clang++ requires g++
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:clang++ \
    cmd:g++
# but we remove it anyway afterwards

WORKDIR /bootstrap/llvmorg

# Configure/install libc++ headers only into a "headers" sysroot
# -> install prefix is /headers/usr so final headers appear under /headers/usr/include
RUN set -eux; \
    mkdir -p build-libcxx-config; \
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
      -DLIBCXX_HAS_GCC_LIB=NO \
      -DLIBCXX_HAS_GCC_S_LIB=NO \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBCXX_ENABLE_THREADS=ON \
      -DLIBCXX_HAS_PTHREAD_API=ON \
      -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DLIBCXX_HARDENING_MODE=extensive \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CFLAGS} ${CXXFLAGS} -Qunused-arguments -Wl,--verbose" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=lld \
      -DLLVM_ENABLE_RUNTIMES= \
      -DLIBCXX_INCLUDE_TESTS=OFF \
    ; \
    cmake --build . --target install || true ;

WORKDIR /bootstrap/llvmorg

# Install libcxxabi headers too (ABI types required by libc++ headers)
RUN set -eux; \
    mkdir -p build-libcxxabi-config; \
    cd build-libcxxabi-config; \
    cmake -G Ninja \
      ../libcxxabi \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Generic-Musl \
      -DCMAKE_INSTALL_PREFIX=/headers/usr \
      -DLIBCXXABI_INSTALL_HEADERS=ON \
      -DLIBCXXABI_ENABLE_SHARED=OFF \
      -DLIBCXXABI_ENABLE_STATIC=OFF \
      -DLIBCXXABI_INSTALL_INCLUDE_TARGET_DIR=include/c++/v1 \
      -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_THREADS=ON \
      -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
      -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=FALSE \
      -DLIBCXXABI_HAS_GCC_S_LIB=NO \
      -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
      -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
      -DCMAKE_CXX_FLAGS="${CFLAGS} ${CXXFLAGS} -Qunused-arguments -Wl,--verbose" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_LINKER=lld \
      -DLLVM_ENABLE_RUNTIMES= \
      -DLIBCXXABI_INCLUDE_TESTS=OFF \
    ; \
    cmake --build . --target install

# Quick, trivial compile-time test that the headers are usable:
# compile-only (no linking) a small C++ snippet using the installed headers.
RUN set -eux; \
    printf '%s\n' '#include <vector>' '#include <string>' 'int main() {' '  std::vector<std::string> v;' '  v.push_back("ok");' '  return (int)v.size();' '}' > /tmp/test.cpp; \
    clang++ -fsyntax-only -std=c++17 -isystem /headers/usr/include /tmp/test.cpp ;


# Cleanup build packages and intermediate files to keep this stage small
RUN apk del --no-cache cmd:g++ cmd:clang++ make cmake samuri python3 && \
    rm -rf /bootstrap/build-libcxx-config /bootstrap/build-libcxxabi-config /tmp/test.cpp && \
    find /headers/usr/include -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true ;

# The resulting "headers" sysroot:
# /headers/usr/include    <-- contains libc++ and libcxxabi headers and generated config headers
# Keep them in this stage so a later stage can COPY --from=libcxxheaders /headers /headers

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l /headers/usr/include || true \
    && file /headers/usr/include/* || true

# --- bootstrap: bootstrap environment using distro clang/llvm to compile a minimal clang toolchain ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS bootstrap

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot
COPY --from=build-unwind /stage /stage
COPY --from=libcxxheaders /headers /stage-cxx

# Copy your Generic-Musl.cmake into the image build context before building the image
COPY Generic-Musl.cmake /tmp/Generic-Musl.cmake
COPY Generic-Musl-Linker.cmake /tmp/Generic-Musl-Linker.cmake

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

ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

ENV LDFLAGS="-v -Wl,--sysroot=/sysroot -Wl,-L,/sysroot/usr/lib -Wl,-L,/sysroot/lib -Wl,-L,/sysroot/usr/lib/generic"
ENV CFLAGS="-rtlib=compiler-rt -fPIC -ffunction-sections -fdata-sections -D_ALL_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -isysroot ${SYSROOT} -iwithsysroot /usr/include"
ENV CXXFLAGS="-iwithsysroot /usr/include/c++/v1 -unwindlib=/sysroot/usr/lib/libunwind.so.1.0"

# overlay the unwinder
RUN mkdir -pv ${SYSROOT}/usr/include/mach-o && \
    for UNWIND_FILE_ARTIFACT in usr/include/__libunwind_config.h \
        usr/include/libunwind.h \
        usr/include/libunwind.modulemap \
        usr/include/mach-o/compact_unwind_encoding.h \
        usr/include/unwind_arm_ehabi.h \
        usr/include/unwind_itanium.h \
        usr/include/unwind.h \
        usr/lib/libunwind.a \
        usr/lib/libunwind.so.1.0 ; do \
          cp -vf /stage/${UNWIND_FILE_ARTIFACT} ${SYSROOT}/${UNWIND_FILE_ARTIFACT} || true ; \
          touch -d "${SOME_DATE_EPOCH}" ${SYSROOT}/${UNWIND_FILE_ARTIFACT} || true ; \
    done ;

# Ensure unwind has canonical name (example: /usr/lib/libunwind.so -> /usr/lib/libunwind.so.1.0)
RUN set -eux \
    && ln -fns libunwind.so.1.0 ${SYSROOT}/lib/libunwind.so.1 && \
    ln -fns libunwind.so.1 ${SYSROOT}/lib/libunwind.so

# Ensure we have the unwinder and libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true \
    && file ${SYSROOT}${MUSL_PREFIX}/include/* || true

#check the lib directories too
# check on the lib
RUN printf "%s\n" "Bootstrapped Libs (pre-c++):" && \
    ls -lap ${SYSROOT}/lib/ && file ${SYSROOT}/lib/generic/* || true ;\
    ls -lap ${SYSROOT}/lib/generic/ && file ${SYSROOT}/lib/generic/* || true ;\
    printf "%s\n" "Bootstrapped Headers:" && \
    ls -lapr ${SYSROOT}/usr/include/ || true

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

# might want -DLIBCXX_ENABLE_THREADS=ON
# might want -DLIBCXX_HAS_PTHREAD_LIB=ON
# might want -DLLVM_RUNTIME_TARGETS="${TARGET_TRIPLE}"
# might need -DLIBCXX_HAS_ATOMIC_LIB=OFF ??
# might need -DLIBCXX_HAS_RT_LIB=ON
# might need -DLIBCXXABI_ENABLE_THREADS=ON
# might need -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=false
# might need -DLIBCXXABI_HAS_PTHREAD_API=ON
# might need -DLIBCXXABI_HAS_PTHREAD_LIB=ON
# might need -DLIBCXXABI_ENABLE_EXCEPTIONS=ON
# might need -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm
# might need -DLLVM_ENABLE_ZLIB=OFF
# might need -DLLVM_ENABLE_ZSTD=OFF
# might need to play with -DCLANG_DEFAULT_CXX_LIB=libc++
# might need to play with -DLIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS=ON
# might want to play with -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON

# might want unused -DLIBCXXABI_TARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DLIBCXX_TARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DTARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DHOST_TRIPLE=${HOST_TRIPLE}
# might want unused -DLIBCXX_HAS_C_LIB=ON

# might want -DLLVM_CONFIG_PATH=/usr/bin/llvm-config  (but need mocking implementation for sysroot)

# does not use manually added -DLLVM_LIBCXXABI_LIBRARY_PATH="${SYSROOT}/usr/lib"
# does not use manually added -DLIBCXXABI_HAS_GCC_LIB=NO
# might not use manually added -DLIBCXXABI_ENABLE_SHARED=ON (always seems to build static?)

# might want -fdebug-prefix-map=/include=${SYSROOT}/usr/include
# sysroot diff hint To see what will be set, inspect the built binary with: readelf -d <bin> | grep RUNPATH or objdump -x <bin> | grep RPATH

# might want unused -DLIBCXXABI_HAS_GCC_LIB=NO

# prob need -DCMAKE_CXX_COMPILER_ID="Clang"
# prob need -DCMAKE_CXX_COMPILER_VERSION=$(${CXX} --version 2>/dev/null | head -n1 | grep -m1 --color=never -oE "[1-9][0-9]*.[0-9]+[\.0-9]*" | head -n1 )

# copy all the libc++ headers into the sysroot
RUN mkdir -vp "$SYSROOT/usr/include/c++/v1/" && \
    cp -HRnp /stage-cxx/include/* "$SYSROOT"/usr/include || true


# DEBUG Mark 2
RUN printf "%s\n" "CMake Version: $(cmake --version)" && \
    printf "%s\n" "Clang-cpp Version: $(clang-cpp --version)" && \
    printf "%s\n" "Clang++ Version: $(clang++ --version)" && \
    printf "%s\n" "Installed Libraries:" && \
    ls -1 ${SYSROOT}/usr/lib/ && ls -1 ${SYSROOT}/usr/lib/generic/ && \
    printf "\n"

# Build minimal static libc++abi.so (install to sysroot)
RUN cmake -S runtimes -B build-libcxxabi-shared -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm/cmake/modules \
    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
    -DClang_DIR=/bootstrap/llvmorg/clang \
    -DLLVM_ENABLE_RUNTIMES="libcxxabi" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Generic-Musl \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
    -DCMAKE_CXX_FLAGS="${CFLAGS} ${CXXFLAGS} -Qunused-arguments -Wl,--verbose" \
    -DLIBCXXABI_SOURCE_DIR="/bootstrap/llvmorg/libcxxabi" \
    -DLIBCXXABI_LIBCXX_PATH="/bootstrap/llvmorg/libcxx" \
    -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_ENABLE_THREADS=ON \
    -DLIBCXXABI_HAS_PTHREAD_LIB=ON \
    -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=false \
    -DLIBCXXABI_HAS_GCC_S_LIB=NO \
    -DLIBCXXABI_ENABLE_SHARED=ON \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_COMPILER_ID="Clang" \
    -DCMAKE_LINKER=lld && \
    apk del --no-cache \
        g++ \
        cmd:g++ && \
    ls -lap -r /bootstrap/llvmorg/build-libcxxabi-shared && \
    ls -lap -r /bootstrap/llvmorg/build-libcxxabi-shared/lib && \
    ls -lap -r /bootstrap/llvmorg/build-libcxxabi-shared/libcxxabi && \
    ls -lap -r /bootstrap/llvmorg/build-libcxxabi-shared/libcxxabi/include && \
    ls -lap -r /bootstrap/llvmorg/build-libcxxabi-shared/CMakeFiles && \
    printf "\n\n%s\n" "CMake --build build-libcxxabi-shared MARK:" && \
    cmake --build build-libcxxabi-shared && \
    cmake --install build-libcxxabi-shared && \
    rm -vfr /bootstrap/llvmorg/build-libcxxabi-shared/

# Ensure we have the dynamic loader and libs present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/lib || true \
    && file ${SYSROOT}${MUSL_PREFIX}/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true \
    && file ${SYSROOT}${MUSL_PREFIX}/include/* || true

# Build minimal static libc++.a (install to sysroot)
#RUN cmake -S llvm -B build-runtimes -Wno-dev -G "Ninja" \
#    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
#    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm/cmake/modules \
#    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
#    -DClang_DIR=/bootstrap/llvmorg/clang \
#    -DLLVM_ENABLE_RUNTIMES="libcxx" \
#    -DLIBCXX_HAS_GCC_LIB=NO \
#    -DLIBCXX_HAS_GCC_S_LIB=NO \
#    -DLIBCXX_USE_COMPILER_RT=ON \
#    -DLIBCXX_ENABLE_SHARED=OFF \
#    -DLIBCXX_ENABLE_STATIC=ON \
#    -DLIBCXX_HAS_MUSL_LIBC=ON \
#    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
#    -DLIBCXX_HARDENING_MODE=extensive \
#    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
#    -DLIBCXX_ABI_VERSION=1 \
#    -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
#    -DLIBCXX_CXX_ABI=libcxxabi \
#    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
#    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
#    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
#    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
#    -DLLVM_DEFAULT_TARGET_TRIPLE=${HOST_TRIPLE} \
#    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
#    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
#    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -Qunused-arguments -Wl,--verbose" \
#    -DCMAKE_BUILD_TYPE=Release \
#    -DCMAKE_C_COMPILER=clang \
#    -DCMAKE_CXX_COMPILER=clang-cpp \
#    -DCMAKE_SYSTEM_NAME=Generic \
#    -DCMAKE_LINKER=ld.lld && \
#    apk del --no-cache \
#        g++ \
#        cmd:g++ && \
#    cmake --build build-runtimes && \
#    cmake --install build-runtimes && \
#    rm -vfr /bootstrap/llvmorg/build-runtimes/

# Ensure we have the dynamic loader and libs present (sysroot paths)
#RUN ls -l ${SYSROOT}${MUSL_PREFIX}/lib || true \
#    && file ${SYSROOT}/usr/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
#RUN ls -l ${SYSROOT}/usr/include || true \
#    && file ${SYSROOT}/usr/include/* || true

# Build minimal clang (install to stsroot)
#RUN cmake -S llvm -B build-llvm -G "Ninja" \
#    -DCMAKE_BUILD_TYPE=Release \
#    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
#    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg \
#    -DLLVM_MAIN_SRC_DIR=/bootstrap/llvmorg/llvm \
#    -DClang_DIR=/bootstrap/llvmorg/clang \
#    -DCMAKE_C_COMPILER=clang \
#    -DCMAKE_CXX_COMPILER=clang++ \
#    -DCMAKE_SYSTEM_NAME=Linux \
#    -DCMAKE_SYSROOT="${SYSROOT}" \
#    -DLLVM_ENABLE_PROJECTS="clang;lld" \
#    -DTARGET_TRIPLE=${TARGET_TRIPLE} \
#    -DHOST_TRIPLE=${HOST_TRIPLE} \
#    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
#    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
#    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
#    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
#    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments -Wl,--dynamic-linker=/lib/${MUSL_LDLIB} ${LDFLAGS}" \
#    -DCMAKE_CXX_FLAGS="-stdlib=libc++ -rtlib=compiler-rt -fPIC -Qunused-arguments -Wl,--dynamic-linker=/lib/${MUSL_LDLIB} ${LDFLAGS}" \
#    -DLLVM_ENABLE_LIBCXX=true \
#    -DLLVM_ENABLE_ZSTD=false \
#    -DLLVM_ENABLE_ZLIB=false \
#    -DCMAKE_LINKER=ld.lld \
#    -DCXX_SUPPORTS_CUSTOM_LINKER=true \
#    -DLLVM_ENABLE_LIBXML2=0 && \
#    cmake --build build-llvm && \
#    cmake --install build-llvm

# additional tools for building llvm
RUN set -eux \
    && apk add --no-cache \
        cmd:find

# check on the lib
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/linux/ || true

RUN find ${SYSROOT} -type f -iname "*.so*" 2>/dev/null || true
RUN find ${SYSROOT} -type f -iname "*.a" 2>/dev/null || true
RUN find ${SYSROOT} -type f -iname "clang*" 2>/dev/null || true

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
COPY --from=sysroot /sysroot /sysroot
# Copy bootstrap compiler and sources
COPY --from=bootstrap /opt/llvm-bootstrap/bin/* /sysroot/bin/
COPY --from=bootstrap /opt/llvm-bootstrap/lib/* /sysroot/lib/
COPY --from=bootstrap /opt/llvm-bootstrap/libexec/* /sysroot/libexec/
COPY --from=fetcher /fetch/llvmorg /build/llvmorg
COPY --from=bootstrap /opt/llvm-bootstrap/include/* /sysroot/usr/include/

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
COPY llvm-musl-toolchain.cmake /build/llvm-musl-toolchain.cmake

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
ARG LLVM_VERSION=${LLVM_VERSION:-"22.1.3"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

COPY --from=runtimes-build /sysroot /
