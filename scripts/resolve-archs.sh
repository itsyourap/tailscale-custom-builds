#!/usr/bin/env bash
# Validates a comma-separated architecture list and prints it as a JSON array
# for the build matrix.
#
# Usage: scripts/resolve-archs.sh <archs>
set -euo pipefail
# Byte-order sorting, so the lists come out the same in every locale.
export LC_ALL=C

if [ "$#" -ne 1 ]; then
	echo "usage: $0 <archs>" >&2
	exit 2
fi

supported="$("$(dirname "$0")/build.sh" --list-archs | sort)"
requested="$(tr ',' '\n' <<<"$1" | tr -d ' \t\r' | { grep -v '^$' || true; } | sort -u)"

if [ -z "$requested" ]; then
	echo "::error::No architectures selected" >&2
	exit 1
fi
unknown="$(comm -23 <(echo "$requested") <(echo "$supported"))"
if [ -n "$unknown" ]; then
	echo "::error::Unsupported architectures: $(paste -sd, <<<"$unknown") (supported: $(paste -sd, <<<"$supported"))" >&2
	exit 1
fi

jq -R . <<<"$requested" | jq -sc .
