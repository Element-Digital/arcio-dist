#!/usr/bin/env bash
set -euo pipefail

# Bake the Arcio OS config into a Flatcar image.
#
#   sudo ./bake.sh flatcar_production_qemu_image.img
#
# Output: build/arcio-os-<version>.qcow2, which boots into a configured Arcio
# with nothing supplied by the hypervisor. That is the difference between an
# appliance and a DIY exercise: the customer imports one file.
#
# Needs root, because it loop-mounts partitions. Everything it writes goes on
# the **OEM partition**, which is the partition Flatcar provides for exactly
# this and is the only one we touch.
#
# ── What goes on, and why there ─────────────────────────────────────────────
#
#   config.ign            the Ignition config from build.sh
#   docker-compose.raw    the compose sysext, ~14MB
#   grub.cfg              rewritten, see below
#
# The sysext is a file on the partition rather than content inside config.ign
# because Ignition is not a bulk transport: inlining it as base64 produced a
# 14.7MB config and hung ignition-fetch-offline indefinitely. First boot copies
# it to /etc/extensions, so a shipped appliance needs no network to finish
# booting, which is what air-gapped customers require.

cd "$(dirname "$0")"

SRC="${1:-}"
BUILD=build
OEM_MNT="${OEM_MNT:-/mnt/arcio-oem}"

[ -n "${SRC}" ] || { echo "usage: sudo ./bake.sh <flatcar image>" >&2; exit 1; }
[ -f "${SRC}" ] || { echo "no such image: ${SRC}" >&2; exit 1; }
[ "$(id -u)" = "0" ] || { echo "needs root: loop-mounts partitions" >&2; exit 1; }
[ -f "${BUILD}/config.ign" ] || { echo "run ./build.sh first" >&2; exit 1; }
[ -f "${BUILD}/docker-compose.raw" ] || { echo "run ./build.sh --fetch first" >&2; exit 1; }

say() { printf '\033[0;36m›\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m✓\033[0m %s\n' "$*"; }

VERSION="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$(cat version.txt 2>/dev/null || echo unknown)" | head -1 || true)"
VERSION="${VERSION:-unknown}"
OUT="${BUILD}/arcio-os-${VERSION}.qcow2"
RAW="${BUILD}/work.raw"

LOOP=""
cleanup() {
  mountpoint -q "${OEM_MNT}" && umount "${OEM_MNT}" || true
  [ -n "${LOOP}" ] && losetup -d "${LOOP}" 2>/dev/null || true
}
trap cleanup EXIT

say "Converting to raw..."
qemu-img convert -O raw "${SRC}" "${RAW}"

say "Attaching..."
LOOP="$(losetup -fP --show "${RAW}")"

# Partition 6 is OEM on every Flatcar image. Asserted rather than assumed: a
# layout change would otherwise write the config into whatever is at p6 now.
#
# blkid, not `lsblk -no PARTLABEL`. On a loop device lsblk returns an empty
# string for PARTLABEL while blkid reads it correctly, so the lsblk version of
# this check failed on its own image.
LABEL="$(blkid -s PARTLABEL -o value "${LOOP}p6")"
[ "${LABEL}" = "OEM" ] || { echo "p6 is '${LABEL}', not OEM. Layout changed; fix this script." >&2; exit 1; }

mkdir -p "${OEM_MNT}"
mount "${LOOP}p6" "${OEM_MNT}"

say "Writing the config..."
install -m 0644 "${BUILD}/config.ign" "${OEM_MNT}/config.ign"

say "Writing the compose sysext..."
install -m 0644 "${BUILD}/docker-compose.raw" "${OEM_MNT}/docker-compose.raw"

# ── autologin ───────────────────────────────────────────────────────────────
#
# Flatcar's QEMU image ships `flatcar.autologin` on the kernel command line, so
# the console comes up as a logged-in shell with sudo and no password. That is
# right for a developer image you booted yourself and wrong for an appliance
# somebody imports, where it makes the console an unauthenticated root shell
# and the password first boot generates purely decorative.
#
# Found by screendumping the console during M1 and seeing a `core@arcio` prompt
# nobody had logged into.
if grep -q 'flatcar.autologin' "${OEM_MNT}/grub.cfg"; then
  say "Removing flatcar.autologin..."
  sed -i 's/[[:space:]]*flatcar\.autologin//' "${OEM_MNT}/grub.cfg"
  grep -q 'flatcar.autologin' "${OEM_MNT}/grub.cfg" && { echo "autologin survived the edit" >&2; exit 1; }
fi

sync
umount "${OEM_MNT}"
losetup -d "${LOOP}"; LOOP=""

say "Compressing to qcow2..."
qemu-img convert -O qcow2 -c "${RAW}" "${OUT}"
rm -f "${RAW}"

sha256sum "${OUT}" | tee "${OUT}.sha256"
ok "${OUT} ($(du -h "${OUT}" | cut -f1))"
echo
echo "Import on Proxmox with:"
echo "  qm importdisk <vmid> ${OUT} <storage>"
