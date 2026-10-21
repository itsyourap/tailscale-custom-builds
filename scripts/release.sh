#!/usr/bin/env bash
# Publishes tailscale-custom binaries to the GitHub release named <version>.
#
# - No such release: create it with all binaries and the feature lists.
# - Release exists: upload only the architectures it doesn't have yet. If it
#   already has all of them, do nothing.
#
# Usage: scripts/release.sh <version> <dist-dir>
# Needs the gh CLI with GH_TOKEN and GH_REPO (or a repo checkout) set.
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <version> <dist-dir>" >&2
	exit 2
fi
version="$1"
cd "$2"

shopt -s nullglob
binaries=(tailscale-custom-linux-*)
if [ "${#binaries[@]}" -eq 0 ]; then
	echo "::error::No tailscale-custom binaries in $2" >&2
	exit 1
fi
for f in enabled-features.txt disabled-features.txt; do
	[ -f "$f" ] || { echo "::error::Missing $f in $2" >&2; exit 1; }
done

tag="$(gh release list --limit 1000 --json name,tagName |
	jq -r --arg v "$version" 'first(.[] | select(.name == $v) | .tagName) // empty')"

if [ -z "$tag" ]; then
	echo "Creating release $version with: ${binaries[*]}"
	notes="Tailscale $version built from the official source with a custom feature set.

Each \`tailscale-custom-linux-<arch>\` binary is tailscaled. If the \`cli\` feature is enabled, it also works as the CLI when invoked as \`tailscale\`: \`ln -s tailscale-custom-linux-<arch> tailscale\`.

See enabled-features.txt and disabled-features.txt for the feature set."
	gh release create "$version" --title "$version" --notes "$notes" \
		${GITHUB_SHA:+--target "$GITHUB_SHA"} \
		"${binaries[@]}" enabled-features.txt disabled-features.txt
	exit 0
fi

existing="$(gh release view "$tag" --json assets --jq '.assets[].name')"
missing=()
for b in "${binaries[@]}"; do
	grep -qxF "$b" <<<"$existing" || missing+=("$b")
done
if [ "${#missing[@]}" -eq 0 ]; then
	echo "Release $version already has all built architectures; nothing to upload."
	exit 0
fi

# Appended binaries must match the feature set the release documents.
if grep -qxF enabled-features.txt <<<"$existing"; then
	tmp="$(mktemp -d)"
	gh release download "$tag" --pattern enabled-features.txt --dir "$tmp"
	if ! diff -u "$tmp/enabled-features.txt" enabled-features.txt; then
		echo "::error::Release $version was built with a different feature set (diff above). Use the same features, or delete the release first." >&2
		exit 1
	fi
else
	missing+=(enabled-features.txt disabled-features.txt)
fi

echo "Appending to release $version: ${missing[*]}"
gh release upload "$tag" "${missing[@]}"
