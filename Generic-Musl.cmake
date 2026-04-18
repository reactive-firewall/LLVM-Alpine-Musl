# Generic-Musl.cmake
# Platform file for System-V style embedded targets using musl libc and Clang/LLVM.
# Use: -DCMAKE_SYSTEM_NAME=Generic-Musl -DCMAKE_C_COMPILER=... -DCMAKE_CXX_COMPILER=...

include(Platform/Generic)

set(CMAKE_SYSTEM_NAME "Generic" CACHE STRING "Target system")
set(CMAKE_SYSTEM_VERSION 1)

# Provide a SYSROOT fallback from env if still not set
if(NOT DEFINED SYSROOT OR SYSROOT STREQUAL "")
  if(DEFINED ENV{SYSROOT})
    set(SYSROOT "$ENV{SYSROOT}" CACHE PATH "Target sysroot" FORCE)
  endif()
endif()

if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "")
endif()

include(Platform/UNIX_SV-Initialize)
include(Platform/UnixPaths)

set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".so")
set(CMAKE_SHARED_MODULE_SUFFIX ".so")
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Position independent code for shared libs" FORCE)

if(CMAKE_C_COMPILER_ID MATCHES "GNU")
  message(FATAL_ERROR "Generic-Musl platform must not be used with GNU toolchains.")
endif()

set(_GENERIC_MUSL_HAVE_CLANG OFF)
if(CMAKE_C_COMPILER_ID MATCHES "Clang" OR CMAKE_C_COMPILER_ID MATCHES "AppleClang")
  set(_GENERIC_MUSL_HAVE_CLANG ON)
endif()

# Infer C++ driver if plausible
if(_GENERIC_MUSL_HAVE_CLANG)
  if(NOT DEFINED CMAKE_CXX_COMPILER)
    get_filename_component(_cbin "${CMAKE_C_COMPILER}" NAME_WE)
    if(_cbin MATCHES "clang$")
      set(CMAKE_CXX_COMPILER "${CMAKE_C_COMPILER}++" CACHE FILEPATH "Inferred clang++" FORCE)
    endif()
  endif()
endif()

# Try to locate libclang_rt.builtins*.a (common locations + /{usr/}lib/generic)
if(NOT DEFINED CLANG_RT_PATH AND _GENERIC_MUSL_HAVE_CLANG)
  get_filename_component(_clang_bin_dir "${CMAKE_C_COMPILER}" DIRECTORY)
  get_filename_component(_clang_parent_dir "${_clang_bin_dir}" PATH)
  set(_try_paths
    "${CMAKE_SYSROOT}/lib/generic"
    "${CMAKE_INSTALL_PREFIX}/lib/generic"
    "/lib/generic"
    "/usr/lib/generic"
    "${_clang_parent_dir}/lib/clang"
    "${_clang_parent_dir}/lib64/clang"
    "${_clang_parent_dir}/../lib/clang"
    "/usr/lib/clang"
    "/usr/lib64/clang"
    "${CMAKE_SYSROOT}/usr/lib/clang"
  )
  foreach(_p IN LISTS _try_paths)
    if(EXISTS "${_p}")
      file(GLOB _builtins_glob "${_p}/libclang_rt.builtins*.a" "${_p}/*/libclang_rt.builtins*.a")
      if(_builtins_glob)
        list(GET _builtins_glob 0 _first_builtins)
        set(CLANG_RT_PATH "${_first_builtins}" CACHE PATH "Path to libclang_rt.builtins.a")
        break()
      endif()
    endif()
  endforeach()
endif()

# Detect libc and musl dynamic linker presence for shared support
# Candidate libc paths relative to sysroot or absolute
set(_libc_candidates
  "${CMAKE_SYSROOT}/lib/libc.so"
  "${CMAKE_SYSROOT}/lib64/libc.so"
  "${CMAKE_INSTALL_PREFIX}/lib/libc.so"
  "${CMAKE_INSTALL_PREFIX}/lib64/libc.so"
  "/lib/libc.so"
  "/lib64/libc.so"
  "/usr/lib/libc.so"
)

set(_musl_loader "")

foreach(_c IN LISTS _libc_candidates)
  if(EXISTS "${_c}")
    set(libc_path "${_c}")
    # try to guess loader name in same dir: ld-musl-*.so
    get_filename_component(_c_dir "${_c}" DIRECTORY)
    file(GLOB _ldcandidates "${_c_dir}/ld-musl-*.so")
    if(_ldcandidates)
      list(GET _ldcandidates 0 _musl_loader)
    endif()
    break()
  endif()
endforeach()

# Detect libpthread / libm near libc
set(CMAKE_PLATFORM_HAS_PTHREADS OFF)
set(CMAKE_PLATFORM_HAS_MATH_LIB OFF)
if(_musl_loader)
  get_filename_component(_loader_dir "${_musl_loader}" DIRECTORY)
  # search sibling dirs (lib, lib64, usr/lib) for libpthread/libm
  set(_search_dirs
    "${loader_dir}"
    "${loader_dir}/.."
    "${CMAKE_SYSROOT}/lib"
    "${CMAKE_SYSROOT}/lib64"
    "${CMAKE_SYSROOT}/usr/lib"
    "${CMAKE_INSTALL_PREFIX}/lib"
    "${CMAKE_INSTALL_PREFIX}/lib64"
    "${CMAKE_INSTALL_PREFIX}/usr/lib"
  )
  foreach(_d IN LISTS _search_dirs)
    if(EXISTS "${_d}")
      file(GLOB _pthreads_candidates "${_d}/libpthread.*" "${_d}/libpthread.so" "${_d}/libpthread.a")
      if(_pthreads_candidates)
        set(CMAKE_PLATFORM_HAS_PTHREADS ON CACHE BOOL "Does the platform provide libpthreads")
      endif()
      file(GLOB _math_candidates "${_d}/libm.*" "${_d}/libm.so" "${_d}/libm.a")
      if(_math_candidates)
        set(CMAKE_PLATFORM_HAS_MATH_LIB ON CACHE BOOL "Does the platform provide libm (math)")
      endif()
    endif()
  endforeach()
else()
  # fallback: attempt to find libs relative to CMAKE_SYSROOT or /lib
  foreach(_d IN LISTS "${CMAKE_SYSROOT}/lib" "/lib" "/usr/lib")
    if(EXISTS "${_d}")
      file(GLOB _pthreads_candidates "${_d}/libpthread.*" "${_d}/libpthread.so" "${_d}/libpthread.a")
      if(_pthreads_candidates)
        set(CMAKE_PLATFORM_HAS_PTHREADS ON CACHE BOOL "Does the platform provide libpthreads")
      endif()
      file(GLOB _math_candidates "${_d}/libm.*" "${_d}/libm.so" "${_d}/libm.a")
      if(_math_candidates)
        set(CMAKE_PLATFORM_HAS_MATH_LIB ON CACHE BOOL "Does the platform provide libm (math)")
      endif()
    endif()
  endforeach()
endif()

# Detect available linkers (ld.lld, ld.clang, lld/llvm-lld as proxy)
find_program(LD_LLD ld.lld)
find_program(LD_CLANG ld.musl-clang)
find_program(LLVM_LLD llvm-lld)
find_program(LLD_LINK lld)  # generic lld

# Shared library support: require musl loader + a linker capable of producing shared libs
# set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS OFF)
if(_musl_loader)
  if(LD_LLD OR LD_CLANG OR LLD_LINK OR LLVM_LLD)
    set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS ON CACHE BOOL "Should the flag -shared be used" FORCE)
  else()
    if(NOT DEFINED CMAKE_LINKER)
      set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS OFF CACHE BOOL "Should the flag -shared be used")
    else()
      set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS ON CACHE BOOL "Should the flag -shared be used")
    endif()
  endif()
else()
  set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS OFF CACHE BOOL "Should the flag -shared be used")
endif()

# Shared linking flags when supported
if(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS AND _GENERIC_MUSL_HAVE_CLANG)
  set(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "-shared")
  set(CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS "-shared")
  set(CMAKE_SHARED_MODULE_LINK_C_FLAGS "-shared")
  set(CMAKE_SHARED_MODULE_LINK_CXX_FLAGS "-shared")

  # Prefer LLD where available
  if(LD_LLD OR LLD_LINK OR LLVM_LLD)
    set(_use_lld ON)
    if(LD_LLD)
      set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=ld.lld")
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fuse-ld=ld.lld")
    else()
      set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=lld")
      set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fuse-ld=lld")
    endif()
  endif()

  # Set dynamic linker path for musl
  if(_musl_loader)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--unique -Wl,--dynamic-linker=${_musl_loader}")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--unique -Wl,--dynamic-linker=${_musl_loader}")
  endif()

  # Conservative security flags
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,relro -Wl,-z,now")
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,relro -Wl,-z,now")
else()
  # Ensure shared lib variables don't advertise support
  set(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "")
  set(CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS "")
  set(CMAKE_SHARED_MODULE_LINK_C_FLAGS "")
  set(CMAKE_SHARED_MODULE_LINK_CXX_FLAGS "")
endif()

# Add clang_rt if found
if(DEFINED CLANG_RT_PATH AND EXISTS "${CLANG_RT_PATH}")
  list(FIND CMAKE_EXE_LINKER_FLAGS "${CLANG_RT_PATH}" _found_clang_rt)
  if(_found_clang_rt EQUAL -1)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${CLANG_RT_PATH}")
  endif()
  list(FIND CMAKE_SHARED_LINKER_FLAGS "${CLANG_RT_PATH}" _found_clang_rt2)
  if(_found_clang_rt2 EQUAL -1)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${CLANG_RT_PATH}")
  endif()
endif()

# Prefer llvm-ar/llvm-strip if present
find_program(LLVM_AR llvm-ar)
if(LLVM_AR)
  set(CMAKE_AR "${LLVM_AR} rc")
endif()
find_program(LLVM_AR llvm-ar)
if(LLVM_AR)
  set(CMAKE_RANLIB "${LLVM_RANLIB}")
endif()
find_program(LLVM_STRIP llvm-strip)
if(LLVM_STRIP)
  set(CMAKE_STRIP "${LLVM_STRIP}")
endif()

# Defaults and hints
set(CMAKE_SKIP_RPATH OFF)
set(CMAKE_PLATFORM_HAS_MATH_LIB ${CMAKE_PLATFORM_HAS_MATH_LIB})
set(CMAKE_PLATFORM_HAS_PTHREADS ${CMAKE_PLATFORM_HAS_PTHREADS})

message(STATUS "Configured Generic-Musl platform (musl libc, Clang/LLVM preferred).")
if(_GENERIC_MUSL_HAVE_CLANG)
  message(STATUS "Detected Clang compiler id: ${CMAKE_C_COMPILER_ID}")
  if(DEFINED CLANG_RT_PATH)
    message(STATUS "clang_rt builtins: ${CLANG_RT_PATH}")
  else()
    message(STATUS "clang_rt builtins not auto-detected; set -DCLANG_RT_PATH=/path/to/clang_rt.builtins.a to link it.")
  endif()
else()
  message(STATUS "No Clang detected; leaving most toolchain variables unchanged (GNU toolchains are forbidden).")
endif()

if(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS)
  message(STATUS "Shared libraries supported (musl loader and linker detected).")
else()
  message(STATUS "Shared libraries disabled (missing musl loader or suitable linker).")
endif()
