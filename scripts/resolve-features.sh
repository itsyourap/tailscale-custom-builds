#!/usr/bin/env bash
# Turns a comma-separated feature list into Tailscale build tags. Features not
# in the list are compiled out; features they depend on are kept.
#
# Usage: scripts/resolve-features.sh <tailscale-source-dir> <features> <output-dir>
#
# Writes to <output-dir>:
#   enabled-features.txt   features in the binary, including dependencies
#   disabled-features.txt  features compiled out
#   build-tags.txt         tags for scripts/build.sh
#   feature-hash-input.txt the text that is hashed: enabled features, comma-joined
#   feature-hash.txt       hash of that text, used in release names
set -euo pipefail
# Byte-order sorting, so the lists come out the same in every locale.
export LC_ALL=C

if [ "$#" -ne 3 ]; then
	echo "usage: $0 <tailscale-source-dir> <features> <output-dir>" >&2
	exit 2
fi
src="$1" features="$2"
mkdir -p "$3"
out="$(cd "$3" && pwd)"

export TS_USE_TOOLCHAIN=1 NOBASHDEBUG=true
cd "$src"
featuretags() { GOOS='' GOARCH='' ./tool/go run ./cmd/featuretags "$@"; }
lines() { tr ',' '\n' | tr -d ' \t\r' | { grep -v '^$' || true; } | sort -u; }

all="$(featuretags --list | cut -d: -f1 | lines)"
requested="$(lines <<<"$features")"

unknown="$(comm -23 <(echo "$requested") <(echo "$all") | { grep -v '^$' || true; })"
if [ -n "$unknown" ]; then
	echo "::error::Unknown features for this Tailscale version: $(paste -sd, <<<"$unknown")" >&2
	echo "Available features: $(paste -sd, <<<"$all")" >&2
	exit 1
fi

tags="$(featuretags --min --add="$(paste -sd, <<<"$requested")")"
disabled="$(tr ',' '\n' <<<"$tags" | sed -n 's/^ts_omit_//p')"
# The CLI has no omit tag: it is linked in by ts_include_cli instead.
if ! tr ',' '\n' <<<"$tags" | grep -qx ts_include_cli; then
	disabled="$(printf '%s\ncli\n' "$disabled")"
fi
disabled="$(lines <<<"$disabled")"
enabled="$(comm -23 <(echo "$all") <(echo "$disabled") | { grep -v '^$' || true; })"
deps="$(comm -23 <(echo "$enabled") <(echo "$requested") | { grep -v '^$' || true; })"

write() { if [ -n "$2" ]; then echo "$2" >"$1"; else : >"$1"; fi; }
write "$out/enabled-features.txt" "$enabled"
write "$out/disabled-features.txt" "$disabled"
write "$out/build-tags.txt" "$tags"

# The enabled features, sorted and joined with commas (no trailing newline),
# hashed with SHA-256 and cut to 12 hex digits.
printf '%s' "$(paste -sd, <<<"$enabled")" >"$out/feature-hash-input.txt"
hash="$(sha256sum "$out/feature-hash-input.txt" | cut -c1-12)"
write "$out/feature-hash.txt" "$hash"

echo "Enabled ($(grep -c . <<<"$enabled" || true)): $(paste -sd, <<<"$enabled")"
[ -z "$deps" ] || echo "  of which added as dependencies: $(paste -sd, <<<"$deps")"
echo "Disabled ($(grep -c . <<<"$disabled" || true)): $(paste -sd, <<<"$disabled")"
echo "Feature hash: $hash"
