/*
 * __stack_chk_fail_local.c
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

/* Detect helpers */
#if !defined(HAS_ATTR)
# if defined(__has_attribute)
#  define HAS_ATTR(x) __has_attribute(x)
# else
#  define HAS_ATTR(x) 0
# endif
#endif

#if !defined(HAS_INCLUDE)
# if defined(__has_include)
#  define HAS_INCLUDE(x) __has_include(x)
# else
#  define HAS_INCLUDE(x) 0
# endif
#endif

/* 1) prefer compiler attribute (Clang/GCC) */
#if HAS_ATTR(noreturn)
# define NORETURN __attribute__((noreturn))
#elif HAS_ATTR(c_noreturn) /* clang's c_noreturn spelling, if present */
# define NORETURN __attribute__((c_noreturn))
#else

/* 2) prefer C11 keyword if available */
# if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
#  define NORETURN _Noreturn
# else

/* 3) fall back to <stdnoreturn.h> if present */
#  if HAS_INCLUDE(<stdnoreturn.h>)
#   include <stdnoreturn.h>
#   if defined(noreturn)
#    define NORETURN noreturn
#   else
#    define NORETURN /* header lacked macro */
#   endif
#  else
/* 4) final fallback: empty */
#   define NORETURN
#  endif
# endif
#endif

/* Ensure defined */
#ifndef NORETURN
# define NORETURN
#endif

extern void __stack_chk_fail(void) NORETURN;

/* Hidden, PIC-friendly local forwarder */
void __attribute__((visibility("hidden"))) NORETURN __stack_chk_fail_local(void)
{
    /* Ensure an indirect call path when appropriate for PIC/toolchains:
       the compiler will emit a PLT/GOT call for __stack_chk_fail when -fPIC
       is used, so a plain call here is PIC-safe. */
    __stack_chk_fail();
}
