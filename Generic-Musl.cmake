# Generic-Musl.cmake
# Platform file for System-V style embedded targets using musl libc and Clang/LLVM.
# Use: -DCMAKE_SYSTEM_NAME=Generic-Musl -DCMAKE_C_COMPILER=... -DCMAKE_CXX_COMPILER=...

# To help the find_xxx() commands, set at least the following so CMAKE_FIND_ROOT_PATH
# works at least for some simple cases:
set(CMAKE_SYSTEM_INCLUDE_PATH /include )
set(CMAKE_SYSTEM_LIBRARY_PATH /lib )
set(CMAKE_SYSTEM_PROGRAM_PATH /bin )

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

set(UNIX 1)
include(Platform/UnixPaths)

# musl dos not care about .exe nor .elf (and does not support .app)
# set(CMAKE_EXECUTABLE_SUFFIX "")
set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".so")
set(CMAKE_SHARED_MODULE_SUFFIX ".so")
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Position independent code for shared libs" FORCE)

if(CMAKE_C_COMPILER_ID MATCHES "GNU")
  message(FATAL_ERROR "Generic-Musl platform can not be used with GNU toolchains.")
endif()

set(_GENERIC_MUSL_HAVE_CLANG OFF)
if(CMAKE_C_COMPILER_ID MATCHES "Clang" OR CMAKE_C_COMPILER_ID MATCHES "AppleClang")
  set(_GENERIC_MUSL_HAVE_CLANG ON)
endif()

# Infer C++ driver if plausible
if(_GENERIC_MUSL_HAVE_CLANG)
  if(NOT DEFINED CMAKE_CXX_COMPILER)
    if(DEFINED ENV{CXX})
      set(CMAKE_CXX_COMPILER "$ENV{CXX}" CACHE STRING "Environment C++ compiler" FORCE)
    else()
      get_filename_component(_cbin "${CMAKE_C_COMPILER}" NAME_WE)
      if(_cbin MATCHES "clang$")
        set(CMAKE_CXX_COMPILER "${CMAKE_C_COMPILER}++" CACHE FILEPATH "Inferred clang++" FORCE)
      endif()
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
  "${CMAKE_INSTALL_PREFIX}/lib/libc.so"
  "/lib/libc.so"
  "/usr/lib/libc.so"
)

# search must have set libc_path to the path of musl libc.so (or empty if not detecting musl)
if(NOT DEFINED libc_path)
  set(libc_path "")
endif()

foreach(_c IN LISTS _libc_candidates)
  if(EXISTS "${_c}")
    set(libc_path "${_c}")
    # try to guess loader name in same dir: ld-musl-*.so.1
    get_filename_component(_c_dir "${_c}" DIRECTORY)
    file(GLOB _ldcandidates "${_c_dir}/ld-musl-*.so.1")
    if(_ldcandidates)
      list(GET _ldcandidates 0 _musl_loader)
    endif()
    break()
  endif()
endforeach()

# check for c99 compliance of detected libc.so
# Preserve any existing known features
set(_known_features "${CMAKE_C_KNOWN_FEATURES}")

if(libc_path)
  # If musl libc is present, assume at least C99 support and probe related features.
  list(APPEND _known_features "c_std_99")

  # Helper macro: try_compile a small snippet, optionally adding -D flags for feature test macros
  macro(_probe_feature feature_name code)
    set(_probe_src "${CMAKE_BINARY_DIR}/cmake_probe_${feature_name}.c")
    file(WRITE "${_probe_src}" "${code}\n")
    try_compile(_res
      "${CMAKE_BINARY_DIR}"                 # BIN dir for try_compile
      "${_probe_src}"
      CMAKE_FLAGS
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}
      OUTPUT_VARIABLE _out
      LANGUAGE C
    )
    if(_res)
      list(APPEND _known_features "${feature_name}")
    endif()
  endmacro()

  # Probe: function prototypes (C89/90 prototypes supported in C99+)
  _probe_feature("c_function_prototypes"
"#if defined(__STDC__)
  /* ensure stdc is enabled */
#endif
int f(int a); /* prototype */
int f(int a) { return a+1; }
int main(void) { return f(1) - 2; }")

  # Probe: restrict keyword (C99)
  _probe_feature("c_restrict"
"#ifndef restrict
  /* allow compilers that use __restrict */
  #define restrict restrict
#endif
int fn(int * restrict p) { return p ? *p : 0; }
int main(void) { int x = 0; return fn(&x); }")

  # Probe: variadic macros (C99)
  _probe_feature("c_variadic_macros"
"#define TEST(fmt, ...) fmt \"\\n\"
int main(void) { (void)TEST(\"x\", 1); return 0; }")

endif()

# Remove duplicates and set cached variable
list(REMOVE_DUPLICATES _known_features)
set(CMAKE_C_KNOWN_FEATURES "${_known_features}" CACHE STRING "Detected C known features" FORCE)
message(STATUS "C known features: ${CMAKE_C_KNOWN_FEATURES}")

# this option needs more testing
#set(CMAKE_DL_LIBS "") # or static libdl.a stub
# support position independance
set(CMAKE_C_COMPILE_OPTIONS_PIC "-fPIC")
set(CMAKE_C_COMPILE_OPTIONS_PIE "-fPIE")

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
    set(_CMAKE_SYSTEM_LINKER_TYPE LLD CACHE INTERNAL "System linker type")
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
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=lld")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fuse-ld=lld")
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
  # (musl) support shared libraries
  set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)

  # PIE link options are managed in Compiler/<compiler>.cmake file
  set(CMAKE_SHARED_LIBRARY_C_FLAGS "-fPIC")            # -pic
  set(CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS "-shared")       # -shared
  set(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "")         # +s, flag for exe link to use shared lib

  # Not sure if rpaths are used by musl (ld-musl-ARCH.so.1 is hardcoded when linking to musl)
  set(CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG "-Wl,-rpath,")       # -rpath
  # probably works like FreeBSD
  # set(CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG_SEP ":")   # : or empty
  # Not sure about -z origin with musl
  #set(CMAKE_SHARED_LIBRARY_RPATH_ORIGIN_TOKEN "\$ORIGIN")
  set(CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG "-Wl,-rpath-link,")
  set(CMAKE_SHARED_LIBRARY_SONAME_C_FLAG "-Wl,-soname,")
  set(CMAKE_EXE_EXPORTS_C_FLAG "-Wl,--export-dynamic")

  # Shared libraries with no builtin soname may not be linked safely by
  # specifying the file path.
  set(CMAKE_PLATFORM_USES_PATH_WHEN_NO_SONAME 1)

  # Initialize C link type selection flags.  These flags are used when
  # building a shared library, shared module, or executable that links
  # to other libraries to select whether to use the static or shared
  # versions of the libraries.
  foreach(type SHARED_LIBRARY SHARED_MODULE EXE)
    set(CMAKE_${type}_LINK_STATIC_C_FLAGS "-Wl,-Bstatic")
    set(CMAKE_${type}_LINK_DYNAMIC_C_FLAGS "-Wl,-Bdynamic")
  endforeach()

  include(Platform/Linker/Generic-Musl-Linker.cmake)
  if(_GENERIC_MUSL_HAVE_CLANG)
    __musl_linker_clang(C)
    __musl_linker_clang(CXX)
  endif()
else()
  if(DEFINED _musl_loader)
    message(STATUS "Detected musl dynamic loader: ${_musl_loader}")
  else()
    message(STATUS "Musl dynamic loader not auto-detected!")
  endif()
  if(DEFINED CMAKE_LINKER)
    message(STATUS "Detected dynamic linker id: ${CMAKE_LINKER}")
  else()
    message(STATUS "Dynamic linker id not auto-detected! ; set -DCMAKE_LINKER=/path/to/linker to override.")
  endif()
  message(STATUS "Shared libraries disabled (missing musl loader or suitable linker).")
  # (musl) targets without hardcoded linkers don't support shared libraries
  set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS FALSE)
endif()

# CMP0164: add_library() rejects SHARED libraries when not supported by the platform.
# New in CMake 3.30: https://cmake.org/cmake/help/latest/policy/CMP0164.html
if(POLICY CMP0164)
  cmake_policy(SET CMP0164 NEW)
endif()
