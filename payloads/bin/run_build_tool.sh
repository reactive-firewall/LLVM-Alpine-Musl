#!/bin/sh
# improved-run-build-tool.sh
# POSIX-sh portable wrapper: modular, readable, and conservative flag-injection/removal.
# Designed to be symlinked to various tool names (cc, c++, ld, cpp, ar, as, ...).
# Focus: clearer structure (functions), single-pass safe argument handling, preserve semantics.

prog=$(basename "$0")

# canonical tools in sysroot (prefered)
SYSROOT_CC="${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/bin/cc"
SYSROOT_LD="${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/bin/ld"

# env defaults
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${AR:=llvm-ar}"
: "${AS:=${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/bin/as-clang}"
: "${CPP:=${CC} -E}"
: "${RANLIB:=llvm-ranlib}"

# -----------------------
# Utilities (portable)
# -----------------------

# append token to NEW_ARGS (stores newline-separated)
NEW_ARGS=""
# WORKAROUND if need to handle spacing carefully (see make_positional)
#append() {
#	NEW_ARGS="${NEW_ARGS}${NEW_ARGS:+
#}$1"
#}
append() {
	if [ -z "$NEW_ARGS" ]; then
		NEW_ARGS="$1"
	else
		NEW_ARGS="$NEW_ARGS $1"
	fi
}

# push two tokens
append_pair() {
	append "$1"
	append "$2"
}

# join NEW_ARGS into positional params (safe for whitespace in tokens)
# WORKAROUND: some shells will need IFS set to newline and then they must be
#             reconstructed into positional args.
#make_positional() {
#	oldIFS=$IFS
#	IFS='
#'
#	# set -- to split tokens by newline
#	set -- $NEW_ARGS
#
#	IFS=$oldIFS
#}

# numeric value extractor for strings like "200809L" -> "200809"
numval() {
	printf '%s' "$1" | tr -cd '0-9'
}

# safe contains check (returns 0 if match)
contains_prefix() {
	[ -z "$2" ] && return 1 ;
	case "$1" in
		"$2"*) return 0 ;;
		*) return 1 ;;
	esac
}

# transform_args: transform "$@" in-place so that
# --dynamic-linker=... and --oformat=... become: -Xlinker <opt>
# leaves other args unchanged. After calling, the caller can use "$@".
transform_args() {
	# Build newline-separated buffer in TRANS
	TRANS=""
	for tok in "$@"; do
		case "$tok" in
			--dynamic-linker=*|--oformat=*)
				# add "-Xlinker" then the original token, separated by newlines
				TRANS="${TRANS}${TRANS:+
}-Xlinker
$tok"
				;;
			*)
				TRANS="${TRANS}${TRANS:+
}$tok"
				;;
		esac
	done

	# Save whether IFS was set and its value
	if [ "${IFS+set}" ]; then
		IFS_was_set=1
		oldIFS=$IFS
	else
		IFS_was_set=
	fi

	# Set IFS to newline only, split TRANS into positional params
	IFS='
'
	set -- $TRANS

	# Restore IFS to original state
	if [ "${IFS_was_set+set}" ]; then
		IFS=$oldIFS
	else
		unset IFS
	fi

	# Export the new positional parameters back to caller
	# (POSIX sh: use "set --" in caller context by calling this function with "transform_args \"$@\"; set -- "$@" ???")
	# To actually update caller's positional parameters, return the list on stdout.
	printf '%s\n' "$@"  # caller should read this to reset positional params
}

# -----------------------
# Scanning stage
# Produce a conservative summary of input args
# -----------------------

# State variables (0 = false / missing, 1 = true / present)
has_dynamic_linker=0
has_oformat=0
has_gnu_unique=0
has_posix_c_source=0
posix_c_value=""
has_xopen_source=0
has_posix_source_macro=0
undef_posix_c=0
undef_posix_source=0
has_stdlib=0
has_nostdincxx=0

# Compiler flags presence
has_mseses=0
has_fPIC=0
has_ffunction_sections=0
has_fdata_sections=0
has_fseparate_named_sections=0
has_fgnuc_version=0
has_fgnu_keywords=0
has_fno_digraphs=0
has_fstack_size_section=0
has_fintegrated_as=0
has_fno_integrated_as=0

# Helper: scan a single token; some tokens (like -Xlinker) need special handling in the rebuild stage
scan_token() {
	t="$1"
	case "$t" in
		--dynamic-linker=*) has_dynamic_linker=1 ;;
		--dynamic-linker) has_dynamic_linker=1 ;;
		--oformat=*) has_oformat=1 ;;
		--oformat) has_oformat=1 ;;
		--gnu-unique) has_gnu_unique=1 ;;
		-Wl,*)
			case "$t" in
				*--dynamic-linker=*) has_dynamic_linker=1 ;;
				*--oformat=*) has_oformat=1 ;;
				*--gnu-unique*) has_gnu_unique=1 ;;
			esac
			;;
		-D_POSIX_C_SOURCE=*)
			has_posix_c_source=1
			posix_c_value=${t#-D_POSIX_C_SOURCE=}
			;;
		-D_POSIX_C_SOURCE)
			has_posix_c_source=1
			posix_c_value="" # value likely next token; mark presence
			;;
		-U_POSIX_C_SOURCE) undef_posix_c=1 ;;
		-U_POSIX_SOURCE) undef_posix_source=1 ;;
		-D_XOPEN_SOURCE=*|-D_XOPEN_SOURCE) has_xopen_source=1 ;;
		-D_POSIX_SOURCE* ) has_posix_source_macro=1 ;;
		--nostdinc++) has_nostdincxx=1 ;;
		-stdlib=*) has_stdlib=1 ;;
		-mseses) has_mseses=1 ;;
		-fPIC) has_fPIC=1 ;;
		-ffunction-sections) has_ffunction_sections=1 ;;
		-fdata-sections) has_fdata_sections=1 ;;
		-fseparate-named-sections) has_fseparate_named_sections=1 ;;
		-fgnuc-version* ) has_fgnuc_version=1 ;;
		-fgnu-keywords) has_fgnu_keywords=1 ;;
		-fno-digraphs) has_fno_digraphs=1 ;;
		-fstack-size-section) has_fstack_size_section=1 ;;
		-fintegrated-as) has_fintegrated_as=1 ;;
		-fno-integrated-as) has_fno_integrated_as=1 ;;
	esac
}

# Perform a simple scan: do not attempt to resolve -Xlinker paired tokens here.
for tok in "$@"; do
	scan_token "$tok"
done

# Determine if POSIX_C >= 200809 (if numeric value is available)
posix_ge_200809=0
if [ "$has_posix_c_source" -eq 1 ] && [ -n "$posix_c_value" ]; then
	nv=$(numval "$posix_c_value")
	if [ -n "$nv" ] && [ "$nv" -ge 200809 ]; then
		posix_ge_200809=1
	fi
fi

# -----------------------
# Rebuild stage: iterate original args, emit tokens to NEW_ARGS while removing or rewriting where necessary.
# This stage handles -Xlinker next-token removal and -Wl, splitting.
# -----------------------


# Work on a copy of positional parameters using indices to avoid clobbering set --
orig_args="$*"
# Split orig_args into an array-like mechanism using a loop over "$@"
# We'll iterate using a shifting local copy to preserve portability
set -- "$@"
while [ $# -gt 0 ]; do
	a="$1"
	shift

	# Handle -Xlinker <arg>
	if [ "$a" = "-Xlinker" ]; then
		if [ $# -eq 0 ]; then
			append "$a"
			break
		fi
		b="$1"
		shift
		case "$b" in
			--gnu-unique)
				has_gnu_unique=1
				# drop both tokens
				continue
				;;
			--dynamic-linker=*|--oformat=*)
				append_pair "-Xlinker" "$b"
				case "$b" in
					--dynamic-linker=*) has_dynamic_linker=1 ;;
					--oformat=*) has_oformat=1 ;;
				esac
				continue
				;;
			*)
				append_pair "-Xlinker" "$b"
				continue
				;;
		esac
	fi

	# Handle -Wl,foo,bar safely (no set -- inside)
	case "$a" in
		-Wl,*)
			wl="${a#-Wl,}"
			rest="$wl"
			new_wl=""
			while [ -n "$rest" ]; do
				case "$rest" in
					*,*)
						part=${rest%%,*}
						rest=${rest#*,}
						;;
					*)
						part=$rest
						rest=""
						;;
				esac

				case "$part" in
					--gnu-unique)
						has_gnu_unique=1
						# drop this part
						continue
						;;
					--dynamic-linker=*)
						has_dynamic_linker=1
						;;
					--oformat=*)
						has_oformat=1
						;;
				esac

				if [ -z "$new_wl" ]; then
					new_wl="$part"
				else
					new_wl="$new_wl,$part"
				fi
			done

			if [ -n "$new_wl" ]; then
				append "-Wl,$new_wl"
			fi
			continue
			;;
	esac

	# Standalone tokens and other cases
	case "$a" in
		--gnu-unique)
			has_gnu_unique=1
			continue
			;;
		--dynamic-linker=*)
			has_dynamic_linker=1
			append "$a"
			continue
			;;
		--dynamic-linker)
			has_dynamic_linker=1
			append "$a"
			if [ $# -gt 0 ]; then
				append "$1"
				shift
			fi
			continue
			;;
		--oformat=*)
			has_oformat=1
			append "$a"
			continue
			;;
		--oformat)
			has_oformat=1
			append "$a"
			if [ $# -gt 0 ]; then
				append "$1"
				shift
			fi
			continue
			;;
		-D_POSIX_C_SOURCE=*)
			append "$a"
			continue
			;;
		-D_POSIX_C_SOURCE)
			append "$a"
			if [ $# -gt 0 ]; then
				append "$1"
				shift
			fi
			continue
			;;
		-U_POSIX_C_SOURCE|-U_POSIX_SOURCE|-D_XOPEN_SOURCE*|-D_POSIX_SOURCE*|--nostdinc++|-stdlib=*|-mseses|-fPIC|-ffunction-sections|-fdata-sections|-fseparate-named-sections|-fgnuc-version*|-fgnu-keywords|-fno-digraphs|-fstack-size-section|-fintegrated-as|-fno-integrated-as)
			case "$a" in
				-fgnuc-version*)
					has_fgnuc_version=1
					continue
					;;
				-fgnu-keywords)
					has_fgnu_keywords=1
					continue
					;;
				-fno-integrated-as)
					has_fno_integrated_as=1
					continue
					;;
				*)
					append "$a"
					continue
					;;
			esac
			;;
		-*)
			append "$a"
			continue
			;;
		*)
			append "$a"
			continue
			;;
	esac
done


# -----------------------
# Injection stage
# Make conservative injections based on scanned state and invocation type.
# -----------------------

# Helper: append only-if-missing
maybe_append() {
	case "$1" in
		"-mseses") [ "$has_mseses" -eq 0 ] && append "$1" ;;
		"-fPIC") [ "$has_fPIC" -eq 0 ] && append "$1" ;;
		"-ffunction-sections") [ "$has_ffunction_sections" -eq 0 ] && append "$1" ;;
		"-fdata-sections") [ "$has_fdata_sections" -eq 0 ] && append "$1" ;;
		"-fseparate-named-sections") [ "$has_fseparate_named_sections" -eq 0 ] && append "$1" ;;
		"-fno-digraphs") [ "$has_fno_digraphs" -eq 0 ] && append "$1" ;;
		"-fstack-size-section") [ "$has_fstack_size_section" -eq 0 ] && append "$1" ;;
		"-fintegrated-as") [ "$has_fintegrated_as" -eq 0 ] && [ "$has_fno_integrated_as" -eq 0 ] && append "$1" ;;
		*) append "$1" ;;
	esac
}


case "$prog" in
	ld|lld|ld.lld|ld64.lld|ld.musl-clang)
		# If SYSTEM_DL defined and no dynamic-linker present, add it.
		if [ -n "${SYSTEM_DL-}" ] && [ "$has_dynamic_linker" -eq 0 ]; then
			append "--dynamic-linker=${SYSTEM_DL}"
		fi
		# Add --oformat=elf if missing
		if [ "$has_oformat" -eq 0 ]; then
			append "--oformat=elf"
		fi
		# --gnu-unique was removed earlier where seen
		;;

	cpp|cpp.exe|any-generic-none-musl-cpp)
		# D_POSIX_C_SOURCE if not defined/undefed
		if [ "$has_posix_c_source" -eq 0 ] && [ "$undef_posix_c" -eq 0 ]; then
			append "-D_POSIX_C_SOURCE=200809L"
			has_posix_c_source=1
			posix_c_value="200809L"
			posix_ge_200809=1
		fi
		# XOPEN if not present and posix >= 200809
		if [ "$has_xopen_source" -eq 0 ] && [ "$posix_ge_200809" -eq 1 ] && [ "$undef_posix_c" -eq 0 ]; then
			append "-D_XOPEN_SOURCE=700L"
		fi
		# POSIX_SOURCE macro if not present and not undefined and posix present
		if [ "$has_posix_source_macro" -eq 0 ] && [ "$undef_posix_source" -eq 0 ] && [ "$has_posix_c_source" -eq 1 ]; then
			append "-D_POSIX_SOURCE"
		fi
		;;

	cc|any-generic-none-musl-cc|any-generic-none-musl-clang|c++|g++|any-generic-none-musl-c++|any-generic-none-musl-clang++|clang)
		case "$prog" in
			c++|g++|any-generic-none-musl-c++|any-generic-none-musl-clang++)
				# C++: add -stdlib if appropriate
				if [ "$has_nostdincxx" -eq 0 ] && [ "$has_stdlib" -eq 0 ]; then
					append "-stdlib=libc++"
				fi
				# fallthrough to generic compiler handling
				;;
		esac

		# common compiler flags
		maybe_append "-mseses"
		maybe_append "-fPIC"
		maybe_append "-ffunction-sections"
		maybe_append "-fdata-sections"
		# C-only flag when invoked as cc
		case "$prog" in
			cc|any-generic-none-musl-cc|any-generic-none-musl-clang)
				maybe_append "-fseparate-named-sections"
				;;
		esac
		maybe_append "-fno-digraphs"
		maybe_append "-fstack-size-section"
		# integrated assembler
		maybe_append "-fintegrated-as"
		# removed flags (-fgnuc-version, -fgnu-keywords, -fno-integrated-as) were dropped earlier
		;;
esac


set -- $NEW_ARGS

# -----------------------
# Finalize and execute
# Transform linker long options for CC fallback when necessary (convert --dynamic-linker=... and --oformat=... to -Xlinker pairs)
# -----------------------

# Convert NEW_ARGS to positional list
#WORKAROUND some shells would need to call this ( see alt append and make_positional above)
#make_positional
# but this should be enough:
set -- $NEW_ARGS

case "$prog" in
	ld|lld|ld.lld|ld64.lld|ld.musl-clang)
		if [ -x "$SYSROOT_LD" ]; then
			exec "$SYSROOT_LD" "$@"
		else
			# Transform certain linker-only long options to -Xlinker form for CC fallback.
			transform_args "$@"
			exec "${CC:-clang}" -fuse-ld=lld "$@"
		fi
		;;
	cpp|cpp.exe|any-generic-none-musl-cpp)
		# Ensure CPP safety as original script required
		allowed="${CC:-clang} -E"
		if [ -n "${CPP+set}" ]; then
			if [ "$CPP" != "$allowed" ]; then
				printf '%s\n' "Refusing to use unsafe CPP value" >&2
				exit 1
			fi
		fi
		exec "${CC:-clang}" -fintegrated-as -E "$@"
		;;
	cc|any-generic-none-musl-cc|any-generic-none-musl-clang)
		# default: prefer sysroot cc, else CC
		if [ -x "${SYSROOT_CC}" ]; then
			exec "${SYSROOT_CC}" "$@"
		else
			exec ${CC:-clang} "$@"
		fi
		;;
	c++|g++|any-generic-none-musl-c++|any-generic-none-musl-clang++)
		exec ${CXX:-clang++} "$@"
		;;
	ar|any-generic-none-musl-ar)
		exec "${AR}" "$@"
		;;
	as|as.exe|gas|asm|any-generic-none-musl-as)
		exec "${AS}" "$@"
		;;
	ranlib|any-generic-none-musl-ranlib)
		exec "${RANLIB:-ranlib}" "$@"
		;;
	*)
		# default: prefer sysroot cc, else CC
		if [ -x "${SYSROOT_CC}" ]; then
			exec "${SYSROOT_CC}" "$@"
		else
			exec ${CC:-clang} "$@"
		fi
		;;
esac
