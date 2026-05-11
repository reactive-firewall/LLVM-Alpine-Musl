#! /bin/bash
set -euo pipefail

if ! command -v llvm-elfedit >/dev/null 2>&1; then
  echo "error: llvm-elfedit not found in PATH" >&2
  exit 2
fi
if ! command -v llvm-readelf >/dev/null 2>&1; then
  echo "error: llvm-readelf not found in PATH" >&2
  exit 2
fi

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <file> [file...]" >&2
  exit 2
fi

for f in "$@"; do
  if [ ! -e "$f" ]; then
    echo "skipping: $f (not found)" >&2
    continue
  fi

  echo "processing: $f"

  # Check for existing DT_RUNPATH / DT_RPATH entries
  has_runpath=0
  has_rpath=0

  if llvm-readelf -d "$f" 2>/dev/null | grep -qi 'RUNPATH'; then
    has_runpath=1
  fi
  if llvm-readelf -d "$f" 2>/dev/null | grep -qi 'RPATH'; then
    has_rpath=1
  fi

  if [ $has_runpath -eq 0 ] && [ $has_rpath -eq 0 ]; then
    echo "  no DT_RUNPATH/DT_RPATH found; nothing to remove"
  else
    # Remove tags if present
    if [ $has_runpath -eq 1 ]; then
      echo "  removing DT_RUNPATH"
      llvm-elfedit --remove-dynamic-tag DT_RUNPATH "$f"
    fi
    if [ $has_rpath -eq 1 ]; then
      echo "  removing DT_RPATH"
      llvm-elfedit --remove-dynamic-tag DT_RPATH "$f"
    fi
  fi

  echo "  verification (DT entries after edit):"
  llvm-readelf -d "$f" | sed -n '1,200p' | awk '/(RUNPATH|RPATH)/ { print "  WARNING: still present -> "$0 }'
  # Also print a short dynamic table summary
  llvm-readelf -d "$f" | sed 's/^/    /'
done
