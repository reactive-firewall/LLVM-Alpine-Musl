# llvm-musl-toolchain.cmake
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=llvm-musl-toolchain.cmake -DTARGET_TRIPLE=... -DSYSROOT=/path/to/sysroot ...

include(Platform/Generic)

set(LIBCXX_INCLUDE_DIR "${CMAKE_SYSROOT}/usr/include/c++/v1")
if(EXISTS "${LIBCXX_INCLUDE_DIR}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -I${LIBCXX_INCLUDE_DIR}" CACHE STRING "" FORCE)
endif()

message(STATUS "TARGET_TRIPLE from CMake: ${TARGET_TRIPLE}")
if(NOT DEFINED TARGET_TRIPLE)
  message(FATAL_ERROR "TARGET_TRIPLE must be defined (e.g. x86_64-unknown-none-musl)")
endif()

message(STATUS "SYSROOT from CMake: ${SYSROOT}")
if(NOT DEFINED SYSROOT)
  message(FATAL_ERROR "SYSROOT must be defined and point to a musl sysroot with headers and libraries")
endif()

# Minimal variables consumed by LLVM build for cross-target runtimes
set(CMAKE_SYSTEM_NAME Generic CACHE STRING "Target system")
string(REGEX MATCH "^[^-]+" TARGET_ARCH ${TARGET_TRIPLE})
set(CMAKE_SYSTEM_PROCESSOR ${TARGET_ARCH} CACHE STRING "Target architecture")
set(CMAKE_SYSROOT ${SYSROOT} CACHE PATH "Target sysroot")
message(STATUS "CMAKE_SYSTEM_PROCESSOR from CMake: ${CMAKE_SYSTEM_PROCESSOR}")

if(NOT DEFINED CMAKE_INSTALL_LIBDIR)
  set(CMAKE_INSTALL_LIBDIR lib CACHE PATH "Library")
endif()
message(STATUS "CMAKE_INSTALL_LIBDIR from CMake: ${CMAKE_INSTALL_LIBDIR}")


# Use explicit compiler wrappers that add --target and --sysroot flags.
# Expect BOOTSTRAP_CLANG and BOOTSTRAP_CLANGXX either set externally or fallback to clang/clang++.
if(NOT DEFINED BOOTSTRAP_CLANG)
  set(BOOTSTRAP_CLANG clang)
endif()
if(NOT DEFINED BOOTSTRAP_CLANGXX)
  set(BOOTSTRAP_CLANGXX clang++)
endif()

# Helper function to produce canonical -target flag from TARGET_TRIPLE
set(TARGET_FLAG "--target=${TARGET_TRIPLE}")

# Compiler programs: wrap bootstrap clang to pass --target and --sysroot.
# CMake will call these as compilers. We provide wrapper scripts under CMAKE_BINARY_DIR if needed.
# Prefer using direct commands with -fuse-ld=lld to ensure lld linking.
set(CMAKE_C_COMPILER "${BOOTSTRAP_CLANG}" CACHE FILEPATH "Bootstrap clang")
set(CMAKE_CXX_COMPILER "${BOOTSTRAP_CLANGXX}" CACHE FILEPATH "Bootstrap clang++")

# Force compile flags for target triple and sysroot
set(CMAKE_C_FLAGS_INIT     "${TARGET_FLAG} --sysroot=${CMAKE_SYSROOT} -fPIC -fuse-ld=lld")
set(CMAKE_CXX_FLAGS_INIT   "${TARGET_FLAG} --sysroot=${CMAKE_SYSROOT} -fPIC -fuse-ld=lld")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${TARGET_FLAG} --sysroot=${CMAKE_SYSROOT} -fuse-ld=lld")

# Ensure position independent code where appropriate (runtimes expect static linking often)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Runtimes tend to require static builds; let caller override if needed
if(NOT DEFINED LLVM_ENABLE_RUNTIMES)
  set(LLVM_ENABLE_RUNTIMES "libcxx;libcxxabi;libunwind" CACHE STRING "")
endif()

# Tell LLVM build it's a cross-compile: host triple vs target triple
if(DEFINED HOST_TRIPLE)
  set(LLVM_HOST_TRIPLE "${HOST_TRIPLE}" CACHE STRING "Host triple for LLVM build")
else()
  # Try to infer host triple using uname-like fallback; caller should set HOST_TRIPLE explicitly.
  message(WARNING "HOST_TRIPLE not set; some cross-build logic may require explicit HOST_TRIPLE.")
endif()

# Make sure to find LLVM tools if available in PATH (bootstrap clang must be usable)
find_program(BOOTSTRAP_CLANG_PATH ${BOOTSTRAP_CLANG})
if(NOT BOOTSTRAP_CLANG_PATH)
  message(FATAL_ERROR "Bootstrap clang not found: ${BOOTSTRAP_CLANG}")
endif()

# Provide canonical flags expected by LLVM's CMake
set(CMAKE_C_COMPILER_FORCED TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)

# Disable features that require native target support at configure time
set(LLVM_ENABLE_THREADS OFF CACHE BOOL "" FORCE)
set(LLVM_ENABLE_Z3_SOLVER OFF CACHE BOOL "" FORCE)
set(LLVM_ENABLE_BINDINGS OFF CACHE BOOL "" FORCE)
set(LLVM_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLVM_INCLUDE_TESTS OFF CACHE BOOL "" FORCE)

# Configure libc++ specifics for musl
set(LIBCXX_HAS_MUSL_LIBC ON CACHE BOOL "")
set(LIBCXX_ENABLE_SHARED OFF CACHE BOOL "")
set(LIBCXX_ENABLE_STATIC ON CACHE BOOL "")
set(LIBCXX_ENABLE_EXCEPTIONS ON CACHE BOOL "")

# Use the bootstrap clang for assembler and linker invocation overrides when needed
set(CMAKE_ASM_COMPILER ${BOOTSTRAP_CLANG} CACHE FILEPATH "ASM compiler")
set(CMAKE_LINKER lld CACHE FILEPATH "Linker (lld)")

# Export target-specific defines to compile-time
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS_INIT} ${CMAKE_C_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS_INIT} ${CMAKE_CXX_FLAGS}" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS_INIT} ${CMAKE_EXE_LINKER_FLAGS}" CACHE STRING "" FORCE)

# Ensure pkg-config uses sysroot (optional)
set(ENV{PKG_CONFIG_SYSROOT_DIR} ${CMAKE_SYSROOT})

# Provide helpful summary
message(STATUS "Configured cross build: TARGET_TRIPLE=${TARGET_TRIPLE} SYSROOT=${CMAKE_SYSROOT}")
message(STATUS "Bootstrap compilers: ${CMAKE_C_COMPILER} ${CMAKE_CXX_COMPILER}")
