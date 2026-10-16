#!/usr/bin/env bash
# fm-install-herdr.sh - install CI's pinned, verified Herdr build.
#
# Single owner of the exact Herdr version, official release asset URL, and
# SHA-256 pin used by the required real-Herdr CI lane. Never installs a
# floating package-manager latest.
#
# Usage:
#   fm-install-herdr.sh <destination-directory>
#
# Pins Herdr v0.9.5 (client protocol 22), the current stable release; the
# protocol floor stays 16. Re-verified for this bump: linux-x86_64 asset
# sha256'd locally, all four digests match GitHub's official asset digests.
# Selects the official GitHub Releases asset for the host OS/arch, downloads
# with a bounded max size, verifies SHA-256 before install, then refuses to
# finish unless the binary reports the exact pin version and a client protocol
# at or above the required floor (16 for the real-Herdr family).
set -eu

# Exact pin - change only with a re-verified real-Herdr matrix.
FM_HERDR_CI_VERSION=0.9.5
FM_HERDR_CI_TAG="v${FM_HERDR_CI_VERSION}"
FM_HERDR_CI_MIN_PROTOCOL=16
# Bounded download ceiling (bytes). The largest official 0.9.5 asset is 30,285,672 bytes (~29 MiB).
FM_HERDR_CI_MAX_BYTES=40000000
FM_HERDR_CI_REPO=herdrdev/herdr

die() {
  printf 'fm-install-herdr.sh: %s\n' "$*" >&2
  exit 1
}

DESTINATION=${1:?usage: fm-install-herdr.sh <destination-directory>}

os=$(uname -s)
arch=$(uname -m)
case "${os}-${arch}" in
  Linux-x86_64)
    ASSET=herdr-linux-x86_64
    SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
    ;;
  Linux-aarch64|Linux-arm64)
    ASSET=herdr-linux-aarch64
    SHA256=17d7536f2da50859523680ef279dffcac8e4a235f4e46fe8da6c2ec44141897c
    ;;
  Darwin-arm64)
    ASSET=herdr-macos-aarch64
    SHA256=fb77c2232a05a8035421382c894392f4174e4e38a18e48af3dd0290157c3a7e2
    ;;
  Darwin-x86_64)
    ASSET=herdr-macos-x86_64
    SHA256=5fb0a908ec7f6745e3e245738b06bfad56c46391c391ab3c0955fbead01f1369
    ;;
  *)
    die "unsupported platform ${os}-${arch}; official Herdr assets are linux/macos x86_64 and aarch64"
    ;;
esac

URL="https://github.com/${FM_HERDR_CI_REPO}/releases/download/${FM_HERDR_CI_TAG}/${ASSET}"
TMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/fm-herdr.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

printf 'fm-install-herdr.sh: downloading %s from %s\n' "$ASSET" "$URL" >&2
# --fail: HTTP errors; --location: follow redirects; --max-filesize: bound.
curl -fsSL --max-filesize "$FM_HERDR_CI_MAX_BYTES" "$URL" -o "$TMP/$ASSET" \
  || die "download failed for $URL (bounded at $FM_HERDR_CI_MAX_BYTES bytes)"

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA256=$(sha256sum "$TMP/$ASSET" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA256=$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')
else
  die "need sha256sum or shasum to verify the Herdr asset"
fi

[ "$ACTUAL_SHA256" = "$SHA256" ] || die "checksum mismatch for $ASSET (expected $SHA256, got $ACTUAL_SHA256)"

mkdir -p "$DESTINATION"
install -m 0755 "$TMP/$ASSET" "$DESTINATION/herdr"

# Post-install version and protocol gates (no floating latest).
installed_version=$("$DESTINATION/herdr" --version 2>/dev/null | awk '{print $2; exit}')
[ "$installed_version" = "$FM_HERDR_CI_VERSION" ] \
  || die "installed herdr version is '${installed_version:-<empty>}', expected exact pin $FM_HERDR_CI_VERSION"

status=$("$DESTINATION/herdr" status --json 2>/dev/null) \
  || die "could not run 'herdr status --json' after install"
protocol=$(printf '%s' "$status" | jq -r '.client.protocol // empty' 2>/dev/null) \
  || die "jq is required to parse herdr status after install"
case "$protocol" in
  ''|*[!0-9]*) die "could not read herdr client protocol from status --json" ;;
esac
[ "$protocol" -ge "$FM_HERDR_CI_MIN_PROTOCOL" ] \
  || die "herdr protocol $protocol is below the required floor $FM_HERDR_CI_MIN_PROTOCOL"

printf 'fm-install-herdr.sh: installed herdr %s (protocol %s) to %s\n' \
  "$installed_version" "$protocol" "$DESTINATION/herdr" >&2
"$DESTINATION/herdr" --version
