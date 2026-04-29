#! /bin/bash
set -euo pipefail
# check for cmake
test -x $(command -pv cmake) || exit 126 ;
src="${1:-.}"
builddir="${2:-build}"
shift 2
mkdir -p "$builddir"
cmake -S "$src" -B "$builddir" -Wno-dev "$@"
cmake --build "$builddir" -- -j2
cmake --install "$builddir"
