#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   export BUILD_DIR=/work/builds/opt/libcxx-build
#   export OBJ_PATH=/work/builds/opt/libcxx-build/src/.../cxa_exception.cpp.o
#   ./arm_diagnostic_script.sh
#
# If OBJ_PATH is not set, the script will try to find likely .o files under BUILD_DIR.

echo "=== ARM Diagnostic Script ==="
date
echo

# Helpers
cmd_exists() { command -v "$1" >/dev/null 2>&1; }
safe_run() { echo "+++ $*"; "$@" || echo "!!! command failed: $*"; }

# Basic environment
echo "### Environment"
echo "PWD: $(pwd)"
echo "BUILD_DIR: ${BUILD_DIR:-<not set>}"
echo "OBJ_PATH: ${OBJ_PATH:-<not set>}"
echo "TARGET: ${TARGET:-<not set>}"
echo "CC: ${CC:-$(command -v clang || true)}"
echo "CXX: ${CXX:-$(command -v clang++ || true)}"
echo "LD: ${LD:-$(command -v ld.lld || command -v ld || true)}"
echo "SYSROOT: ${SYSROOT:-<not set>}"
echo "PATH: $PATH"
echo

echo "### Tool versions"
if cmd_exists clang++; then safe_run clang++ --version; else echo "clang++ not found"; fi
if cmd_exists clang; then safe_run clang --version; fi
if cmd_exists gcc; then safe_run gcc --version; fi
if cmd_exists ld.lld; then safe_run ld.lld --version; fi
if cmd_exists llvm-readelf; then safe_run llvm-readelf --version; else echo "llvm-readelf not found"; fi
if cmd_exists llvm-objdump; then safe_run llvm-objdump --version; else echo "llvm-objdump not found"; fi
if cmd_exists nm; then safe_run nm --version || true; fi
echo

# Find candidate object file(s)
find_obj_candidates() {
  if [ -n "${OBJ_PATH:-}" ] && [ -f "$OBJ_PATH" ]; then
    echo "$OBJ_PATH"
    return 0
  fi
  if [ -n "${BUILD_DIR:-}" ] && [ -d "$BUILD_DIR" ]; then
    echo "Searching for likely object files under BUILD_DIR..."
    find "$BUILD_DIR" -type f \( -name 'cxa_exception*.o' -o -name '*cxa_exception*.o' -o -name '*cxa_*' -o -path '*/CMakeFiles/*cxxabi_shared_objects.dir/*.o' \) -print | head -n 20
    # also try widely named libc++abi objects if present
    find "$BUILD_DIR" -type f -name '*.o' -path '*cxxabi*' -print | head -n 50
  else
    echo "No BUILD_DIR set and OBJ_PATH unset; scanning current dir for likely .o..."
    find . -type f -name 'cxa_exception*.o' -o -name '*cxa_exception*.o' -print | head -n 20
  fi
}

echo "### Candidate object files"
CANDIDATES=$(find_obj_candidates)
echo "$CANDIDATES"
echo

# If multiple, pick first for deep inspection, but print list for manual check
FIRST_OBJ=$(echo "$CANDIDATES" | sed -n '1p' || true)
if [ -z "$FIRST_OBJ" ]; then
  echo "No object candidate found; exiting with non-zero."
  exit 2
fi

echo "### Deep inspect object: $FIRST_OBJ"
safe_run file "$FIRST_OBJ"
safe_run llvm-readelf -h "$FIRST_OBJ"
safe_run llvm-readelf -S "$FIRST_OBJ" | sed -n '1,120p'
echo

echo "Relocations in the object (full, may be large):"
safe_run llvm-readelf -r "$FIRST_OBJ" | sed -n '1,200p'
echo

echo "Relocations filtered for ARM ABS32/REL/PLT/UNWIND:"
safe_run llvm-readelf -r "$FIRST_OBJ" | grep -E 'R_ARM_ABS32|R_ARM_REL32|R_ARM_CALL|R_ARM_JUMP24|R_ARM_V4BX' || true
echo

echo "Looking for references to _Unwind_Resume and similar unwind symbols in this object:"
safe_run llvm-readelf -Ws "$FIRST_OBJ" | grep -E 'Unwind|__gxx_personality|_Unwind_Resume|_Unwind_RaiseException|_Unwind_Resume_or_Rethrow' || true
echo

echo "Disassembly around symbol __cxa_end_cleanup (if present):"
SYM=$(llvm-readelf -s "$FIRST_OBJ" 2>/dev/null | grep -E ' __cxa_end_cleanup$' | awk '{print $2}')
if [ -n "$SYM" ]; then
  safe_run llvm-objdump -D -M reg-names-raw --start-address=0x$SYM "$FIRST_OBJ" | sed -n '1,160p' || true
else
  echo "Could not find symbol __cxa_end_cleanup by name; dumping first 200 lines of disassembly instead:"
  safe_run llvm-objdump -d -M reg-names-raw "$FIRST_OBJ" | sed -n '1,200p' || true
fi
echo

# List of libraries referenced on link line: try to extract from env LINK_FLAGS or by scanning build.ninja
echo "### Linker flags / link inputs (attempts)"
if [ -n "${LINK_LINE:-}" ]; then
  echo "LINK_LINE env provided:"
  echo "$LINK_LINE"
else
  echo "Attempting to find obvious linker inputs in BUILD_DIR/build.ninja"
  if [ -n "${BUILD_DIR:-}" ] && [ -f "$BUILD_DIR/build.ninja" ]; then
    grep -E -- '-l(gcc|unwind|c|pthread|clang_rt|libgcc|libunwind|libclang_rt)' "$BUILD_DIR/build.ninja" || true
    echo "--- full link lines containing cxxabi_shared_objects.dir ---"
    grep -n 'cxxabi_shared_objects.dir' "$BUILD_DIR/build.ninja" || true
  else
    echo "No build.ninja found to parse."
  fi
fi
echo

# Inspect candidate runtime provider libraries that often provide _Unwind_Resume
echo "### Possible unwind providers to inspect (common paths)"
POSSIBLE_LIBS=(
  "${SYSROOT:-/sysroot}/usr/lib/libunwind.so"
  "${SYSROOT:-/sysroot}/usr/lib/libunwind.so.1"
  "${SYSROOT:-/sysroot}/lib/libgcc_s.so.1"
  "/usr/lib/gcc/*/../../../libgcc_s.so.1"
  "/usr/lib/gcc/*/*/libgcc_s.so.1"
  "/usr/lib/libunwind.so"
  "/lib/libunwind.so"
)
for p in "${POSSIBLE_LIBS[@]}"; do
  for f in $(ls -1 $p 2>/dev/null || true); do
    echo "---- Inspecting $f ----"
    safe_run file "$f"
    safe_run llvm-readelf -h "$f"
    safe_run llvm-readelf -Ws "$f" | grep -E 'Unwind|__gxx_personality|_Unwind_Resume' || true
    safe_run nm -D --defined-only "$f" 2>/dev/null | grep -E 'Unwind|__gxx_personality|_Unwind_Resume' || true
    echo
  done
done

# Inspect any static builtins archive referenced in original link (libclang_rt.builtins-arm.a)
echo "### Inspect libclang_rt.builtins-arm.a if present in common locations"
COMMON_BUILTINS=(
  "${BUILD_DIR:-/work/builds}/opt/libcxxabi-bootstrap0/lib/generic/libclang_rt.builtins-arm.a"
  "${BUILD_DIR:-/work/builds}/opt/libclang_rt.builtins-arm.a"
  "/work/builds/opt/libcxxabi-bootstrap0/lib/generic/libclang_rt.builtins-arm.a"
)
for a in "${COMMON_BUILTINS[@]}"; do
  if [ -f "$a" ]; then
    echo "---- Archive: $a ----"
    safe_run file "$a"
    safe_run ar -t "$a" | sed -n '1,200p' || true
    echo "Looking inside archive for Unwind symbols / relocations (extracting short list):"
    for m in $(ar -t "$a" 2>/dev/null | head -n 200); do
      if ar -p "$a" "$m" | llvm-readelf -Ws - 2>/dev/null | grep -E -q 'Unwind|_Unwind_Resume|__gxx_personality'; then
        echo "Member: $m -> symbols:"
        ar -p "$a" "$m" | llvm-readelf -Ws - 2>/dev/null | grep -E 'Unwind|_Unwind_Resume|__gxx_personality' || true
        echo "Member relocations (llvm-readelf -r):"
        ar -p "$a" "$m" | llvm-readelf -r - 2>/dev/null | grep -E 'R_ARM_ABS32|R_ARM_REL32|R_ARM_CALL|R_ARM_JUMP24' || true
      fi
    done
    echo
  fi
done

# Show dynamic loader search paths used at link time if possible (ld.lld verbose)
echo "### Linker search paths (attempt to show sysroot and /usr/lib locations)"
echo "LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-<not set>}"
echo "SYSROOT: ${SYSROOT:-<not set>}"
echo "Checking standard library locations:"
for d in /lib /usr/lib /usr/lib/gcc /usr/lib/gcc/*/; do
  ls -ld $d 2>/dev/null | sed -n '1,50p' || true
done
echo

# Check compilation flags used to produce the object if build.ninja/compile_commands.json exists
echo "### Trying to find how $FIRST_OBJ was compiled (compile_commands.json / build.ninja)"
if [ -f compile_commands.json ]; then
  echo "Found compile_commands.json; searching for $FIRST_OBJ"
  jq -r --arg f "$FIRST_OBJ" '.[] | select(.file|contains($f) or .file|endswith("'"$(basename "$FIRST_OBJ")"'")) | .command' compile_commands.json 2>/dev/null || true
else
  if [ -n "${BUILD_DIR:-}" ] && [ -f "${BUILD_DIR}/build.ninja" ]; then
    echo "Looking for compile line in build.ninja (first match):"
    grep -n "$(basename "$FIRST_OBJ")" "${BUILD_DIR}/build.ninja" | sed -n '1,10p' || true
  else
    echo "No compile_commands.json or build.ninja available in current env."
  fi
fi
echo

# Quick summary heuristics
echo "### Heuristic checks"
echo "Check if the object has absolute relocations referencing Unwind symbols:"
if llvm-readelf -r "$FIRST_OBJ" 2>/dev/null | grep -E 'R_ARM_ABS32' >/dev/null; then
  echo "Found R_ARM_ABS32 relocations in object — indicates non-PIC absolute references."
else
  echo "No R_ARM_ABS32 relocations found in object (or llvm-readelf failed to parse)."
fi

echo "Check if system libgcc provides _Unwind_Resume (shared):"
if llvm-readelf -Ws /usr/lib/gcc/*/../../../libgcc_s.so.1 2>/dev/null | grep -E -q '_Unwind_Resume'; then
  echo "_Unwind_Resume found in libgcc_s.so.1"
else
  echo "_Unwind_Resume not found (or libgcc_s.so.1 not present under that path)"
fi

echo
echo "### End of diagnostics"
date
