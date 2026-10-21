#!/usr/bin/env bash
# Publishes tailscale-custom binaries to the GitHub release <release-name>,
# which is <tailscale-version>-<feature hash>, so each feature set of a version
# gets its own release.
#
# - No such release: create it with all binaries and the feature lists.
# - Release exists: upload only the architectures it doesn't have yet. If it
#   already has all of them, do nothing.
#
# Usage: scripts/release.sh <release-name> <tailscale-version> <dist-dir>
# Needs the gh CLI with GH_TOKEN and GH_REPO (or a repo checkout) set.
set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "usage: $0 <release-name> <tailscale-version> <dist-dir>" >&2
	exit 2
fi
name="$1" version="$2"
cd "$3"

shopt -s nullglob
binaries=(tailscale-custom-linux-*)
if [ "${#binaries[@]}" -eq 0 ]; then
	echo "::error::No tailscale-custom binaries in $3" >&2
	exit 1
fi
for f in enabled-features.txt disabled-features.txt; do
	[ -f "$f" ] || { echo "::error::Missing $f in $3" >&2; exit 1; }
done

tag="$(gh release list --limit 1000 --json name,tagName |
	jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .tagName) // empty')"

if [ -z "$tag" ]; then
	echo "Creating release $name with: ${binaries[*]}"
	notes="Tailscale $version built from the official source with a custom feature set.

Each \`tailscale-custom-linux-<arch>\` binary is tailscaled. If the \`cli\` feature is enabled, it also works as the CLI when invoked as \`tailscale\`: \`ln -s tailscale-custom-linux-<arch> tailscale\`.

See enabled-features.txt and disabled-features.txt for the feature set."
	gh release create "$name" --title "$name" --notes "$notes" \
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
	echo "Release $name already has all built architectures; nothing to upload."
	exit 0
fi
for f in enabled-features.txt disabled-features.txt; do
	grep -qxF "$f" <<<"$existing" || missing+=("$f")
done

echo "Appending to release $name: ${missing[*]}"
gh release upload "$tag" "${missing[@]}"
