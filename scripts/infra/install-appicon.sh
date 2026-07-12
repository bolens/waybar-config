#!/usr/bin/env bash
# Install a pinned appicon release binary (checksum-verified).
# Used by the dock CSS proof — Waybar only shells out to `appicon resolve`.
set -euo pipefail

APPICON_VERSION="${APPICON_VERSION:-v0.1.1}"
# SHA256 of release archives (from https://github.com/bolens/appicon/releases).
APPICON_SHA256_AMD64="${APPICON_SHA256_AMD64:-4332b2e33bc39c095fd1455345717f53bcedde5a69d60fc4991674ce2ae43a25}"
APPICON_SHA256_ARM64="${APPICON_SHA256_ARM64:-17af174714398ad772dac116be2bb214e405daafde8348b135f3e62cbafdcf27}"

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
echo "installed: $DEST_DIR/appicon ($("$DEST_DIR/appicon" version 2>/dev/null || echo "$APPICON_VERSION"))"
echo "Enable dock icons: set icons.appicon.enabled=true in data/waybar-settings.jsonc, then make generate."
