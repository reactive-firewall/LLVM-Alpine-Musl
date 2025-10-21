# syntax=docker/dockerfile:1

# ---- fetcher stage: install and cache required Alpine packages and fetch release tarballs ----

# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS fetcher

# Set environment variables
ARG LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION:-"1.3"}
ENV LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION}
ENV LIBEXECINFO_URL="https://github.com/reactive-firewall/libexecinfo/raw/refs/tags/v${LIBEXECINFO_VERSION}/libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2"
ARG HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION:-"17.2"}
ENV HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION}
ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"
ARG LLVM_VERSION=${LLVM_VERSION:-"21.1.5"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.5"}
ENV MUSL_VERSION=${MUSL_VERSION}
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
WORKDIR /fetch
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="clang -c"
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"

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
    cmd:bsdtar

# just need a place to fetch
RUN mkdir -p /fetch
WORKDIR /fetch

# Fetch the signed release tarballs (or supply via build-args)
# Download musl
RUN curl -fsSLo musl-${MUSL_VERSION}.tar.gz \
    --url "https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz" && \
    bsdtar -xzf musl-${MUSL_VERSION}.tar.gz && \
    rm musl-${MUSL_VERSION}.tar.gz && \
    mv /fetch/musl-${MUSL_VERSION} /fetch/musl
# get HOST linux Headers
RUN curl -fsSLo linux-6.${HOST_HEADERS_VERSION}.tar.gz \
    --url "https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz" && \
    bsdtar -xzf linux-6.${HOST_HEADERS_VERSION}.tar.gz && \
    rm linux-6.${HOST_HEADERS_VERSION}.tar.gz && \
    mv /fetch/linux-6.${HOST_HEADERS_VERSION} /fetch/linux
RUN curl -fsSLo libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 \
    --url "$LIBEXECINFO_URL" && \
    bsdtar -xzf libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 && \
    rm libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2 && \
    mv /fetch/libexecinfo-${LIBEXECINFO_VERSION}r /fetch/libexecinfo && \
    rm /fetch/libexecinfo/patches.tar.bz2
RUN curl -fsSLo llvmorg-${LLVM_VERSION}.tar.gz \
    --url "$LLVM_URL" && \
    bsdtar -xzf llvmorg-${LLVM_VERSION}.tar.gz && \
    rm llvmorg-${LLVM_VERSION}.tar.gz && \
    mv /fetch/llvm-project-llvmorg-${LLVM_VERSION} /fetch/llvmorg


# --- Strip-to-headers Stage: prepare stripped linux headers for musl sysroot ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS linux-trampoline

ARG HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION:-"17.2"}
ENV HOST_HEADERS_VERSION=${HOST_HEADERS_VERSION}
ENV HOST_HEADERS_URL="https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.${HOST_HEADERS_VERSION}.tar.gz"

RUN set -eux \
    && apk add --no-cache \
        cmd:bsdtar \
        clang \
        cmd:clang++ \
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
        gzip \
        perl \
        paxctl

# copy sources (for musl headers)
COPY --from=fetcher /fetch/linux /build/linux
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="clang -c"
ENV RANLIB=llvm-ranlib
ENV LDFLAGS="-fuse-ld=lld"

WORKDIR /build/linux

RUN make headers -j$(nproc) && \
    find usr/include -type f ! -name '*.h' -delete


# --- Prepare Stage: prepare sysroot for musl headers ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS sysroot

# version is passed through by Docker.
# shellcheck disable=SC2154
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.5"}
ENV MUSL_VERSION=${MUSL_VERSION}
ENV MUSL_URL="https://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"
ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB}"
ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
ENV SYSROOT="/sysroot"
ENV MUSL_PREFIX="/usr"

RUN set -eux \
    && apk add --no-cache \
        cmd:bsdtar \
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
        gzip \
        perl \
        paxctl \
    && mkdir -pv /build && mkdir -pv "${SYSROOT}"

WORKDIR /staging

RUN mkdir -pv ${MUSL_PREFIX} && \
    mkdir -pv "${SYSROOT}"/dev && \
    mkdir -pv "${SYSROOT}"/proc && \
    mkdir -pv "${SYSROOT}"/run && \
    mkdir -pv "${SYSROOT}"/sys && \
    mkdir -pv "${SYSROOT}"/share && \
    mkdir -pv "${SYSROOT}"/man && \
    mkdir -pv "${SYSROOT}"/tmp && \
    mkdir -pv "${SYSROOT}/usr/lib" && \
    mkdir -pv "${SYSROOT}/usr/libexec" && \
    mkdir -pv "${SYSROOT}/usr/bin" && \
    mkdir -pv "${SYSROOT}/usr/sbin" && \
    ln -sfv usr/bin "${SYSROOT}/bin" && \
    ln -sfv usr/sbin "${SYSROOT}/sbin" && \
    ln -sfv usr/lib "${SYSROOT}/lib" && \
    ln -sfv usr/lib "${SYSROOT}/libexec" && \
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
ENV AR=llvm-ar
ENV AS="clang -c"
ENV RANLIB=llvm-ranlib
ENV LD=ld.lld
# can't use -Wl,--dynamic-linker=/lib/ld-musl-x86_64.so.1 yet
ENV LDFLAGS="-fuse-ld=lld -Wl,--sysroot=/sysroot"
# epoch is passed through by Docker.
# shellcheck disable=SC2154
ARG SOME_DATE_EPOCH
ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

# copy sources (for musl headers)
COPY --from=fetcher /fetch/musl /build/musl
# copy headers to $SYSROOT
COPY --from=linux-trampoline /build/linux/usr/include /sysroot/usr/include
# copy llvm sources (for compiler_rt)
COPY --from=fetcher /fetch/llvmorg /build/llvm


# --- Prepare Stage: prepare musl sysroot with headers ---
WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
    CC=clang CFLAGS="${CFLAGS} -stdlib=libc++ -rtlib=compiler-rt -fno-math-errno -fPIC -fno-common" AR=llvm-ar LDFLAGS="${LDFLAGS}" && \
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
RUN set -eux \
    && apk add --no-cache \
        cmd:ninja \
        cmd:clang++ \
        cmake \
        pkgconfig \
        zlib-dev \
        cmd:find


# --- Precompile CC Stage0: prepare musl sysroot with clang builtins for TARGET_TRIPLE ---
RUN cmake -S compiler-rt -B build-compiler-rt -G "Ninja" \
      -DCMAKE_INSTALL_PREFIX="${SYSROOT}${MUSL_PREFIX}" \
      -DLLVM_CMAKE_DIR=/build/llvm/llvm \
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
      -DCMAKE_C_FLAGS="-D_XOPEN_SOURCE=700" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSROOT="${SYSROOT}" && \
      cmake --build build-compiler-rt && \
      cmake --install build-compiler-rt && \
      rm -rfv build-compiler-rt

RUN set -eux \
    && apk del --no-cache \
        cmd:ninja \
        cmake \
        pkgconfig \
        zlib-dev

# Ensure we have the clang builtins lib
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/linux/ || true


# --- runtime Trampoline Stage: compile musl sysroot with compiler_rt ---
WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN ./configure --prefix=${MUSL_PREFIX} --target=${TARGET_TRIPLE} \
      --enable-wrapper=clang \
      CC=clang \
      AR=llvm-ar RANLIB=llvm-ranlib \
      LDFLAGS="${LDFLAGS}" \
      LIBCC="-l${SYSROOT}/lib/linux/${LLVM_RTLIB}" \
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

# Ensure loader has canonical name (example: /lib/ld-musl-x86_64.so.1)
RUN set -eux \
    && ln -fns /lib/libc.so "${SYSROOT}/lib/${MUSL_LDLIB}" \
    && ln -fns "/lib/${MUSL_LDLIB}" "${SYSROOT}/lib/ld-musl.so.1"

# touch artifacts to make more reproducible (optional)
RUN find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.so" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.o" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/lib -type f -name "*.a" -exec touch -d "${SOME_DATE_EPOCH}" {} + || true; \
    find ${SYSROOT}${MUSL_PREFIX}/include -type f -exec touch -d "${SOME_DATE_EPOCH}" {} + || true;

# Ensure we have the dynamic loader and libs present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/lib || true && \
    file ${SYSROOT}${MUSL_PREFIX}/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/include || true && \
    file ${SYSROOT}${MUSL_PREFIX}/include/* || true

# --- bootstrap: bootstrap environment using distro clang/llvm to compile a minimal clang toolchain ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS bootstrap

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg
COPY --from=sysroot /sysroot /sysroot

ARG MUSL_LDLIB
ENV MUSL_LDLIB="${MUSL_LDLIB}"

ARG LLVM_RTLIB
ENV LLVM_RTLIB="${LLVM_RTLIB}"

ARG TARGET_FOR_LLVM
ENV TARGET_FOR_LLVM=${TARGET_FOR_LLVM}

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV AS="clang -c"
ENV RANLIB=llvm-ranlib
ENV LD=ld.lld

ENV SYSROOT="/sysroot"

# may need -Wl,--sysroot=/sysroot
# may need -Wl,--dynamic-linker=/lib/libc.so
ENV LDFLAGS="-Wl,--sysroot=/sysroot -Wl,-L,/usr/lib -Wl,-L,/lib -Wl,-L,/usr/lib/linux -Wl,--unique -Wl,--dynamic-linker=/lib/${MUSL_LDLIB} -fuse-ld=lld"
ENV CFLAGS="-rtlib=compiler-rt -fPIC -D__linux__ -D_BSD_SOURCE -D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -I${SYSROOT}/usr/include -I/usr/include"
ENV CXXFLAGS="-rtlib=compiler-rt -fPIC -D_LIBUNWIND_USE_DLADDR=0 -DSANITIZER_CAN_USE_PREINIT_ARRAY=0"

# Install distro packages that provide clang able to cross-emit --target. Adjust names for Alpine tag.
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add --no-cache \
    cmd:bash \
    cmd:dash \
    clang \
    llvm \
    lld \
    libc++ \
    libc++-dev \
    compiler-rt \
    cmd:llvm-ar \
    llvm-runtimes \
    cmake \
    ninja-build \
    cmd:ninja \
    pkgconfig \
    cmd:clang-cpp \
    cmd:clang++ \
    cmd:g++

#    cmd:llvm-otool \
#    cmd:llvm-nm \
#    cmd:llvm-strip \

#ENV LIBCC="${SYSROOT}/lib/linux/${LLVM_RTLIB}"

WORKDIR /bootstrap/llvmorg

# might need LDFLAGS="-Wl,--exclude-libs,libssp_nonshared.a"
# also might need -DCMAKE_C_FLAGS="-fno-stack-protector" -DCMAKE_CXX_FLAGS="-fno-stack-protector"
# also might need -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE
# may want unused -DLIBUNWIND_HAS_MUSL_LIBC=ON and -DLIBUNWIND_HAS_C_LIB=ON
# may want unused -DLIBUNWIND_TARGET_TRIPLE=${TARGET_TRIPLE}

# Build minimal clang (install to sysroot)
RUN cmake -S runtimes -B build-libunwind -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm \
    -DClang_DIR=/bootstrap/llvmorg/clang \
    -DLLVM_ENABLE_RUNTIMES="libunwind" \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBUNWIND_HAS_NODEFAULTLIBS_FLAG=OFF \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
    -DLIBUNWIND_HAS_DL_LIB=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_LINKER=ld.lld && \
    apk del --no-cache \
        g++ \
        cmd:g++ && \
    cmake --build build-libunwind && \
    cmake --install build-libunwind && \
    rm -vfr /bootstrap/llvmorg/build-libunwind/

# check on the lib
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/linux/ || true

# cmake thinks that clang++ requires g++
RUN apk add --no-cache \
    cmd:g++
# but we remove it anyway afterwards

ENV CXXFLAGS="-stdlib=libc++ -rtlib=compiler-rt -fPIC -DSANITIZER_CAN_USE_PREINIT_ARRAY=0 -D__linux__ -D_BSD_SOURCE -D_XOPEN_SOURCE=700 -D_POSIX_C_SOURCE=200809L"

# might need -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm
# might need -DLIBCXX_HAS_ATOMIC_LIB=OFF ??
# might need -DLIBCXX_HAS_C_LIB=ON
# might need -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=false
# might need -DLIBCXX_HAS_RT_LIB=ON
# might need -DLLVM_ENABLE_ZSTD=OFF
# might need -DLLVM_ENABLE_ZLIB=OFF
# might need -DLIBCXXABI_HAS_PTHREAD_API=ON
# might need -DLIBCXXABI_BAREMETAL=ON
# might want -DLIBCXX_ENABLE_THREADS=ON
# might need -DLIBCXXABI_ENABLE_THREADS=ON
# might need -DLIBCXXABI_HAS_PTHREAD_LIB=ON
# might want -DLIBCXX_HAS_PTHREAD_LIB=ON
# might want -DLIBCXXABI_HAS_PTHREAD_API=ON
# might need -DLIBCXXABI_BAREMETAL=ON
# might want -DCMAKE_SYSTEM_NAME=Linux
# might want -DCMAKE_SYSROOT="${SYSROOT}"
# might want unused -DLIBCXXABI_TARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DLIBCXX_TARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DTARGET_TRIPLE=${TARGET_TRIPLE}
# might want unused -DHOST_TRIPLE=${HOST_TRIPLE}

# might want -fdebug-prefix-map=/include=${SYSROOT}/usr/include


# Build minimal clang (install to sysroot)
RUN cmake -S runtimes -B build-runtimes -Wno-dev -G "Ninja" \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm \
    -DLLVM_ENABLE_RUNTIMES="libcxxabi;libcxx" \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXXABI_HAS_C_LIB=ON \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_HAS_MUSL_LIBC=ON \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXX_HARDENING_MODE=extensive \
    -DLLVM_HOST_TRIPLE=${HOST_TRIPLE} \
    -DLLVM_DEFAULT_TARGET_TRIPLE=${HOST_TRIPLE} \
    -DCMAKE_ASM_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_C_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DCMAKE_CXX_COMPILER_TARGET=${TARGET_TRIPLE} \
    -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" \
    -DCMAKE_C_FLAGS="${CFLAGS} -Qunused-arguments" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -Qunused-arguments -Wl,--verbose" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_LINKER=ld.lld \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSROOT="${SYSROOT}" && \
    cmake --build build-runtimes && \
    cmake --install build-runtimes && \
    rm -vfr /bootstrap/llvmorg/build-runtimes/ && \
        apk del --no-cache \
        g++ \
        cmd:g++

# Ensure we have the dynamic loader and libs present (sysroot paths)
RUN ls -l ${SYSROOT}${MUSL_PREFIX}/lib || true \
    && file ${SYSROOT}/usr/lib/* || true

# Ensure we have the libc headers present (sysroot paths)
RUN ls -l ${SYSROOT}/usr/include || true \
    && file ${SYSROOT}/usr/include/* || true

# Build minimal clang (install to stsroot)
RUN cmake -S llvm -B build-llvm -G "Ninja" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${SYSROOT}/usr" \
    -DLLVM_CMAKE_DIR=/bootstrap/llvmorg/llvm \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSROOT="${SYSROOT}" \
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
RUN ls -lap ${SYSROOT}/lib/ && ls -lap ${SYSROOT}/lib/linux/ || true

RUN find ${SYSROOT} -type f -iname "*.so" 2>/dev/null || true
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
ARG MUSL_VERSION=${MUSL_VERSION:-"1.2.5"}
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
    ninja-build \
    cmd:ninja \
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
    ln -sf /usr/include/'c++' /sysroot/usr/include/'c++' && \
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
    /sysroot/usr/include/'c++' \
    /usr/include/'c++' \
    /sysroot/usr/include/'c++'/./ ; do \
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

LABEL version="20250924"
LABEL org.opencontainers.image.title="llvm-alpine-musl"
LABEL org.opencontainers.image.description="Hermetically built llvm-alpine-musl."
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="MIT"

# provenance ENV (kept intentionally)
ARG LLVM_VERSION=${LLVM_VERSION:-"21.1.5"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

COPY --from=runtimes-build /sysroot /
