#!/usr/bin/env bash
set -euo pipefail

# Build the offline image bundle.
#
#   ./bundle.sh                 pull the pinned images and save them
#   ARCIO_VERSION=1.0.0 ./bundle.sh
#
# Output: build/images.tar.gz, which bake.sh writes onto the appliance's root
# partition and first boot loads before starting anything.
#
# Run this anywhere with Docker. It is deliberately separate from bake.sh,
# which needs root and loop devices but not a Docker daemon, so neither script
# drags the other's dependencies along.
#
# ── Why a tarball and not a pre-seeded /var/lib/docker ──────────────────────
#
# Copying a populated Docker data directory into the image would skip the load
# step and boot faster. It also couples the appliance to the storage driver and
# the daemon version that produced it, and a mismatch fails in ways that are
# tedious to diagnose from a console.
#
# `docker save` and `docker load` are a documented, versioned interface between
# two Docker daemons. `arcioctl import` already uses the same one for air-gapped
# updates, so there is one mechanism here rather than two.

cd "$(dirname "$0")"

ARCIO_VERSION="${ARCIO_VERSION:-edge}"
BUILD=build
mkdir -p "${BUILD}"

command -v docker >/dev/null || { echo "needs docker" >&2; exit 1; }

say() { printf '\033[0;36m›\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m✓\033[0m %s\n' "$*"; }

# Caddy is included even though it only runs under the `tls` profile. An
# air-gapped site that decides it wants TLS should not discover that the one
# thing it needs is the one thing that has to be downloaded.
IMAGES=(
  "ghcr.io/element-digital/arcio:${ARCIO_VERSION}"
  "postgres:16-alpine"
  "caddy:2-alpine"
)

for image in "${IMAGES[@]}"; do
  say "Pulling ${image}..."
  docker pull -q "${image}"
done

say "Saving..."
# Piped through gzip rather than saved and then compressed: the uncompressed
# tar is well over a gigabyte and there is no reason for it to exist on disk.
docker save "${IMAGES[@]}" | gzip -1 > "${BUILD}/images.tar.gz"

sha256sum "${BUILD}/images.tar.gz" | tee "${BUILD}/images.tar.gz.sha256"
ok "${BUILD}/images.tar.gz ($(du -h "${BUILD}/images.tar.gz" | cut -f1))"
echo
echo "Now: sudo ./bake.sh <flatcar image>"
