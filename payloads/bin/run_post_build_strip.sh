#! /bin/bash
set -euo pipefail

strip_DT_R_PATHS() {
{

  if ! command -v llvm-elfedit >/dev/null 2>&1; then
    printf "%s\n" "error: llvm-elfedit not found in PATH" >&2
    return 126
  fi
  if ! command -v llvm-readelf >/dev/null 2>&1; then
    printf "%s\n" "error: llvm-readelf not found in PATH" >&2
    return 126
  fi
  _file="${1}"
  if [ -z $_file ] || [ ! -e $_file ]; then
    printf "%s\n" "error: No such file" >&2
    return 2
  fi

  has_runpath=0
  has_rpath=0

  if llvm-readelf -d "$_file" 2>/dev/null | grep -qi 'RUNPATH'; then
    has_runpath=1
  fi
  if llvm-readelf -d "$_file" 2>/dev/null | grep -qi 'RPATH'; then
    has_rpath=1
  fi

  if [ $has_runpath -eq 0 ] && [ $has_rpath -eq 0 ]; then
    printf "%s\n" "  no DT_RUNPATH/DT_RPATH found; nothing to remove"
  else
    # Remove tags if present
    if [ $has_runpath -eq 1 ]; then
      printf "%s\n" "  removing DT_RUNPATH"
      llvm-elfedit --remove-dynamic-tag DT_RUNPATH "$_file"
    fi
    if [ $has_rpath -eq 1 ]; then
      printf "%s\n" "  removing DT_RPATH"
      llvm-elfedit --remove-dynamic-tag DT_RPATH "$_file"
    fi
  fi
  unset has_runpath
  unset has_rpath

  printf "%s\n" "  verification (DT entries after edit):"
  llvm-readelf --dynamic-table "$_file" | sed -n '1,200p' | awk '/(RUNPATH|RPATH)/ { print "  WARNING: still present -> "$0 }'
  # Also print a short dynamic table summary
  llvm-readelf --dynamic-table "$_file" | sed 's/^/    /'
  return 0;
}

strip_GNU_versioned_sym() {
{

  if ! command -v llvm-strip >/dev/null 2>&1; then
    printf "%s\n" "error: llvm-strip not found in PATH" >&2
    return 126
  fi
  if ! command -v llvm-readelf >/dev/null 2>&1; then
    printf "%s\n" "error: llvm-readelf not found in PATH" >&2
    return 126
  fi
  _file="${1}"
  if [ -z $_file ] || [ ! -e $_file ]; then
    printf "%s\n" "error: No such file" >&2
    return 2
  fi

  has_g_version=0
  has_g_version_r=0
  has_g_version_d=0

  if llvm-readelf -d "$_file" 2>/dev/null | grep -qi '.gnu.version'; then
    has_g_version=1
  fi
  if llvm-readelf -d "$_file" 2>/dev/null | grep -qi '.gnu.version_r'; then
    has_g_version_r=1
  fi
  if llvm-readelf -d "$_file" 2>/dev/null | grep -qi '.gnu.version_d'; then
    has_g_version_d=1
  fi

  if [ $has_g_version -eq 0 ] && [ $has_g_version_r -eq 0 ] && [ has_g_version_d -eq 0 ]; then
    printf "%s\n" "  no versioned sections found; nothing to remove"
  else
    # Remove tags if present
    if [ $has_g_version -eq 1 ]; then
      printf "%s\n" "  removing .gnu.version"
      llvm-strip --remove-section=.gnu.version "$_file"
    fi
    if [ $has_g_version_r -eq 1 ]; then
      printf "%s\n" "  removing .gnu.version_r"
      llvm-strip --remove-section=.gnu.version_r "$_file"
    fi
    if [ $has_g_version_d -eq 1 ]; then
      printf "%s\n" "  removing .gnu.version_d"
      llvm-strip --remove-section=.gnu.version_d "$_file"
    fi
  fi
  unset has_g_version_d
  unset has_g_version_r
  unset has_g_version

  printf "%s\n" "  verification (DT_VER* entries after edit):"
  llvm-readelf --version-info "$_file" #| sed -n '1,200p' | awk '/(RUNPATH|RPATH)/ { print "  WARNING: still present -> "$0 }'
  llvm-readelf --dynamic-table "$_file" | sed -n '1,200p' | awk '/(DT_VERSYM|DT_VERNEED|DT_VERDEF)/ { print "  WARNING: still present -> "$0 }'
  # Also print a short dynamic table summary
  llvm-readelf --section-headers "$_file" | awk '/(.gnu.version|.gnu.version_r|.gnu.version_d)/ { print "  WARNING: versioned section still present -> "$0 }'
  return 0;
}

if [ "$#" -lt 1 ]; then
  printf "%s\n" "usage: $0 <file> [file...]" >&2
  exit 2
fi

for f in "$@"; do
  if [ ! -e "$f" ]; then
    printf "%s\n" "skipping: $f (not found)" >&2
    continue
  fi

  printf "%s\n" "processing: $f"

  # Check for existing DT_RUNPATH / DT_RPATH entries
  strip_DT_R_PATHS "$f" 2>/dev/null || true ;

  # Check for junk versioning of symbols:
  strip_GNU_versioned_sym "$f" 2>/dev/null || true ;
done
