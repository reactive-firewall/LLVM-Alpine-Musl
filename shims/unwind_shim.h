/*
 * unwind_shim.h
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

#ifndef __UNWIND_SHIM_H_

#if defined(__clang__)
/* Unclear if this should be __has_feature or __has_extension */
#if __has_feature(attribute_unavailable)
#define LIBUNWIND_UNAVAIL __attribute__ (( unavailable ))
#pragma clang final(LIBUNWIND_UNAVAIL)
#else
#define LIBUNWIND_UNAVAIL
#endif
#endif /* !defined(__clang__) */

/* unwind_shim.h
 * Provide either llvm's unwind.h (at unwind-llvm.h) or libcxxrt's unwind.h (at unwind-cxxabi.h).
 * Do not use as system header (e.g., <unwind.h>).
 *
 * Usage: #include "unwind.h"
 *
 * This header tries:
 * 1) If _Unwind_Reason_Code already declared, do nothing.
 * 2) If __libunwind_config.h exists, check if unwind-llvm.h before using it.
 * 3) If unwind-llvm.h (and __libunwind_config.h) exists, implement _Unwind_Reason_Code using it.
 * 4) Otherwise if unwind-cxxabi.h exists, implement _Unwind_Reason_Code using it.
 * 5) Otherwise warn of unsupported compile environment.
 */

#if defined(__has_include)

#ifndef __UNWIND_SHIM_HAS_LLVM_CONFIG_H_
/* Check for __libunwind_config.h before trying unwind-llvm.h */
#if __has_include(<__libunwind_config.h>)
#define __UNWIND_SHIM_HAS_LLVM_CONFIG_H_ 1
#define __UNWIND_SHIM_LLVM_CONFIG_H_ <__libunwind_config.h>
#else /* !__has_include(<__libunwind_config.h>) */
#if __has_include("__libunwind_config.h")
#define __UNWIND_SHIM_HAS_LLVM_CONFIG_H_ 1
#define __UNWIND_SHIM_LLVM_CONFIG_H_ "__libunwind_config.h"
#else /* !__has_include("__libunwind_config.h") */
#define __UNWIND_SHIM_HAS_LLVM_CONFIG_H_ 0
#endif /* End __has_include("__libunwind_config.h") (inner) */
#endif /* End __has_include(<__libunwind_config.h>) (outer) */
#endif /* !__UNWIND_SHIM_HAS_LLVM_CONFIG_H_ */

#if (__UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0)

#ifndef __UNWIND_H__

/* Guard of unwind-llvm.h */
#if defined(_Unwind_Reason_Code)

#if defined(UNWIND_H_INCLUDED)
#if defined(__clang__)
#warning "Odd? '_Unwind_Reason_Code' is already defined, indicating an unwind implementation (but wrong import guard). This may break things."
#endif /* !__clang__ */
/* always define __UNWIND_H__ because we already found __UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0 (alias) */
#define __UNWIND_H__ UNWIND_H_INCLUDED

#else /* UNWIND_H_INCLUDED */

#if defined(__clang__)
#warning "Odd? '_Unwind_Reason_Code' is already defined, indicating an unwind implementation (but no import guard). This will break things."
#endif /* !__clang__ */
/* always define __UNWIND_H__ because we already found __UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0 (plain) */
#define __UNWIND_H__

#endif /* !UNWIND_H_INCLUDED */

#else /* !defined(_Unwind_Reason_Code) */
/* 1. Check for unwind-llvm.h and use it if available */
#if __has_include(<unwind-llvm.h>)
#include <unwind-llvm.h>
#define __UNWIND_SHIM_H_ <unwind.h>
#else /* !__has_include(<unwind-llvm.h>) */
#if __has_include(<unwind/unwind-llvm.h>)
#include <unwind/unwind-llvm.h>
#define __UNWIND_SHIM_H_ <unwind/unwind.h>
#else /* !__has_include(<unwind/unwind-llvm.h>) */
#if __has_include("unwind-llvm.h")
#define __UNWIND_SHIM_H_ "unwind-llvm.h"
#else /* !__has_include("unwind-llvm.h") */
#define __UNWIND_SHIM_H_ 0
#endif /* End __has_include("unwind-llvm.h") (inner) */
#endif /* End __has_include(<unwind/unwind-llvm.h>) (outer) */
#endif /* End __has_include(<unwind-llvm.h>) (outer) */
#endif /* End defined(_Unwind_Reason_Code) */

/* can now assume that: define __UNWIND_H__ OR define __UNWIND_SHIM_H_ */
#if !defined(__UNWIND_H__) && !defined(__UNWIND_SHIM_H_)
#error "Could not verify status of libunwind - unsupported compiler environment"
#endif /* END !defined(__UNWIND_H__) && !defined(__UNWIND_SHIM_H_) */

#endif /* !__UNWIND_H__ */

#else /* !(__UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0) */

#if defined(__clang__)
#warning "Can not use '__libunwind_config'; will attempt to find libcxxrt unwind implementation."
#endif /* !__clang__ */

/* Guard of unwind-cxxabi.h */
#if defined(_Unwind_Reason_Code)
#ifndef UNWIND_H_INCLUDED
#define UNWIND_H_INCLUDED
#endif /* !UNWIND_H_INCLUDED */
#else /* !defined(_Unwind_Reason_Code) */
/* 2. Check for unwind-cxxabi.h and use it if available */
#if __has_include(<unwind-cxxabi.h>)
#include <unwind-cxxabi.h>
#define __UNWIND_SHIM_H_ <unwind-cxxabi.h>
#else /* !__has_include(<unwind-cxxabi.h>) */
#if __has_include(<cxxabi/unwind-cxxabi.h>)
#include <cxxabi/unwind-cxxabi.h>
#define __UNWIND_SHIM_H_ <cxxabi/unwind-cxxabi.h>
#else /* !__has_include(<cxxabi/unwind-cxxabi.h>) */
#if __has_include("unwind-cxxabi.h")
#define __UNWIND_SHIM_H_ "unwind-cxxabi.h"
#else /* !__has_include("unwind-llvm.h") */
#define __UNWIND_SHIM_H_ 0
#endif /* End __has_include("unwind-cxxabi.h") (inner) */
#endif /* End __has_include(<cxxabi/unwind-cxxabi.h>) (outer) */
#endif /* End __has_include(<unwind-cxxabi.h>) (outer) */
#endif /* End defined(_Unwind_Reason_Code) */

/* can now assume that: define __UNWIND_H__ OR define __UNWIND_SHIM_H_ */
#if !defined(UNWIND_H_INCLUDED) && !defined(__UNWIND_SHIM_H_)
#error "Could not verify status of libcxxrt (unwind) - unsupported compiler environment"
#endif /* END !defined(__UNWIND_H__) && !defined(__UNWIND_SHIM_H_) */

#endif /* End (__UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0) */

#ifndef __has_builtin
#define __has_builtin(x) 0
#endif

#if __has_builtin(__builtin_static_assert)
#define STATIC_ASSERT(cond, msg) __builtin_static_assert(cond, msg)
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#else
/* C99 fallback — msg must be identifier-like (no quotes/spaces) */
#define STATIC_ASSERT(cond, msg) typedef char static_assertion_##msg[(cond) ? 1 : -1]
#endif

#ifndef __UNWIND_SHIM_MISSING_REASON_CODES_
#define __UNWIND_SHIM_MISSING_REASON_CODES_ "Can not find an unwind reason-code map for C++ ABI - Build environment unsupported"
#endif
#ifndef __UNWIND_SHIM_MISSING_EXCEPTIONS_TYPE_
#define __UNWIND_SHIM_MISSING_EXCEPTIONS_TYPE_ "Can not resolve an unwind implementation for C++ ABI - Build environment unsupported"
#endif

/* 3. Otherwise warn of unsupported compile environment. */
STATIC_ASSERT(sizeof(_Unwind_Reason_Code) > 0, __UNWIND_SHIM_MISSING_REASON_CODES_);
STATIC_ASSERT(sizeof(_Unwind_Exception) > 0, __UNWIND_SHIM_MISSING_EXCEPTIONS_TYPE_);

#else /* !defined(__has_include) */
#if defined(_Unwind_Reason_Code) || defined(_Unwind_Exception)
#define __UNWIND_SHIM_H_ 1
#if defined(__clang__)
#warning "Can not use '__has_include'; Yet _Unwind_Exception is defined; will attempt blind use of _Unwind_Exception implementation. This may break things."
#endif /* !__clang__ */
#else
#warning "Can not use '__has_include'; will attempt blind include of an unwind implementation. This may break things."
#define __UNWIND_SHIM_H_ <unwind.h>
#include <unwind.h>
#endif /* !_Unwind_Reason_Code */
#endif /* END defined(__has_include) */

#endif /* !__UNWIND_SHIM_H_ */
