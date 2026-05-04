# Distributed under the OSI-approved BSD 3-Clause License.


# This module is shared by multiple languages; use include blocker.
include_guard()

macro(__musl_linker_clang lang)
    set(CMAKE_${lang}_COMPILE_OPTIONS_VISIBILITY "-fvisibility=")
    # linker selection
    set(CMAKE_${lang}_USING_LINKER_SYSTEM "")
    set(CMAKE_${lang}_USING_LINKER_LLD "-fuse-ld=lld")

    # Features for LINK_LIBRARY generator expression
    ## WHOLE_ARCHIVE: Force loading all members of an archive
    set(CMAKE_${lang}_LINKER_PUSHPOP_STATE_SUPPORTED FALSE)
    set(CMAKE_${lang}_LINK_LIBRARY_USING_WHOLE_ARCHIVE "LINKER:--whole-archive"
                                                       "<LINK_ITEM>"
                                                       "LINKER:--no-whole-archive")
    set(CMAKE_${lang}_LINK_LIBRARY_USING_WHOLE_ARCHIVE_SUPPORTED TRUE)
    set(CMAKE_${lang}_LINK_LIBRARY_WHOLE_ARCHIVE_ATTRIBUTES LIBRARY_TYPE=STATIC DEDUPLICATION=YES OVERRIDE=DEFAULT)

    set(CMAKE_${lang}_PLATFORM_LINKER_ID LLD)
    set(CMAKE_${lang}_LINK_LIBRARIES_PROCESSING ORDER=REVERSE DEDUPLICATION=ALL)
endmacro()
