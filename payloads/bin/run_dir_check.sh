#!/bin/sh
# Portable Almquist-compatible script to check a directory.
# Usage: run_dir_check.sh DIR [MIN_COUNT]
# MIN_COUNT defaults to 4 (counts entries excluding '.' and '..' so >3 total including them).

DIR=$1
MIN_COUNT=${2:-4}

if [ -z "$DIR" ]; then
  printf "%s\n" "Usage: $0 DIR [MIN_COUNT]" >&2
  exit 2
fi

# Remove trailing slash if present
case "$DIR" in
  */) DIR=${DIR%/} ;;
esac

# Check directory exists and is a directory
if [ ! -d "$DIR" ]; then
  printf "%s\n" "ERROR: '$DIR' not found or not a directory" >&2
  exit 3
fi

# Count entries excluding . and ..
# Use POSIX-safe listing: use ls -A if available; fallback to simple loop if not
COUNT=0
# ls -A is widely available; use it but handle potential ls errors
if ls -A -- "$DIR" >/dev/null 2>&1; then
  # POSIX ls may not support --, so try without if previous failed
  if ls -A -- "$DIR" >/dev/null 2>&1; then
    COUNT=`ls -A -- "$DIR" | awk 'END{print NR+0}'`
  else
    COUNT=`ls -A "$DIR" | awk 'END{print NR+0}'`
  fi
else
  # Fallback: count filenames by shell loop
  for _p in "$DIR"/* "$DIR"/.[!.]* "$DIR"/..?*; do
    case "$_p" in
      "$DIR"/*)
        [ -e "$_p" ] || continue
        COUNT=`expr $COUNT + 1` ;;
      "$DIR"/.[!.]*)
        [ -e "$_p" ] || continue
        COUNT=`expr $COUNT + 1` ;;
      "$DIR"/..?*)
        [ -e "$_p" ] || continue
        COUNT=`expr $COUNT + 1` ;;
    esac
  done
fi

# COUNT now holds number of visible + dot entries (excluding . and ..).
# Require COUNT >= MIN_COUNT
# MIN_COUNT is expected as total entries (not counting . ..)
if [ "$COUNT" -lt "$MIN_COUNT" ]; then
  printf "%s\n" "ERROR: '$DIR' contains $COUNT entries (need >= $MIN_COUNT)" >&2
  exit 4
fi

# Compute total size of directory contents (sum of sizes of entries)
# Use du -sk for kilobytes in a portable manner (some du support -s -k separately)
TOTAL_KB=0
# Use POSIX du invocation: du -sk DIR/* (but handle case with no matches)
# Loop over entries to sum portable stat/du
sum_entry_size() {
  entry=$1
  # Prefer du -sk if available
  if du -sk "$entry" >/dev/null 2>&1; then
    kb=`du -sk "$entry" 2>/dev/null | awk '{print $1+0}'`
  else
    # Fallback: use wc on file or estimate directory as 0
    if [ -f "$entry" ]; then
      # bytes to KB, round up
      bytes=`wc -c < "$entry" 2>/dev/null || echo 0`
      kb=`expr \( $bytes + 1023 \) / 1024`
    else
      kb=0
    fi
  fi
  TOTAL_KB=`expr $TOTAL_KB + $kb`
}

# Iterate entries (including dotfiles) robustly
# Use set -- to expand patterns and then iterate
set -- "$DIR"/* "$DIR"/.[!.]* "$DIR"/..?*
for e in "$@"; do
  [ -e "$e" ] || continue
  # skip the directory itself if pattern matched it
  case "$e" in
    "$DIR") continue ;;
  esac
  sum_entry_size "$e"
done

# Require more than trivial size: default threshold 1 KB (adjust if desired)
MIN_KB=1
if [ "$TOTAL_KB" -le "$MIN_KB" ]; then
  printf "%s\n" "ERROR: '$DIR' contents too small (${TOTAL_KB} KB <= ${MIN_KB} KB)" >&2
  exit 5
fi

# All checks passed
printf "%s\n" "OK: '$DIR' exists, has $COUNT entries and total size ${TOTAL_KB} KB"
exit 0
