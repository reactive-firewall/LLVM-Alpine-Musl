#!/bin/sh
# wrapper: symlinked from various tool names; POSIX shell

prog=$(basename "$0")

# canonical compiler in sysroot
SYSROOT_CC="${SYSROOT:-/sysroot}${MUSL_PREFIX:-/usr}/bin/cc"   # set to your sysroot's bin/cc
HOST_BINDIR=$(llvm-config --bindir)   # where to find llvm stuff

# env defaults (from your Dockerfile)
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${AR:=llvm-ar}"
: "${AS:=${CC} -integrated-as -c}"
: "${CPP:=${CC} -E}"
: "${RANLIB:=llvm-ranlib}"

case "$prog" in
	as|as.exe|gas|asm|any-generic-none-musl-as)
		exec sh -c "${AS} \"$@\""
		;;
	ar|any-generic-none-musl-ar)
		exec sh -c "${AR} \"$@\""
		;;
	ranlib|any-generic-none-musl-ranlib)
		exec sh -c "${RANLIB:-ranlib} \"$@\""
		;;
	cpp|cpp.exe|any-generic-none-musl-cpp)
		allowed="${CC:-clang} -E"
		if [ -n "${CPP+set}" ]; then
			if [ "$CPP" != "$allowed" ]; then
				printf '%s\n' "Refusing to use unsafe CPP value" >&2
				exit 1
			fi
		fi
		exec ${CC:-clang} -integrated-as -E "$@"
		;;
	c++|g++|any-generic-none-musl-c++)
		exec ${CXX:-clang++} "$@"
		;;
	cc|any-generic-none-musl-cc)
		# Prefer sysroot cc driver if present, falling back to CC
		if [ -x "${SYSROOT_CC}" ]; then
			exec "${SYSROOT_CC}" "$@"
		else
			exec ${CC:-clang} "$@"
		fi
		;;
	ld|lld|ld.lld|ld64.lld|ld.musl-clang)
		# avoid replacing LLD assembler unless intended
		if [ -d "${HOST_BINDIR}" ]; then
			exec ${HOST_BINDIR}/llvm-lld "$@"
		else
			exec ${CC:-clang} -fuse-ld=lld "$@"
		fi
		;;
	*)
		# default: try to act as compiler driver
		if [ -x "${SYSROOT_CC}" ]; then
			exec "${SYSROOT_CC}" "$@"
		else
			exec ${CC:-clang} "$@"
		fi
		;;
esac
