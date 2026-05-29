# Distributed under the OSI-approved BSD 3-Clause License.

# FindCompilerArch.cmake
# Usage: detect_compiler_architecture(<LANG>)
# Produces:
#   <LANG>_COMPILER_ARCH_ID            - resolved value (not cached)
#   <LANG>_COMPILER_ARCH_ID_SOURCE     - source used
#
# Will set cache variable CMAKE_<LANG>_COMPILER_ARCHITECTURE_ID only if
# it is not already present in the cache (preserves vendor / user choices).

function(detect_compiler_architecture LANG)
  string(TOUPPER "${LANG}" LANG_U)
  set(cache_var "CMAKE_${LANG_U}_COMPILER_ARCHITECTURE_ID")
  set(lib_arch_var "CMAKE_${LANG_U}_LIBRARY_ARCHITECTURE")
  set(compiler_target_var "CMAKE_${LANG_U}_COMPILER_TARGET")

  # Return variables (non-cache).
  set(result_var "${LANG}_COMPILER_ARCH_ID")
  set(source_var "${LANG}_COMPILER_ARCH_ID_SOURCE")

  # If the cache already has a value, use it and do not override.
  if(DEFINED ${cache_var} AND NOT "${${cache_var}}" STREQUAL "")
    set(${result_var} "${${cache_var}}" PARENT_SCOPE)
    set(${source_var} "CACHE" PARENT_SCOPE)
    return()
  endif()

  # Helper: normalize an architecture token to conservative canonical form.
  function(_normalize_arch_token token outvar)
    string(TOLOWER "${token}" _tok)
    # strip known suffixes (e.g., -* or .*)
    string(REGEX REPLACE "([-_].*)$" "" _tok "${_tok}")

    # common mappings (extend as needed)
    if(_tok MATCHES "^(x86_64|x86-64|x64|amd64)$")
      set(_canon "x86_64")
    elseif(_tok MATCHES "^(i[3-6]86|x86|ia32)$")
      set(_canon "x86")
    elseif(_tok MATCHES "^(aarch64|arm64)$")
      set(_canon "aarch64")
    elseif(_tok MATCHES "^(armv7|armv7a|armhf|arm)$")
      set(_canon "arm")
    elseif(_tok MATCHES "^(riscv64|riscv32)$")
      # preserve width if present in token
      if(_tok MATCHES "riscv32")
        set(_canon "riscv32")
      else()
        set(_canon "riscv64")
      endif()
    elseif(_tok MATCHES "^(mips|mips64)$")
      set(_canon "${_tok}")
    else()
      # default: return token as-is (after strip/normalize)
      set(_canon "${_tok}")
    endif()
    set(${outvar} "${_canon}" PARENT_SCOPE)
  endfunction()

  # 1) Try CMAKE_<LANG>_LIBRARY_ARCHITECTURE if present and non-empty and not "generic"
  if(DEFINED ${lib_arch_var} AND NOT "${${lib_arch_var}}" STREQUAL "")
    string(STRIP "${${lib_arch_var}}" _lib_arch)
    if(NOT _lib_arch STREQUAL "generic")
      _normalize_arch_token("${_lib_arch}" _cand)
      if(NOT _cand STREQUAL "")
        set(${result_var} "${_cand}" PARENT_SCOPE)
        set(${source_var} "LIBRARY_ARCH" PARENT_SCOPE)
        # Do not cache — leave original cache var untouched so CMake's own detection can still run/override later.
        return()
      endif()
    endif()
  endif()

  # 2) Try CMAKE_<LANG>_COMPILER_TARGET (explicit compiler target triple)
  if(DEFINED ${compiler_target_var} AND NOT "${${compiler_target_var}}" STREQUAL "")
    string(STRIP "${${compiler_target_var}}" _ct)
    # target triples often are of form arch-vendor-os[-libc] or arch-*-*.
    # Extract first token up to first '-' (the architecture name) and normalize.
    string(REGEX REPLACE "^([^\\-]+).*$" "\\1" _arch_token "${_ct}")
    _normalize_arch_token("${_arch_token}" _cand)
    if(NOT _cand STREQUAL "")
      set(${result_var} "${_cand}" PARENT_SCOPE)
      set(${source_var} "COMPILER_TARGET" PARENT_SCOPE)
      return()
    endif()
  endif()

  # 3) Fallback to system/host processor variables set by CMake
  # Prefer CMAKE_SYSTEM_PROCESSOR (target) when cross-compiling, else host.
  if(DEFINED CMAKE_SYSTEM_PROCESSOR AND NOT "${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "")
    _normalize_arch_token("${CMAKE_SYSTEM_PROCESSOR}" _cand)
    if(NOT _cand STREQUAL "")
      set(${result_var} "${_cand}" PARENT_SCOPE)
      set(${source_var} "SYSTEM_PROCESSOR" PARENT_SCOPE)
      return()
    endif()
  endif()

  if(DEFINED CMAKE_HOST_SYSTEM_PROCESSOR AND NOT "${CMAKE_HOST_SYSTEM_PROCESSOR}" STREQUAL "")
    _normalize_arch_token("${CMAKE_HOST_SYSTEM_PROCESSOR}" _cand)
    if(NOT _cand STREQUAL "")
      set(${result_var} "${_cand}" PARENT_SCOPE)
      set(${source_var} "HOST_PROCESSOR" PARENT_SCOPE)
      return()
    endif()
  endif()

  # 4) Conservative guesses from CMAKE_SYSTEM_NAME when nothing else set.
  if(DEFINED CMAKE_SYSTEM_NAME AND NOT "${CMAKE_SYSTEM_NAME}" STREQUAL "")
    string(TOLOWER "${CMAKE_SYSTEM_NAME}" _sysname)
    if(_sysname MATCHES "^(linux|freebsd|netbsd|openbsd|dragonfly|android)$")
      # cannot infer arch from OS alone; leave empty but mark GUESS_NONE
      set(${result_var} "" PARENT_SCOPE)
      set(${source_var} "GUESS_NONE" PARENT_SCOPE)
      return()
    endif()
  endif()

  # If we reached here, we couldn't determine a conservative value.
  set(${result_var} "" PARENT_SCOPE)
  set(${source_var} "GUESS_NONE" PARENT_SCOPE)
endfunction()
