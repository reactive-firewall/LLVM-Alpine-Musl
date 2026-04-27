#!/usr/bin/env bash
set -euo pipefail
src="$1"
builddir="$2"
shift 2
mkdir -p "$builddir"
cmake -S "$src" -B "$builddir" "$@"
cmake --build "$builddir" -- -j2
cmake --install "$builddir"
