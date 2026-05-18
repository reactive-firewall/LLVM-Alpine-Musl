#!/bin/sh
# POSIX shell wrapper: data-driven, modular, minimal globals.
# Usage: invoked via symlink named "<arch>-generic-none-musl-<tool>"


# ----------------------------
# Data: architecture and flag mappings
# ----------------------------
arch_map() {
  # maps incoming arch -> canonical arch key
  case "$1" in
    armv7) printf '%s\n' "armhf" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

triple_for_arch() {
  case "$1" in
    # the minimum supported CPU model is actually 80486 unless kernel emulation of the cmpxchg instruction is added
    i486|i*86) printf '%s\n' "i486-generic-none-musl" ;; # UNUSED ISA32 - just an interesting minimum
    x86_64) printf '%s\n' "x86_64-generic-none-musl" ;; # targets AMD LP64
    aarch64|armv8) printf '%s\n' "aarch64-generic-none-musl" ;; # AArch64 target is little-endian (see aarch64_be)
    armhf|arm|armv7) printf '%s\n' "armv7-generic-none-musleabihf" ;; # might want just eabi instead?
    *) printf '%s\n' "" ;;
  esac
}

march_mcpu_for_arch() {
  case "$1" in
    i486|i*86) printf '%s\n' "-march=i486 -m32 -mtune=generic" ;; # UNUSED ISA32 - just an interesting minimum
    x86_64) printf '%s\n' "-march=x86-64-v4 -mtune=generic" ;;  # targets AMD LP64
    aarch64|armv8) printf '%s\n' "-march=armv8-a -mtune=generic" ;;  # AArch64 target is little-endian
    armhf|armv7) printf '%s\n' "-march=armv7-a -mabi=aapcs -mtune=generic -marm -mfloat-abi=hard -mfpu=neon-vfpv4" ;; # targets armv7 like raspberrypi 2+ thru 3B+ (32-bit) (but those should use -mcpu=cortex-a7 or -mcpu=cortex-a53)
    *) printf '%s\n' "" ;;
  esac
}

# Tools that accept --target (clang style)
target_accepting() {
  case "$1" in
    clang|cc|c++|cpp|as|ld) return 0 ;;
    *) return 1 ;;
  esac
}

# Tools that need special default args
default_args_for_tool() {
  case "$1" in
    ar) printf '%s\n' "--format=bsd" ;;     # llvm-ar friendly format
    *) printf '%s\n' "" ;;
  esac
}

# ----------------------------
# Helpers
# ----------------------------
basename_only() {
  # POSIX basename without calling external basename
  p="${1%/}"
  p="${p##*/}"
  printf '%s' "$p"
}

has_flag_prefix() {
  prefix="$1"; shift
  for a in "$@"; do
    case "$a" in
      "$prefix" | "$prefix"*) return 0 ;;
    esac
  done
  return 1
}

find_driver() {
  tool="$1"
  # Prefer driver next to this script
  here="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
  cand="$here/any-generic-none-musl-$tool"
  if [ -x "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  # Fallback to PATH
  cand="$(command -v "any-generic-none-musl-$tool" 2>/dev/null || true)"
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  return 1
}

# Safe append (build args list using set --)
append_args() {
  for a in "$@"; do
    set -- "$@" "$a"
  done
}

# ----------------------------
# Main wiring
# ----------------------------
prog="$(basename_only "$0")"

case "$prog" in
  *-generic-none-musl-*)
    inv_arch="${prog%%-generic-none-musl-*}"
    tool="${prog#*-generic-none-musl-}"
    ;;
  *-generic-none-musleabi-*)
    inv_arch="${prog%%-generic-none-musleabi-*}"
    tool="${prog#*-generic-none-musleabi-}"
    ;;
  *-generic-none-musleabihf-*)
    inv_arch="${prog%%-generic-none-musleabihf-*}"
    tool="${prog#*-generic-none-musleabihf-}"
    ;;
  *)
    # fallback: assume tool is the whole prog
    inv_arch=""
    tool="$prog"
    ;;
esac

arch="$(arch_map "$inv_arch")"
triple="$(triple_for_arch "$arch")"
marchcpu="$(march_mcpu_for_arch "$arch")"
drv="$(find_driver "$tool")" || {
  printf '%s\n' "error: driver not found: any-generic-none-musl-$tool" >&2
  exit 127
}

# Preserve original user args
orig_args="$*"

# Build final argv: start with driver
set -- "$drv"

# Inject --target if tool accepts it and triple is known and user didn't provide --target
if target_accepting "$tool" && [ -n "$triple" ] && ! has_flag_prefix -- "--target" "$@ $orig_args"; then
  set -- "$@" "--target=$triple"
fi

# Inject march/mcpu if present and not already supplied
if [ -n "$marchcpu" ] && ! has_flag_prefix -- "-march" $orig_args && ! has_flag_prefix -- "-mtune" $orig_args && ! has_flag_prefix -- "-mcpu" $orig_args; then
  for f in $marchcpu; do set -- "$@" "$f"; done
fi

# Tool-specific defaults (ar, etc.)
defargs="$(default_args_for_tool "$tool")"
if [ -n "$defargs" ]; then
  for f in $defargs; do set -- "$@" "$f"; done
fi

# Append original user args (preserve spacing/words)
# POSIX: rebuild by iterating over "$@": but we clobbered "$@" earlier, so use saved positional parameters via "$orig_args"
# Split orig_args safely by resetting IFS then using set --
old_IFS="$IFS"
IFS=' '
set -- "$@" $orig_args
IFS="$old_IFS"

# Exec driver with final argv vector
exec "$@"
