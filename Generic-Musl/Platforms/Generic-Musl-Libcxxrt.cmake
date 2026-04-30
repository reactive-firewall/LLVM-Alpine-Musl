include(Platform/Generic-Musl)

# Detect optional shared libcxxrt and required cxxabi header location
# Prefer an imported shared library if found and expose it as libcxxrt::lib
# Respect sysroot by using CMAKE_SYSROOT
find_library(_LIBCXXRT_NAMED libcxxrt
  PATHS ${CMAKE_SYSROOT}/usr/lib ${CMAKE_SYSROOT}/lib /usr/lib /lib
  NO_DEFAULT_PATH
  NO_CMAKE_FIND_ROOT_PATH
)

# A more typical find: allow normal search too (useful if no sysroot)
if(NOT _LIBCXXRT_NAMED)
  find_library(_LIBCXXRT_NAMED libcxxrt)
endif()

set(LIBCXXRT_FOUND FALSE)

if(CMAKE_PLATFORM_SUPPORTS_SHARED_LIBS)
  if(_LIBCXXRT_NAMED)
    set(LIBCXXRT_FOUND TRUE)
    # look for cxxabi header relative to include roots
    # check common include roots including sysroot
    set(_cxxabi_rel_path "c++/v1/cxxabi/cxxabi.h")
    find_path(_LIBCXXRT_CXXABI_H NAMES ${_cxxabi_rel_path}
      PATHS ${CMAKE_SYSROOT}/usr/include ${CMAKE_SYSROOT}/include /usr/include /usr/local/include
      PATH_SUFFIXES ""  # file name already includes subpath
    )
    # If found, compute the include-root (strip trailing path)
    if(_LIBCXXRT_CXXABI_H)
      get_filename_component(_inc_root "${_LIBCXXRT_CXXABI_H}" DIRECTORY) # .../c++/v1/cxxabi
      # go up two levels to reach include root that contains c++/v1
      get_filename_component(_inc_root "${_inc_root}" DIRECTORY) # .../c++/v1
      get_filename_component(_inc_root "${_inc_root}" DIRECTORY) # include root
    endif()

    # Create imported target for linkage convenience
    add_library(libcxxrt::lib UNKNOWN IMPORTED)
    set_target_properties(libcxxrt::lib PROPERTIES
      IMPORTED_LOCATION "${_LIBCXXRT_NAMED}"
    )
    if(_inc_root)
      target_include_directories(libcxxrt::lib INTERFACE "${_inc_root}")
    endif()
  endif()


  # Helper: when building C++ shared objects (modules, shared libs, executables built SHARED),
  # link to libcxxrt if found. You can apply this to targets you create:
  #
  # Example usage when creating a shared C++ target:
  # add_library(my_shared_module SHARED ...)
  # if(LIBCXXRT_FOUND)
  #   target_link_libraries(my_shared_module PRIVATE libcxxrt::lib)
  # endif()
  #
  # Alternatively, create an interface to automatically apply to SHARED C++ targets:
  add_library(Generic::CXXSharedRuntimes INTERFACE)
  if(LIBCXXRT_FOUND)
    target_link_libraries(Generic::CXXSharedRuntimes INTERFACE libcxxrt::lib)
  endif()
else()
  if(_LIBCXXRT_NAMED)
    message(STATUS "Detected C++ runtime library: ${_LIBCXXRT_NAMED}")
  else()
    message(STATUS "The C++ runtime library was not auto-detected! (Will want a C++ABI)")
  endif()
endif()
