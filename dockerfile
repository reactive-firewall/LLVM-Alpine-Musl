# syntax=docker/dockerfile:1

# ---- fetcher stage: install and cache required Alpine packages and fetch release tarballs ----

# Use MIT licensed Alpine as the base image for the build environment
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS fetcher

# Set environment variables
ARG LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION:-"1.3"}
ENV LIBEXECINFO_VERSION=${LIBEXECINFO_VERSION}
ENV LIBEXECINFO_URL="https://github.com/reactive-firewall/libexecinfo/raw/refs/tags/v${LIBEXECINFO_VERSION}/libexecinfo-${LIBEXECINFO_VERSION}r.tar.bz2"
ARG LLVM_VERSION=${LLVM_VERSION:-"21.1.1"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
WORKDIR /fetch
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
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

# --- bootstrap: bootstrap environment using distro clang/llvm to compile a minimal clang toolchain ---
FROM --platform="linux/${TARGETARCH}" alpine:latest AS bootstrap

WORKDIR /bootstrap

# copy sources
COPY --from=fetcher /fetch/llvmorg /bootstrap/llvmorg

ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}

ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

# Install distro packages that provide clang able to cross-emit --target. Adjust names for Alpine tag.
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked --network=default \
  apk update && \
  apk add \
    cmd:bash \
    build-base \
    cmd:dash \
    clang20 \
    cmd:clang \
    lld \
    llvm \
    cmd:lld \
    llvm-dev \
    cmake \
    python3 \
    ninja-build \
    cmd:ninja \
    cmd:clang++-20 \
    cmd:clang++ \
    musl-dev \
    pkgconfig \
    zlib-dev

#    cmd:llvm-ar \
#    cmd:llvm-otool \
#    cmd:llvm-nm \
#    cmd:llvm-strip \
#    llvm-runtimes

# Build minimal LLVM (install to /opt/llvm-bootstrap)
RUN mkdir -p /bootstrap/llvm-build && cd /bootstrap/llvmorg/llvm && \
    cmake -S . -B /bootstrap/llvm-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/llvm-bootstrap \
      -DLLVM_ENABLE_PROJECTS="clang;lld" \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64" && \
    cmake --build /bootstrap/llvm-build --target install -j$(nproc)

ENV BOOTSTRAP_CLANG=/opt/llvm-bootstrap/bin/clang
ENV BOOTSTRAP_CLANGXX=/opt/llvm-bootstrap/bin/clang++
ENV PATH=/opt/llvm-bootstrap/bin:$PATH

# --- Stage 2: prepare musl sysroot for TARGET_TRIPLE ---
# shellcheck disable=SC2154
FROM --platform="linux/${TARGETARCH}" alpine:latest AS sysroot

# version is passed through by Docker.
# shellcheck disable=SC2154
ARG MUSL_VER=${MUSL_VER:-"1.2.5"}
ENV MUSL_VER=${MUSL_VER}
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
ENV MUSL_PREFIX="/staging"

RUN set -eux \
    && apk add --no-cache \
        cmd:bsdtar \
        clang \
        llvm \
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
    && mkdir -p /build

WORKDIR /build
ENV CC=clang
ENV AR=llvm-ar
ENV RANLIB=llvm-ranlib
ENV LD=ld.lld
ENV LDFLAGS="-fuse-ld=lld"
# epoch is passed through by Docker.
# shellcheck disable=SC2154
#ARG SOME_DATE_EPOCH
#ENV SOME_DATE_EPOCH=${SOME_DATE_EPOCH}

# Download musl
RUN curl -fsSL \
    --url "https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz" \
    -o musl-${MUSL_VER}.tar.gz && \
    bsdtar xf musl-${MUSL_VER}.tar.gz && \
    mv musl-${MUSL_VER} musl

WORKDIR /build/musl

# Configure, build, and install musl with shared enabled (default) using LLVM tools
RUN mkdir -p ${MUSL_PREFIX} && \
    ./configure --prefix=${MUSL_PREFIX} && \
    make CC=clang CFLAGS="${CFLAGS} -fno-math-errno -fPIC -fno-common" AR=llvm-ar LDFLAGS="${LDFLAGS}" -j"$(nproc)" && \
    make install

# Ensure we have the dynamic loader and libs present (example paths)
RUN ls -l ${MUSL_PREFIX}/lib || true \
    && file ${MUSL_PREFIX}/lib/* || true

#RUN touch -d ${SOME_DATE_EPOCH} ${MUSL_PREFIX}/lib/* || true \
#    && touch -d ${SOME_DATE_EPOCH} ${MUSL_PREFIX}/include/* || true

# Stage 3: build full LLVM runtimes using bootstrap compiler and toolchain file
FROM --platform=linux/${TARGETARCH} alpine:latest AS runtimes-build
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}
ENV MUSL_PREFIX="/staging"
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
    cmd:lld
# Copy bootstrap compiler and sources
COPY --from=bootstrap /opt/llvm-bootstrap /opt/llvm-bootstrap
COPY --from=fetcher /fetch/llvmorg /build/llvmorg
# Copy musl runtime artifacts from builder:
# - dynamic loader (ld-musl-*.so.1)
# - libmusl shared object(s) (libc.so.*)
# - crt*.o (for static linking if needed)
# - headers
COPY --from=sysroot ${MUSL_PREFIX}/lib/ld-musl-*.so.* /sysroot/lib/
COPY --from=sysroot ${MUSL_PREFIX}/lib/crt*.o /sysroot/lib/
COPY --from=sysroot ${MUSL_PREFIX}/lib/libc.so* /sysroot/usr/lib/
COPY --from=sysroot ${MUSL_PREFIX}/include /sysroot/usr/include

# Copy the toolchain file into the image
COPY llvm-musl-toolchain.cmake /build/llvm-musl-toolchain.cmake
# Build runtimes using the toolchain file
RUN cmake -S /build/llvmorg/llvm -B /build/llvm-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/llvm-final \
    -DCMAKE_TOOLCHAIN_FILE=/build/llvm-musl-toolchain.cmake \
    -DTARGET_TRIPLE=${TARGET_TRIPLE} \
    -DHOST_TRIPLE=${HOST_TRIPLE} \
    -DSYSROOT=/sysroot \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" && \
    cmake --build /build/llvm-build --target install-runtimes -j$(nproc)

## DEBUG CODE

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

## END DEBUG CODE

# ---- final stage: artifact only ----
# Final artifact stage: copy llvm-alpine-musl
FROM scratch AS llvm-alpine-musl

LABEL version="20250924"
LABEL org.opencontainers.image.title="llvm-alpine-musl"
LABEL org.opencontainers.image.description="Hermetically built llvm-alpine-musl."
LABEL org.opencontainers.image.vendor="individual"
LABEL org.opencontainers.image.licenses="MIT"

# provenance ENV (kept intentionally)
ARG LLVM_VERSION=${LLVM_VERSION:-"21.1.1"}
ENV LLVM_VERSION=${LLVM_VERSION}
ENV LLVM_URL="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz"
ARG TARGET_TRIPLE
ENV TARGET_TRIPLE=${TARGET_TRIPLE}
ARG HOST_TRIPLE
ENV HOST_TRIPLE=${HOST_TRIPLE:-${TARGET_TRIPLE}}

COPY --from=runtimes-build /sysroot /
