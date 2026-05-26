# Generic-Musl.cmake
# Platform file for System-V style embedded targets using musl libc and Clang/LLVM.
# Use: -DCMAKE_SYSTEM_NAME=Generic-Musl -DCMAKE_C_COMPILER=... -DCMAKE_CXX_COMPILER=...

set(CMAKE_SYSTEM_NAME "Generic" CACHE STRING "Target system")
set(CMAKE_SYSTEM_VERSION 1)

# Provide a CMAKE_SYSROOT fallback from env if still not set
if(NOT DEFINED CMAKE_SYSROOT OR CMAKE_SYSROOT STREQUAL "")
  if(DEFINED ENV{SYSROOT})
    set(CMAKE_SYSROOT "$ENV{SYSROOT}" CACHE PATH "Target sysroot" FORCE)
  endif()
else()
  set(CMAKE_SYSROOT "")
endif()

if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "")
endif()

set(_generic_musl_EXE_linker_flags_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")
set(_generic_musl_SHARED_linker_flags_INIT "${CMAKE_SHARED_LINKER_FLAGS_INIT}")

# To help the find_xxx() commands, set at least the following so CMAKE_FIND_ROOT_PATH
# works at least for some simple cases:
if(EXISTS "${CMAKE_SYSROOT}/bin")
  set(CMAKE_SYSTEM_PROGRAM_PATH "${CMAKE_SYSROOT}/bin")
endif()
if(EXISTS "${CMAKE_SYSROOT}/include")
  set(CMAKE_SYSTEM_INCLUDE_PATH "${CMAKE_SYSROOT}/include")
endif()
if(EXISTS "${CMAKE_SYSROOT}/usr/lib")
  set(CMAKE_SYSTEM_LIBRARY_PATH "${CMAKE_SYSROOT}/lib;${CMAKE_SYSROOT}/usr/lib" )
else()
  set(CMAKE_SYSTEM_LIBRARY_PATH "${CMAKE_SYSROOT}/lib")
endif()

set(LIBRARY_OUTPUT_PATH "${CMAKE_SYSROOT}/lib")

if(NOT DEFINED CMAKE_LIBRARY_OUTPUT_DIRECTORY)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SYSROOT}/lib")
endif()
if(NOT DEFINED EXECUTABLE_OUTPUT_PATH)
  if(EXISTS "${CMAKE_SYSROOT}/bin")
    set(EXECUTABLE_OUTPUT_PATH "${CMAKE_SYSROOT}/bin")
  endif()
endif()
if(NOT DEFINED CMAKE_RUNTIME_OUTPUT_DIRECTORY)
  if(EXISTS "${CMAKE_SYSROOT}/libexec")
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SYSROOT}/libexec")
  else()
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
  endif()
endif()
if(NOT DEFINED CMAKE_ARCHIVE_OUTPUT_DIRECTORY)
  set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_SYSROOT}/lib")
endif()


set(UNIX 1)
include(Platform/UnixPaths)

# musl does NOT need GNU extensions, but can leverage them when either one of
#  _GNU_SOURCE or _ALL_SOURCE is defined.
#  Treat compiler GNU extensions when _GNU_SOURCE or _ALL_SOURCE are defined
#  (set these variables so the rest of the toolchain can use them)
set(CMAKE_C_EXTENSIONS_DEFAULT OFF)
set(CMAKE_CXX_EXTENSIONS_DEFAULT OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU")
  message(FATAL_ERROR "Generic-Musl platform can not be used with GNU toolchains.")
endif()

set(_GENERIC_MUSL_HAVE_CLANG OFF)
if(CMAKE_C_COMPILER_ID MATCHES "Clang" OR CMAKE_C_COMPILER_ID MATCHES "AppleClang")
  set(_GENERIC_MUSL_HAVE_CLANG ON)
else()
  message(AUTHOR_WARNING "Unrecognized compiler ID: ${CMAKE_C_COMPILER_ID}")
  message(FATAL_ERROR "Generic-Musl platform can only be used with Clang toolchains at this time.")
endif()

# Also allow explicit option override
option(ENABLE_C_EXTENSIONS "Enable C GNU extensions" ${C_EXTENSIONS})
option(ENABLE_CXX_EXTENSIONS "Enable C++ GNU extensions" ${CXX_EXTENSIONS})
if(ENABLE_C_EXTENSIONS)
  add_compile_definitions(_GNU_SOURCE)
endif()
if(ENABLE_CXX_EXTENSIONS)
  add_compile_definitions(_GNU_SOURCE)
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
        set(CMAKE_CXX_COMPILER_ID "Clang")
      endif()
    endif()
  endif()
endif()

# Try to locate libclang_rt.builtins*.a (common locations + /{usr/}lib/generic)
if(NOT DEFINED CLANG_RT_PATH AND _GENERIC_MUSL_HAVE_CLANG)

  if(NOT DEFINED CMAKE_C_LIBRARY_ARCHITECTURE)
    set(CMAKE_C_LIBRARY_ARCHITECTURE "generic")
  endif()

  get_filename_component(_clang_bin_dir "${CMAKE_C_COMPILER}" DIRECTORY)
  get_filename_component(_clang_parent_dir "${_clang_bin_dir}" PATH)
  set(_try_paths
    "${CMAKE_SYSROOT}/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "${CMAKE_SYSROOT}/usr/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "${CMAKE_INSTALL_PREFIX}/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "${CMAKE_INSTALL_PREFIX}/usr/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "/usr/lib/${CMAKE_C_LIBRARY_ARCHITECTURE}"
    "${_clang_parent_dir}/lib/clang"
    "${_clang_parent_dir}/lib64/clang"
    "${_clang_parent_dir}/../lib/clang"
    "/usr/lib/clang"
    "/usr/lib64/clang"
  )
  foreach(_p IN LISTS _try_paths)
    if(EXISTS "${_p}")
      file(GLOB _builtins_glob "${_p}/libclang_rt.builtins*.a" "${_p}/*/libclang_rt.builtins*.a")
      if(_builtins_glob)
        list(GET _builtins_glob 0 _first_builtins)
        set(CLANG_RT_PATH "${_first_builtins}" CACHE PATH "Path to libclang_rt.builtins.a")
        if(EXISTS "$CLANG_RT_PATH")
          get_filename_component(basename "${_first_builtins}" NAME)
          string(REGEX MATCH "libclang_rt\\.builtins-(.*)\\.a$" _match "${basename}")  # capture group 1 = the '*' part (possibly empty)
          set(target_part "${CMAKE_MATCH_1}")                                        # empty string if no target
          set(COMPILER_RT_LIBRARY_builtins_${target_part} "${CLANG_RT_PATH}" CACHE INTERNAL "Compiler Runtime builtins (detected from libclang_rt)")
        endif()
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
  "${CMAKE_SYSROOT}/usr/lib/libc.so"
  "${CMAKE_INSTALL_PREFIX}/usr/lib/libc.so"
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
    # try to guess loader name in same dir: ld-musl-*.so.${CMAKE_SYSTEM_VERSION:-1}
    get_filename_component(_c_dir "${_c}" DIRECTORY)
    # only support v1 for musl
    file(GLOB _ldcandidates "${_c_dir}/ld-musl-*.so.1")
    list(LENGTH _ldcandidates _ld_count)
    if(_ld_count GREATER 0)
      list(GET _ldcandidates 0 _musl_loader)
      set(CMAKE_SYSTEM_LIBRARY_PATH "${_c_dir}")
    endif()
    break()
  endif()
endforeach()

# optional debug
message(VERBOSE "libc_path='${libc_path}' _musl_loader='${_musl_loader}'")

find_program(_llvm_objdump NAMES llvm-objdump)
find_program(_gnu_objdump NAMES objdump)
if(_llvm_objdump)
  set(CMAKE_OBJDUMP "${_llvm_objdump}")
elseif(ENABLE_C_EXTENSIONS AND _gnu_objdump)
  set(CMAKE_OBJDUMP "${_gnu_objdump}")
else()
  set(CMAKE_OBJDUMP "")
endif()

if(CMAKE_OBJDUMP AND EXISTS "${libc_path}")
  execute_process(
    COMMAND ${CMAKE_OBJDUMP} -p "${libc_path}"
    RESULT_VARIABLE _od_res
    OUTPUT_VARIABLE _od_out
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(_od_res EQUAL 0 AND _od_out)
    # Try to extract SONAME first (e.g. SONAME libc.so.1) or any "libc.so.<num>"
    string(REGEX MATCH "SONAME[[:space:]]+([^[:space:]]+)" _match "${_od_out}")
    if(_match)
      string(REGEX REPLACE "SONAME[[:space:]]+([^[:space:]]+)" "\\1" _ver_candidate "${_match}")
    else()
      # fallback: filename version like libc.so.1 or libc-<ver>.so
      get_filename_component(_fname "${libc_path}" NAME)
      string(REGEX MATCH "libc[^0-9]*([0-9]+(\\.[0-9]+)*)?" _fmatch "${_fname}")
      if(_fmatch)
        string(REGEX REPLACE "libc[^0-9]*([0-9]+(\\.[0-9]+)*)?" "\\1" _ver_candidate "${_fmatch}")
      endif()
    endif()

    if(_ver_candidate)
      # set the CMake cached vars only if not already set by user
      if(NOT DEFINED CMAKE_HOST_SYSTEM_VERSION)
        set(CMAKE_HOST_SYSTEM_VERSION "${_ver_candidate}" CACHE STRING "Host system version (detected from libc)" FORCE)
      endif()
      if(DEFINED CMAKE_SYSTEM_VERSION AND (CMAKE_SYSTEM_VERSION STREQUAL "1" OR NOT CMAKE_SYSTEM_VERSION))
        set(CMAKE_SYSTEM_VERSION "${_ver_candidate}" CACHE STRING "System version (detected from libc)" FORCE)
      endif()
    endif()
  endif()
endif()

# check for c99 compliance of detected libc.so
# Preserve any existing known features
set(_known_features "${CMAKE_C_KNOWN_FEATURES}")

if(libc_path)
  # Musl libc trys to be strict ISO 9899:1999 Aligned
  # If musl libc is present, assume at least C99 support and probe related features.
  list(APPEND _known_features "c_std_99")
  # function prototypes (C89/90 prototypes supported in C99+)
  list(APPEND _known_features "c_function_prototypes")
  # restrict keyword (C99)
  list(APPEND _known_features "c_restrict")
  # variadic macros (C99)
  list(APPEND _known_features "c_variadic_macros")
  # If musl libc is present, assume at least C11 support and probe related features.
  list(APPEND _known_features "c_std_11")

  # musl dos not care about .exe nor .elf (and does not support .app)
  # set(CMAKE_EXECUTABLE_SUFFIX "")
  set(CMAKE_EXECUTABLE_FORMAT "ELF" CACHE STRING "Executable format")
  set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")
  set(CMAKE_STATIC_LIBRARY_FORMAT "ELF" CACHE STRING "Static Library format")
  set(CMAKE_SHARED_LIBRARY_PREFIX "lib")
  set(CMAKE_SHARED_LIBRARY_SUFFIX ".so")
  set(CMAKE_EXTRA_SHARED_LIBRARY_SUFFIXES
    ".so.${CMAKE_SYSTEM_VERSION}"
    ".so.${CMAKE_SYSTEM_VERSION}.0"
    ".${CMAKE_SYSTEM_VERSION}.0.so"
    ".lib"
  )
  set(CMAKE_IMPORT_LIBRARY_SUFFIX "${CMAKE_SHARED_LIBRARY_SUFFIX}")
  set(CMAKE_SHARED_MODULE_SUFFIX ".so")

  # require PIC by default
  set(CMAKE_POSITION_INDEPENDENT_CODE TRUE)

  # musl does NOT need GNU extensions, but can leverage them when either one of
  #  _GNU_SOURCE or _ALL_SOURCE is defined.
  #  Treat compiler GNU extensions when _GNU_SOURCE or _ALL_SOURCE are defined
  #  (set these variables so the rest of the toolchain can use them)
  set(CMAKE_C_EXTENSIONS_DEFAULT OFF)
  set(CMAKE_CXX_EXTENSIONS_DEFAULT OFF)
  set(CMAKE_C_EXTENSIONS OFF) # musl in generic mode need not use extensions (so default to off)
endif()

# Remove duplicates and set cached variable
list(REMOVE_DUPLICATES _known_features)
set(CMAKE_C_KNOWN_FEATURES "${_known_features}" CACHE STRING "Detected C known features" FORCE)
message(VERBOSE "C known features: ${CMAKE_C_KNOWN_FEATURES}")

set(CMAKE_DL_LIBS "" CACHE STRING "dl linker flags") # or empty static dl (libdl.a) stub
set(CMAKE_FIND_LIBRARY_PREFIXES "lib")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".so" ".a")

# support position independance
# https://discourse.cmake.org/t/potential-bug-in-cmake-modules-compiler-clang-cmake-cmake-c-xx-compile-options-pic/1933/2
set(CMAKE_C_COMPILE_OPTIONS_PIC "-fPIC")
set(CMAKE_C_COMPILE_OPTIONS_PIE "-fPIE") ## needs -Xlinker --pic-veneer -fPIE -Xlinker --pie

# Detect libpthread / libm near libc
set(CMAKE_PLATFORM_HAS_PTHREADS OFF)
set(CMAKE_PLATFORM_HAS_MATH_LIB OFF)
set(CMAKE_PLATFORM_HAS_RT_LIB OFF)
if(_musl_loader)
  get_filename_component(_loader_dir "${_musl_loader}" DIRECTORY)
  # search sibling dirs (lib, lib64, usr/lib) for libpthread/libm
  set(_search_dirs
    "${loader_dir}"
    "${CMAKE_SYSROOT}/lib"
    "${CMAKE_SYSROOT}/usr/lib"
    "${CMAKE_INSTALL_PREFIX}/lib"
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
      file(GLOB _rt_candidates "${_d}/librt.*" "${_d}/librt.so" "${_d}/librt.a")
      if(_rt_candidates)
        set(CMAKE_PLATFORM_HAS_RT_LIB ON CACHE BOOL "Does the platform provide librt (real-time)")
      endif()
    endif()
  endforeach()
else()
  # fallback: attempt to find libs relative to CMAKE_SYSROOT or /lib
  foreach(_d IN LISTS "${CMAKE_SYSROOT}/lib" "/lib" "/usr/lib")
    if(EXISTS "${_d}")
      file(GLOB _pthreads_candidates "${_d}/libpthread.*" "${_d}/libpthread.a")
      if(_pthreads_candidates)
        set(CMAKE_PLATFORM_HAS_PTHREADS ON CACHE BOOL "Does the platform provide libpthreads")
      endif()
      file(GLOB _math_candidates "${_d}/libm.*" "${_d}/libm.a")
      if(_math_candidates)
        set(CMAKE_PLATFORM_HAS_MATH_LIB ON CACHE BOOL "Does the platform provide libm (math)")
      endif()
      file(GLOB _rt_candidates "${_d}/librt.*" "${_d}/librt.a")
      if(_rt_candidates)
        set(CMAKE_PLATFORM_HAS_RT_LIB ON CACHE BOOL "Does the platform provide librt (real-time)")
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
    set(CMAKE_SYSTEM_LINKER_TYPE LLD CACHE INTERNAL "System linker type")
    set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS ON CACHE BOOL "Should the flag -shared be used" FORCE)
  else()
    if(NOT DEFINED CMAKE_LINKER)
      set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS OFF CACHE BOOL "Should the flag -shared be used")
    else()
      set(CMAKE_SYSTEM_LINKER_TYPE DRIVER CACHE INTERNAL "System linker type")
      set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS ON CACHE BOOL "Should the flag -shared be used")
    endif()
  endif()
  set(CMAKE_C_LINKER_WRAPPER_FLAG "-Xlinker" " ")
  set(CMAKE_CXX_LINKER_WRAPPER_FLAG "-Xlinker" " ")
  set(CMAKE_ASM_LINKER_WRAPPER_FLAG "-Xlinker" " ")
  set(_c_dir_flags "-Xlinker -L${CMAKE_SYSTEM_LIBRARY_PATH}")
  list(FIND _generic_musl_EXE_linker_flags "${_c_dir_flags}" _found_musl_lib)
  if(_found_musl_lib EQUAL -1)
    list(APPEND _generic_musl_EXE_linker_flags "${_c_dir_flags}")
  endif()
  list(FIND _generic_musl_SHARED_linker_flags_INIT "${_c_dir_flags}" _found_musl_lib2)
  if(_found_musl_lib2 EQUAL -1)
    list(APPEND _generic_musl_SHARED_linker_flags_INIT "${_c_dir_flags}")
  endif()
else()
  set(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS OFF CACHE BOOL "Should the flag -shared be used")
endif()

# Shared linking flags when supported
if(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS AND _GENERIC_MUSL_HAVE_CLANG)
  # Prefer LLD where available
  if(LD_LLD OR LLD_LINK OR LLVM_LLD)
    set(_use_lld ON)
    foreach(type SHARED MODULE EXE)
      if (NOT DEFINED _generic_musl_${type}_linker_flags_INIT)
        set(_generic_musl_${type}_linker_flags_INIT "-fuse-ld=lld")
      else()
        list(FIND _generic_musl_${type}_linker_flags_INIT "-fuse-ld=lld" _found_lld_for_${type}_flag)
        if(_found_lld_for_${type}_flag EQUAL -1)
          list(APPEND _generic_musl_${type}_linker_flags_INIT "-fuse-ld=lld")
        endif()
      endif()
    endforeach()
  endif()
  foreach(lang C CXX)
    foreach(type SHARED_LIBRARY SHARED_MODULE)
      set(CMAKE_${type}_LINK_${lang}_FLAGS "-Xlinker --shared")
    endforeach()
  endforeach()

  if (NOT DEFINED _generic_musl_EXE_linker_flags)
    set(_generic_musl_EXE_linker_flags "${_generic_musl_EXE_linker_flags_INIT}")
  endif()

  # Set dynamic linker path for musl
  if(_musl_loader)
    list(FIND _generic_musl_EXE_linker_flags "--pic-veneer" _found_lld_veneer_flag)
    if(_found_lld_veneer_flag EQUAL -1)
      list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --pic-veneer")
    endif()
    list(FIND _generic_musl_EXE_linker_flags "--unique" _found_uniq_flag)
    if(_found_uniq_flag EQUAL -1)
      list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --no-gnu-unique")
      list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --unique")
    endif()
    list(FIND _generic_musl_EXE_linker_flags "--dynamic-linker" _found_dyn_link_flag)
    if(_found_dyn_link_flag EQUAL -1)
      list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --dynamic-linker=${_musl_loader}")
    endif()
    list(FIND _generic_musl_EXE_linker_flags "--pack-dyn-relocs=relr" _found_dyn_reloc_flag)
    if(_found_dyn_reloc_flag EQUAL -1)
      list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --pack-dyn-relocs=relr")
    endif()
    list(FIND _generic_musl_SHARED_linker_flags_INIT "--pic-veneer" _found_lld_veneer_flag2)
    if(_found_lld_veneer_flag2 EQUAL -1)
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --pic-veneer")
    endif()
    list(FIND _generic_musl_SHARED_linker_flags_INIT "--unique" _found_uniq_flag2)
    if(_found_uniq_flag2 EQUAL -1)
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --no-gnu-unique")
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --unique")
    endif()
    list(FIND _generic_musl_SHARED_linker_flags_INIT "--dynamic-linker" _found_dyn_link_flag2)
    if(_found_dyn_link_flag2 EQUAL -1)
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --dynamic-linker=${_musl_loader}")
    endif()
    list(FIND _generic_musl_SHARED_linker_flags_INIT "--pack-dyn-relocs=relr" _found_dyn_reloc_flag2)
    if(_found_dyn_reloc_flag2 EQUAL -1)
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --pack-dyn-relocs=relr")
    endif()
    # musl's dynamic loader supports DT_RELR / SHT_RELR
    list(FIND _generic_musl_SHARED_linker_flags_INIT "--pack-dyn-relocs=relr" _found_dyn_reloc_flag2)
    if(_found_dyn_reloc_flag2 EQUAL -1)
      list(APPEND _generic_musl_SHARED_linker_flags_INIT "-Xlinker --pack-dyn-relocs=relr")
    endif()
  endif()

  # From Musl's own documentation:
  #   It is recommended that distributions build GCC with multilib disabled,
  #   and use library directories named lib.
  # -fPIC -Xlinker --pic-veneer -Xlinker -z -Xlinker relro -Xlinker -z -Xlinker now

  # Conservative security flags
  list(FIND _generic_musl_EXE_linker_flags "relro" _found_relro_flag)
  if(_found_relro_flag EQUAL -1)
    list(APPEND _generic_musl_EXE_linker_flags "-z relro")
    list(APPEND _generic_musl_EXE_linker_flags "-z now")
  endif()
  if (NOT DEFINED _generic_musl_SHARED_linker_flags)
    set(_generic_musl_SHARED_linker_flags "${_generic_musl_SHARED_linker_flags_INIT}")
  endif()
  list(FIND _generic_musl_SHARED_linker_flags "relro" _found_relro_flag2)
  if(_found_relro_flag2 EQUAL -1)
    list(APPEND _generic_musl_SHARED_linker_flags "-z relro")
    list(APPEND _generic_musl_SHARED_linker_flags "-z now")
  endif()

  # else
  # Ensure shared lib variables don't advertise support
endif()

# TODO: handle adding excludes when linking clang_rt
#-Xlinker --exclude-libs=libgcc_s.so.1 -Xlinker --exclude-libs=libgcc_s.so -Xlinker --exclude-libs=libgcc_s.a
#-nobuiltininc

# Add clang_rt if found
if(DEFINED CLANG_RT_PATH AND EXISTS "${CLANG_RT_PATH}")
  list(FIND _generic_musl_EXE_linker_flags "${CLANG_RT_PATH}" _found_clang_rt)
  if(_found_clang_rt EQUAL -1)
    list(APPEND _generic_musl_EXE_linker_flags "${CLANG_RT_PATH}")
    list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --exclude-libs=libgcc_s.so.1")
    list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --exclude-libs=libgcc_s.so")
    list(APPEND _generic_musl_EXE_linker_flags "-Xlinker --exclude-libs=libgcc_s.a")
  endif()
  list(FIND _generic_musl_SHARED_linker_flags "${CLANG_RT_PATH}" _found_clang_rt2)
  if(_found_clang_rt2 EQUAL -1)
    list(APPEND _generic_musl_SHARED_linker_flags "${CLANG_RT_PATH}")
    list(APPEND _generic_musl_SHARED_linker_flags "-Xlinker --exclude-libs=libgcc_s.so.1")
    list(APPEND _generic_musl_SHARED_linker_flags "-Xlinker --exclude-libs=libgcc_s.so")
    list(APPEND _generic_musl_SHARED_linker_flags "-Xlinker --exclude-libs=libgcc_s.a")
  endif()
endif()

# Prefer llvm-ar/llvm-strip if present
find_program(LLVM_AR llvm-ar)
if(LLVM_AR)
  # Choose archiver and default format
  set(CMAKE_AR "${LLVM_AR}" CACHE FILEPATH "Archiver")
  set(AR_FORMAT "default" CACHE STRING "llvm-ar --format selection (default|bsd|darwin)")

  # Helpers to read possible target identifiers
  if(DEFINED CMAKE_C_COMPILER_TARGET)
    set(_target_id "${CMAKE_C_COMPILER_TARGET}")
  else()
    set(_target_id "${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
  endif()

  # Support explicit target triple containing apple/darwin
  if(_target_id MATCHES "apple" OR _target_id MATCHES "darwin")
    set(AR_FORMAT "darwin")
  elseif(_target_id MATCHES "freebsd|netbsd|openbsd|bsd" OR CMAKE_SYSTEM_NAME MATCHES "FreeBSD")
    set(AR_FORMAT "bsd")
  else()
    # fallback based on shared-lib suffix (.dylib => darwin, .so => bsd)
    if(DEFINED CMAKE_SHARED_LIBRARY_SUFFIX)
      if(CMAKE_SHARED_LIBRARY_SUFFIX STREQUAL ".dylib")
        set(AR_FORMAT "darwin")
      elseif(CMAKE_SHARED_LIBRARY_SUFFIX STREQUAL ".so")
        set(AR_FORMAT "bsd")
      endif()
    endif()
  endif()
  # Expose for debugging if needed
  message(VERBOSE "Selected llvm-ar format: ${AR_FORMAT}")

  # Override the archive commands so CMake calls llvm-ar with the chosen --format
  # Use the per-language variables; here for C and CXX (repeat for other languages if needed).
  set(CMAKE_C_ARCHIVE_CREATE
      "<CMAKE_AR> --format=${AR_FORMAT} rc <TARGET> <OBJECTS>")
  set(CMAKE_C_ARCHIVE_APPEND
      "<CMAKE_AR> --format=${AR_FORMAT} q <TARGET> <OBJECTS>")

  set(CMAKE_CXX_ARCHIVE_CREATE "${CMAKE_C_ARCHIVE_CREATE}")
  set(CMAKE_CXX_ARCHIVE_APPEND "${CMAKE_C_ARCHIVE_APPEND}")
endif()
find_program(LLVM_RANLIB llvm-ranlib)
if(LLVM_RANLIB)
  set(CMAKE_RANLIB "${LLVM_RANLIB}")
  # Use the per-language variables; here for C and CXX (repeat for other languages if needed).
  # uses CMAKE_RANLIB if set; keep default behaviour
  set(CMAKE_C_ARCHIVE_FINISH "<CMAKE_RANLIB> -D <TARGET>")
  set(CMAKE_CXX_ARCHIVE_FINISH "${CMAKE_C_ARCHIVE_FINISH}")
else()
  if(LLVM_AR)
    set(CMAKE_C_ARCHIVE_FINISH "<CMAKE_AR> sD <TARGET>")
    set(CMAKE_CXX_ARCHIVE_FINISH "${CMAKE_C_ARCHIVE_FINISH}")
  endif()
endif()
find_program(LLVM_STRIP llvm-strip)
if(LLVM_STRIP)
  set(CMAKE_STRIP "${LLVM_STRIP}")
endif()

# Defaults and hints
set(CMAKE_SKIP_RPATH OFF)
# POSIX -std=c99 is supported by musl (when defined)
add_compile_definitions(_POSIX_C_SOURCE=200809L)
# POSIX/XOPEN is also supported by musl (when defined)
add_compile_definitions(_XOPEN_SOURCE=700)
# POSIX -std=c99 -lm is supported with an empty archive by musl
set(CMAKE_PLATFORM_HAS_MATH_LIB ${CMAKE_PLATFORM_HAS_MATH_LIB})
# POSIX -std=c99 -lpthread is supported with an empty archive by musl
set(CMAKE_PLATFORM_HAS_PTHREADS ${CMAKE_PLATFORM_HAS_PTHREADS})

message(STATUS "Configured Generic-Musl platform (musl libc, Clang/LLVM preferred).")
if(_GENERIC_MUSL_HAVE_CLANG)
  message(STATUS "Detected Clang compiler id: ${CMAKE_C_COMPILER_ID}")
  if(DEFINED CLANG_RT_PATH)
    message(STATUS "clang_rt builtins: ${CLANG_RT_PATH}")
  else()
    message(STATUS "clang_rt builtins not auto-detected; set -DCLANG_RT_PATH=/path/to/libclang_rt.builtins.a to link it.")
  endif()
  # Check compile definitions usable at configure-time: the user may pass -D_GNU_SOURCE etc.
  # but not CMAKE_C_FLAGS MATCHES "_ALL_SOURCE"
  if(CMAKE_C_FLAGS MATCHES "_GNU_SOURCE" OR CMAKE_CXX_FLAGS MATCHES "_GNU_SOURCE")
    set(C_EXTENSIONS ON)
    set(CXX_EXTENSIONS ON)
  endif()
else()
  message(WARNING "No Clang detected; leaving most toolchain variables unchanged (GNU toolchains are unsupported).")
endif()

# STDC detection for Musl

# Candidate mapping: CMake-standard-string -> preferred __STDC_VERSION__ numeric literal
set(_candidates
  "26;202600L"   # provisional C26
  "23;202311L"   # Clang / provisional C23
  "23;202300L"   # musl does not directly support >= C23
  "17;201710L"   # experimental for musl (mostly ignored)
  "11;201112L"   # musl should provide _Noreturn for gnu-c (also needs -D_GNUC_ to enable)
  "99;199901L"   # musl should provide __inline & __restrict for compatibility with gnu-c
  "90;199409L"   # safe for musl (ignored)
)

# Does the musl build provide Annex K? (default: OFF)
option(MUSL_HAS_ANNEX_K "Set ON if musl libc was built to provide Annex K" OFF)

# If you want the config to define __STDC_NO_ANNEX_K__ when MUSL_HAS_ANNEX_K is OFF,
# enable this. (Separate from MUSL_HAS_ANNEX_K to avoid reusing the same option name.)
option(DEFINE_NO_ANNEX_K "When ON and MUSL_HAS_ANNEX_K is OFF, define __STDC_NO_ANNEX_K__=1" OFF)

# Option to force-define __STDC_VERSION__ as a compile definition (nonstandard; default OFF)
option(FORCE_DEFINE_STDC_VERSION "Define __STDC_VERSION__ as a compile definition" OFF)

# Only emit compile definitions if the user asked CMake to strictly enforce the requested standard
# or if the user explicitly requested forcing the definition.
# (This avoids redefining reserved macros unless explicitly asked.)
if(CMAKE_C_STANDARD_REQUIRED OR FORCE_DEFINE_STDC_VERSION)

  # Determine requested C standard (prefer user-supplied CMAKE_C_STANDARD)
  if(DEFINED CMAKE_C_STANDARD AND CMAKE_C_STANDARD)
    set(_requested_std "${CMAKE_C_STANDARD}")
  else()
    # Default to highest candidate (first entry)
    #list(GET _candidates 0 _first_pair)
    # WORKAROUND for cmake being a bit behind the drafts.
    # Default to c11 candidate (fifth entry)
    list(GET _candidates 4 _first_pair)
    string(REGEX REPLACE "([^;]+);(.+)" "\\1" _requested_std "${_first_pair}")
    # also set CMake variable so CMake's rules get the requested standard
    set(CMAKE_C_STANDARD "${_requested_std}" CACHE STRING "Requested C standard" FORCE)
  endif()

  # Find the numeric __STDC_VERSION__ value that matches the requested CMake standard name
  set(SELECTED_STD_VALUE "")
  foreach(_pair IN LISTS _candidates)
    string(REGEX REPLACE "([^;]+);(.+)" "\\1" _cand_std "${_pair}")
    string(REGEX REPLACE "([^;]+);(.+)" "\\2" _cand_val "${_pair}")
    if(_cand_std STREQUAL _requested_std)
      set(SELECTED_STD_VALUE "${_cand_val}")
      break()
    endif()
  endforeach()

  # Fallback to C11 numeric value if no exact match found
  if(NOT SELECTED_STD_VALUE)
    set(SELECTED_STD_VALUE "201112L")
  endif()

  message(STATUS "Requested C standard: ${_requested_std} -> selected __STDC_VERSION__=${SELECTED_STD_VALUE}")
  message(VERBOSE "MUSL_HAS_ANNEX_K = ${MUSL_HAS_ANNEX_K}; DEFINE_NO_ANNEX_K = ${DEFINE_NO_ANNEX_K}; FORCE_DEFINE_STDC_VERSION = ${FORCE_DEFINE_STDC_VERSION}")

  if(FORCE_DEFINE_STDC_VERSION)
    add_compile_definitions("__STDC_VERSION__=${SELECTED_STD_VALUE}")
  endif()
endif()

# If musl lacks Annex K and the user opted in, define the no-Annex-K macro
if(NOT MUSL_HAS_ANNEX_K AND DEFINE_NO_ANNEX_K)
  add_compile_definitions("__STDC_NO_ANNEX_K__=1")
endif()

#shared libs support
if(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS)
  message(STATUS "Shared libraries supported (musl loader and linker detected).")
  # (musl) support shared libraries
  set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)

  # Define feature "DEFAULT" as supported. This special feature generates the
  # default option to link a library
  # This feature is intended to be used in LINK_LIBRARY_OVERRIDE and
  # LINK_LIBRARY_OVERRIDE_<LIBRARY> target properties
  set(CMAKE_LINK_LIBRARY_USING_DEFAULT_SUPPORTED TRUE)
  set(CMAKE_SHARED_LIBRARY_FORMAT "ELF" CACHE STRING "Shared lib format")
  set(CMAKE_SHARED_MODULE_FORMAT "ELF" CACHE STRING "Shared module format")
  # PIE link options are managed in Compiler/<compiler>.cmake file
  list(FIND CMAKE_SHARED_LIBRARY_C_FLAGS "-fseparate-named-sections" _found_named_sections_flag)
  if(_found_named_sections_flag EQUAL -1)
    list(APPEND CMAKE_SHARED_LIBRARY_C_FLAGS "-fseparate-named-sections")
    list(APPEND CMAKE_SHARED_LIBRARY_C_FLAGS "${CMAKE_C_COMPILE_OPTIONS_PIC}")
  endif()
  set(CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS "-shared")       # -shared
  set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS "-shared")       # -shared
  if(NOT DEFINED CMAKE_SHARED_LIBRARY_LINK_C_FLAGS)
    message(STATUS "Detected dynamic linker id: ${CMAKE_LINKER}")
    set(CMAKE_SHARED_LIBRARY_LINK_C_FLAGS "")         # +s, flag for exe link to use shared lib
  endif()

  # Not sure if rpaths are used by musl (ld-musl-ARCH.so.1 is hardcoded when linking to musl)
  # Not sure about '-z' (including '-z origin') with musl linker
  foreach(lang C CXX ASM)
    foreach(type SHARED_LIBRARY SHARED_MODULE EXE)
      set(CMAKE_${type}_RPATH_ORIGIN_TOKEN "\$ORIGIN")
      set(CMAKE_${type}_RUNTIME_${lang}_FLAG "-Xlinker --enable-new-dtags -Xlinker --rpath=")
      set(CMAKE_${type}_RPATH_LINK_${lang}_FLAG "-Xlinker --disable-new-dtags -Xlinker --rpath=")
      # probably works like FreeBSD
      set(CMAKE_${type}_RUNTIME_${lang}_FLAG_SEP ":")   # : or empty
      set(CMAKE_${type}_SONAME_${lang}_FLAG "-Xlinker --soname=")
      set(CMAKE_${type}_EXPORTS_${lang}_FLAG "-Xlinker --export-dynamic")
    endforeach()
  endforeach()

  # Features for LINK_GROUP generator expression
  ## RESCAN: request the linker to rescan static libraries until there is
  ## no pending undefined symbols
  set(CMAKE_LINK_GROUP_USING_RESCAN "LINKER:--start-group" "LINKER:--end-group")
  set(CMAKE_LINK_GROUP_USING_RESCAN_SUPPORTED TRUE)

  # From Musl's own documentation:
  #   Since 1.1.21, musl supports increasing the default thread
  #   stack size via the PT_GNU_STACK program header, which can
  #   be set at link time via ${CMAKE_C_LINKER_WRAPPER_FLAG} -z,stack-size=N.

  # Shared libraries with no builtin soname may not be linked safely by
  # specifying the file path.
  set(CMAKE_PLATFORM_USES_PATH_WHEN_NO_SONAME 1)

  # Musl does NOT support versioned sonames
  set(CMAKE_PLATFORM_NO_VERSIONED_SONAME TRUE)

  # Initialize C link type selection flags.  These flags are used when
  # building a shared library, shared module, or executable that links
  # to other libraries to select whether to use the static or shared
  # versions of the libraries.
  foreach(type SHARED_LIBRARY SHARED_MODULE EXE)
    set(CMAKE_${type}_LINK_STATIC_C_FLAGS "-Xlinker -Bstatic")
    set(CMAKE_${type}_LINK_DYNAMIC_C_FLAGS "-Xlinker -Bdynamic")
  endforeach()

  set(CMAKE_SHARED_LIBRARY_CXX_FLAGS "${CMAKE_SHARED_LIBRARY_C_FLAGS}")
  set(CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS "${CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS}")
  set(CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS "${CMAKE_SHARED_LIBRARY_LINK_C_FLAGS}")
  set(CMAKE_SHARED_LIBRARY_RUNTIME_CXX_FLAG "${CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG}")
  # probably works like FreeBSD
  set(CMAKE_SHARED_LIBRARY_RUNTIME_CXX_FLAG_SEP "${CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG_SEP}")   # : or empty
  set(CMAKE_SHARED_LIBRARY_RPATH_LINK_CXX_FLAG "${CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG}")
  set(CMAKE_SHARED_LIBRARY_SONAME_CXX_FLAG "${CMAKE_SHARED_LIBRARY_SONAME_C_FLAG}")

  include(Platform/Linker/Generic-Musl-Linker)
  if(_GENERIC_MUSL_HAVE_CLANG)
    __musl_linker_clang(C)
    __musl_linker_clang(CXX)
    __musl_linker_clang(ASM)
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

# CMP0079: allow target_link_libraries() use with targets in other directories
# New in CMake 3.13: https://cmake.org/cmake/help/latest/policy/CMP0079.html
if(POLICY CMP0079)
  cmake_policy(SET CMP0079 NEW)
endif()

# CMP0164: add_library() rejects SHARED libraries when not supported by the platform.
# New in CMake 3.30: https://cmake.org/cmake/help/latest/policy/CMP0164.html
if(POLICY CMP0164)
  cmake_policy(SET CMP0164 NEW)
endif()

# CMP0128: <LANG>_EXTENSIONS are initialized with respect to CMAKE_<LANG>_EXTENSIONS_DEFAULT, unless overridden.
# New in CMake 3.22: https://cmake.org/cmake/help/latest/policy/CMP0128.html
if(POLICY CMP0128)
  cmake_policy(SET CMP0128 NEW)
endif()

foreach(type SHARED EXE)
  string(REPLACE ";" " " joined_${type}_linkerflags_init "${_generic_musl_${type}_linker_flags_INIT}")
  set(CMAKE_${type}_LINKER_FLAGS_INIT "${CMAKE_${type}_LINKER_FLAGS_INIT} ${joined_${type}_linkerflags_init}")
  string(REPLACE ";" " " joined_${type}_linkerflags "${_generic_musl_${type}_linker_flags}")
  set(CMAKE_${type}_LINKER_FLAGS "${CMAKE_${type}_LINKER_FLAGS} ${joined_${type}_linkerflags}")
endforeach()
