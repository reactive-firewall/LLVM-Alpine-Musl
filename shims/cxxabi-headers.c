#ifndef CXX_ABI_HEADERS_H
#define CXX_ABI_HEADERS_H

/* Detect ABI headers */
#if defined(__has_include)
#if __has_include(<cxxabi.h>)
#include <cxxabi.h>
#else
#if __has_include("cxxabi.h")
#include "cxxabi.h"
#endif
#endif

/* Intentionally empty compatibility header: no exported symbols.
   Keeps builds that expect -lcxxabi-headers satisfied without providing
   any definitions that could be picked up by the dynamic loader. */

#endif /* CXX_ABI_HEADERS_H */
