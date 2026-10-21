#!/usr/bin/env bash
# Publishes tailscale-<release-name>-<arch> binaries to the GitHub release
# <release-name>, which is <tailscale-version>-<feature hash>, so each feature
# set of a version gets its own release.
#
# - No such release: create it with all binaries. The description lists the
#   enabled and disabled features and the text the feature hash comes from.
# - Release exists: upload only the architectures it doesn't have yet. If it
#   already has all of them, do nothing.
#
# Usage: scripts/release.sh <release-name> <tailscale-version> <dist-dir>
# <dist-dir> holds the binaries and the files from scripts/resolve-features.sh.
# Needs the gh CLI with GH_TOKEN and GH_REPO (or a repo checkout) set.
set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "usage: $0 <release-name> <tailscale-version> <dist-dir>" >&2
	exit 2
fi
name="$1" version="$2"
cd "$3"

shopt -s nullglob
binaries=("tailscale-$name-"*)
if [ "${#binaries[@]}" -eq 0 ]; then
	echo "::error::No tailscale-$name-<arch> binaries in $3" >&2
	exit 1
fi
for f in enabled-features.txt disabled-features.txt feature-hash.txt feature-hash-input.txt; do
	[ -f "$f" ] || { echo "::error::Missing $f in $3" >&2; exit 1; }
done
hash="$(cat feature-hash.txt)"
if [ "$name" != "$version-$hash" ]; then
	echo "::error::Release name $name doesn't match $version-$hash" >&2
	exit 1
fi

tag="$(gh release list --limit 1000 --json name,tagName |
	jq -r --arg n "$name" 'first(.[] | select(.name == $n) | .tagName) // empty')"

if [ -z "$tag" ]; then
	# Features as `a`, `b`, ... or "None".
	# shellcheck disable=SC2016 # the backticks are Markdown, not substitution
	features() {
		if [ -s "$1" ]; then sed 's/.*/`&`/' "$1" | paste -sd, | sed 's/,/, /g'; else echo None; fi
	}
	notes="$(mktemp)"
	cat >"$notes" <<EOF
Tailscale $version built from the official source with a custom feature set.

Each \`tailscale-$name-<arch>\` binary is tailscaled. If the \`cli\` feature is enabled, it also works as the CLI when invoked as \`tailscale\`: \`ln -s tailscale-$name-<arch> tailscale\`.

### Enabled features ($(grep -c . enabled-features.txt || true))

$(features enabled-features.txt)

### Disabled features ($(grep -c . disabled-features.txt || true))

$(features disabled-features.txt)

### Feature hash

\`$hash\` is the first 12 hex digits of the SHA-256 of this text (no trailing newline):

\`\`\`text
$(cat feature-hash-input.txt)
\`\`\`
EOF
	echo "Creating release $name with: ${binaries[*]}"
	gh release create "$name" --title "$name" --notes-file "$notes" \
		${GITHUB_SHA:+--target "$GITHUB_SHA"} "${binaries[@]}"
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

echo "Appending to release $name: ${missing[*]}"
gh release upload "$tag" "${missing[@]}"
