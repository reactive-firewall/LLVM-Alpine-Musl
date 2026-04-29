#if defined(__has_include)
#if __has_include(<cstddef>) && __has_include(<cstdlib>)
#include <cstddef>
#include <cstdlib>
using std::size_t;
using std::malloc;
using std::free;
#else
#include <stddef.h>
#include <stdlib.h>
typedef size_t size_t; /* already defined by stddef.h; keeps intent explicit */
#endif
#else
/* Fallback when __has_include not available: prefer C headers for portability */
#include <stddef.h>
#include <stdlib.h>
typedef size_t size_t;
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Mark weak so a full C++ runtime can override these later. */
#if defined(__GNUC__) || defined(__clang__)
#define WEAK_ATTR __attribute__((weak))
#else
#define WEAK_ATTR
#endif

void* WEAK_ATTR __cxa_allocate_exception(size_t size) {
	return malloc(size);
}

void WEAK_ATTR __cxa_free_exception(void* ptr) noexcept {
	free(ptr);
}

void WEAK_ATTR __cxa_throw(void* /*ex*/, void* /*info*/, void (*/*dtor*/)(void*)) {
	/* Minimal bootstrap: abort if exceptions are actually thrown */
	abort();
}

void* WEAK_ATTR __cxa_get_exception_ptr(void* p) noexcept {
	return p;
}

void WEAK_ATTR __cxa_begin_catch(void*) noexcept {}
void WEAK_ATTR __cxa_end_catch() noexcept {}

#ifdef __cplusplus
}
#endif
