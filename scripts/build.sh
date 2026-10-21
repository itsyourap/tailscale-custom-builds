#!/usr/bin/env bash
# Cross-compiles tailscale-custom (tailscaled, with the CLI embedded when the
# "cli" feature is enabled) for one Linux architecture.
#
# Usage: scripts/build.sh <tailscale-source-dir> <arch> <build-tags> <output-dir>
#        scripts/build.sh --list-archs
#
# <build-tags> comes from scripts/resolve-features.sh. The source dir must be a
# git checkout with history (not shallow) so the version can be stamped into
# the binary. Writes <output-dir>/tailscale-custom-linux-<arch>.
set -euo pipefail

ARCHS="386 amd64 arm arm64 geode loong64 mips mips64 mips64le mipsle ppc64le riscv64 s390x"

if [ "${1:-}" = --list-archs ]; then
	tr ' ' '\n' <<<"$ARCHS"
	exit 0
fi
if [ "$#" -ne 4 ]; then
	echo "usage: $0 <tailscale-source-dir> <arch> <build-tags> <output-dir>" >&2
	exit 2
fi
src="$1" arch="$2" tags="$3"
mkdir -p "$4"
out="$(cd "$4" && pwd)"

# Pure Go and statically linked, so the binary doesn't depend on the system's
# libc. GOARM=5 and GOMIPS=softfloat match Tailscale's official builds and run
# on CPUs without an FPU.
export GOOS=linux CGO_ENABLED=0
case "$arch" in
386 | amd64 | arm64 | loong64 | mips64 | mips64le | ppc64le | riscv64 | s390x)
	export GOARCH="$arch" ;;
arm) export GOARCH=arm GOARM=5 ;;
geode) export GOARCH=386 GO386=softfloat ;; # AMD Geode, as in official builds
mips | mipsle) export GOARCH="$arch" GOMIPS=softfloat ;;
*)
	echo "unsupported arch '$arch' (supported: $ARCHS)" >&2
	exit 2
	;;
esac
# Build with Tailscale's Go fork pinned in go.toolchain.rev, like official
# releases. NOBASHDEBUG silences the toolchain wrapper's `set -x` under CI.
export TS_USE_TOOLCHAIN=1 NOBASHDEBUG=true

bin="tailscale-custom-linux-$arch"
cd "$src"
echo "Building $bin"
TAGS="$tags" ./build_dist.sh --strip -o "$out/$bin" ./cmd/tailscaled
ls -l "$out/$bin"
