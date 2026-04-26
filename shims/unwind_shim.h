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
#define __UNWIND_SHIM_H_

/* unwind_shim.h
 * Provide either llvm's unwind.h (at unwind-llvm.h) or libcxxrt's unwind.h (at unwind-cxxabi.h)
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
/* 1. Check for __libunwind_config.h before trying unwind-llvm.h */
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

/* guard of unwind-llvm.h */
#if defined(_Unwind_Reason_Code)
#define __UNWIND_H__
#else
/* 2. Check for unwind-llvm.h and use it if available */
#if __has_include(<unwind-llvm.h>)
#include <unwind-llvm.h>
#define __UNWIND_SHIM_H_ <unwind.h>
#else /* !__has_include(<unwind-llvm.h>) */
#if __has_include("unwind-llvm.h")
#define __UNWIND_SHIM_H_ "unwind-llvm.h"
#else /* !__has_include("unwind-llvm.h") */
#define __UNWIND_SHIM_H_ 0
#endif /* End __has_include("unwind-llvm.h") (inner) */
#endif /* End __has_include(<unwind-llvm.h>) (outer) */
#endif /* End defined(_Unwind_Reason_Code) */

#endif /* !__UNWIND_H__ */

#else

/* guard of unwind-cxxabi.h */
#if defined(_Unwind_Reason_Code)
#ifndef UNWIND_H_INCLUDED
#define UNWIND_H_INCLUDED
#endif /* !UNWIND_H_INCLUDED */
#else /* !defined(_Unwind_Reason_Code) */
/* 3. Check for unwind-cxxabi.h and use it if available */
#if __has_include(<unwind-cxxabi.h>)
#include <unwind-cxxabi.h>
#define __UNWIND_SHIM_H_ <unwind-cxxabi.h>
#else /* !__has_include(<unwind-cxxabi.h>) */
#if __has_include("unwind-cxxabi.h")
#define __UNWIND_SHIM_H_ "unwind-cxxabi.h"
#else /* !__has_include("unwind-llvm.h") */
#define __UNWIND_SHIM_H_ 0
#endif /* End __has_include("unwind-cxxabi.h") (inner) */
#endif /* End __has_include(<unwind-cxxabi.h>) (outer) */
#endif /* End defined(_Unwind_Reason_Code) */

#endif /* End (__UNWIND_SHIM_HAS_LLVM_CONFIG_H_ > 0) */

/* Otherwise warn of unsupported compile environment. */
#if defined(_Unwind_Reason_Code)
#warning "Can not resolve an unwind implementation for C++ ABI - Build environment unsupported"
#endif /* !_Unwind_Reason_Code */

#else
#include <unwind.h>
#endif
