# tailscale-custom-builds

Custom builds of [Tailscale](https://tailscale.com) for Linux: pick the
features and architectures, and the workflow cross-compiles `tailscaled` from
the official [tailscale/tailscale](https://github.com/tailscale/tailscale)
source with everything else compiled out.

## Running the workflow

Run **Actions → Build tailscale-custom → Run workflow**. The inputs:

| Input | Default | Meaning |
| --- | --- | --- |
| `features` | every feature | Comma-separated features to include. Delete the ones you don't need. Features that a listed feature depends on are kept automatically. |
| `arch` | every architecture | Comma-separated architectures to build. Delete the ones you don't need. |
| `version` | latest stable | Tailscale tag to build, such as `v1.104.2`. |
| `release` | `false` | Publish the binaries to a GitHub release (see below). |

Unknown feature or architecture names fail the run before anything is built.
The `features` default lists the features of Tailscale v1.104.2. Features added
in later versions are compiled out unless you add them to the list. Run
`go run ./cmd/featuretags --list` in the Tailscale source to see them.

Each build produces `tailscale-custom-linux-<arch>`. With `release` off, the
binaries and the feature lists are kept as workflow artifacts for 7 days.

### Releases

With `release` on, the binaries go to the release named
`<version>-<feature hash>`, for example `v1.104.2-bac268ed04d5` for every
feature of v1.104.2. Each feature set of a version gets its own release.

- If there is no such release, it is created with every binary,
  `enabled-features.txt` and `disabled-features.txt`.
- If the release exists, only binaries for architectures it doesn't have yet
  are uploaded. If it already has all of them, nothing changes.

The feature hash covers the features actually in the binary, including the
ones added as dependencies, so inputs that produce the same binary share a
release. The names are sorted in byte order, joined with commas, hashed with
SHA-256 and cut to 12 hex digits. To check a release's hash:

```sh
LC_ALL=C sort enabled-features.txt | paste -sd, | tr -d '\n' | sha256sum | cut -c1-12
```

## Architectures

| `arch` | Notes |
| --- | --- |
| `386`, `amd64`, `arm64`, `riscv64` | |
| `arm` | `GOARM=5`, runs on ARMv5 and later, as in official builds |
| `geode` | 386 with `GO386=softfloat`, for AMD Geode, as in official builds |
| `mips`, `mipsle` | `GOMIPS=softfloat`, runs without an FPU, as in official builds |
| `mips64`, `mips64le` | |
| `loong64`, `ppc64le`, `s390x` | Not built by Tailscale officially |

All binaries are statically linked pure Go (`CGO_ENABLED=0`), so they don't
depend on the system's libc. They need Linux 3.2 or later.

## Using a binary

The binary is `tailscaled`. If the `cli` feature is enabled, invoking it under
the name `tailscale` (through a symlink) runs the CLI:

```sh
chmod +x tailscale-custom-linux-<arch>
ln -s tailscale-custom-linux-<arch> tailscale

./tailscale-custom-linux-<arch> --statedir=/path/to/persistent/tailscale &
./tailscale up
```

If the device has no `/dev/net/tun`, start the daemon with
`--tun=userspace-networking` (needs the `netstack` feature). If
`grep -w tun /proc/misc` prints `200 tun`, the kernel has TUN and only the
device node is missing: `mkdir -p /dev/net && mknod /dev/net/tun c 10 200`.

## Building locally

```sh
docker run --rm -v "$PWD:/work" -w /work -e OWNER="$(id -u):$(id -g)" ubuntu:24.04 bash -c '
  set -e
  apt-get update -qq
  apt-get install -y -qq git curl ca-certificates >/dev/null
  git clone --branch v1.104.2 https://github.com/tailscale/tailscale /tmp/tailscale
  scripts/resolve-features.sh /tmp/tailscale "cli,netstack,dns,advertiseroutes" dist
  scripts/build.sh /tmp/tailscale mipsle "$(cat dist/build-tags.txt)" dist
  chown -R "$OWNER" dist'
```

The scripts:

- `scripts/resolve-features.sh` validates the feature list, adds
  dependencies, and writes `enabled-features.txt`, `disabled-features.txt`,
  `build-tags.txt` and `feature-hash.txt`.
- `scripts/build.sh` builds one architecture with Tailscale's Go fork, pinned
  by the source tree's `go.toolchain.rev`, as official releases do.
- `scripts/resolve-archs.sh` validates the architecture list for the build
  matrix.
- `scripts/release.sh` creates or appends to the release.
