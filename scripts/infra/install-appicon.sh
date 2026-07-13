#!/usr/bin/env bash
# Install a pinned appicon release binary (checksum-verified).
# Used by the dock CSS proof — Waybar only shells out to `appicon resolve`.
set -euo pipefail

APPICON_VERSION="${APPICON_VERSION:-v0.2.1}"
# SHA256 of release archives (from https://github.com/bolens/appicon/releases SHA256SUMS).
APPICON_SHA256_AMD64="${APPICON_SHA256_AMD64:-5bb3f1394a10017298de0061dc26fe223dc30de18bd374b4437967d91b75b45a}"
APPICON_SHA256_ARM64="${APPICON_SHA256_ARM64:-4c7dcae41158aec643e92e525d36bbc7bcef369dea8d0c35f78eb48a132f6fa8}"

DEST_DIR="${APPICON_INSTALL_DIR:-${HOME}/.local/bin}"
REPO="${APPICON_REPO:-bolens/appicon}"

arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64)
    asset_arch="amd64"
    expect_sha="$APPICON_SHA256_AMD64"
    ;;
  aarch64 | arm64)
    asset_arch="arm64"
    expect_sha="$APPICON_SHA256_ARM64"
    ;;
  *)
    printf 'unsupported arch: %s (need amd64 or arm64)\n' "$arch" >&2
    exit 1
    ;;
esac

archive_name="appicon_${APPICON_VERSION}_linux_${asset_arch}.tar.gz"
url="https://github.com/${REPO}/releases/download/${APPICON_VERSION}/${archive_name}"

cache="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-appicon"
mkdir -p "$cache" "$DEST_DIR"
archive="$cache/$archive_name"

if [ ! -f "$archive" ]; then
  echo "Downloading appicon ${APPICON_VERSION} (${asset_arch})..." >&2
  curl -fsSL -o "$archive" "$url"
fi

got_sha="$(sha256sum "$archive" | awk '{print $1}')"
if [ "$got_sha" != "$expect_sha" ]; then
  printf 'SHA256 mismatch for %s\n  expected: %s\n  got:      %s\n' \
    "$archive_name" "$expect_sha" "$got_sha" >&2
  rm -f "$archive"
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
tar -xzf "$archive" -C "$tmpdir"
if [ ! -x "$tmpdir/appicon" ]; then
  printf 'archive missing appicon binary: %s\n' "$archive_name" >&2
  exit 1
fi

install -m 755 "$tmpdir/appicon" "$DEST_DIR/appicon"
# Drop any negative-cache from a prior bar session without appicon installed.
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/waybar/appicon-bin-miss" 2>/dev/null || true
echo "installed: $DEST_DIR/appicon ($("$DEST_DIR/appicon" version 2>/dev/null || echo "$APPICON_VERSION"))"
echo "Enable dock icons: set icons.appicon.enabled=true in data/waybar-settings.jsonc, then make generate."
