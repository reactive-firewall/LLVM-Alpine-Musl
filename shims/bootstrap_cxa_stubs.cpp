/*
 * bootstrap_cxa_stubs.cpp
 *
 * MIT License
 *
 * Copyright (c) 2026 Mr. Walls
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

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

#ifndef WEAK_ATTR
/* Mark weak so a full C++ runtime can override these later. */
#if defined(__GNUC__) || defined(__clang__)
#define WEAK_ATTR __attribute__((weak))
#else
#define WEAK_ATTR
#endif
#endif /* !WEAK_ATTR */

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
