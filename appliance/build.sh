#!/usr/bin/env bash
set -euo pipefail

# Build the Arcio OS Ignition config.
#
#   ./build.sh              transpile only, into build/config.ign
#   ./build.sh --fetch      refresh the vendored inputs first
#
# Produces an Ignition config, not a disk image. Baking it into a Flatcar image
# is M2 and is a separate script, because the two have different dependencies:
# this needs butane and curl, that needs loopback mounts and root.
#
# ── Why the inputs are vendored into build/ ─────────────────────────────────
#
# Butane's `local:` file references are resolved at transpile time from
# --files-dir, so everything the appliance ships has to be on disk here first.
# That is a feature rather than a chore: the config that comes out is complete,
# so a first boot needs no network, which is what an air-gapped appliance
# requires and what stops a boot hanging on somebody else's outage.

cd "$(dirname "$0")"

FLATCAR_CHANNEL="${FLATCAR_CHANNEL:-lts}"
COMPOSE_SYSEXT_VERSION="${COMPOSE_SYSEXT_VERSION:-5.5.1}"
ARCH="${ARCH:-x86-64}"

BUILD=build
mkdir -p "${BUILD}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "need $1" >&2; exit 1; }; }
say() { printf '\033[0;36m›\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m✓\033[0m %s\n' "$*"; }

need curl

if [ "${1:-}" = "--fetch" ] || [ ! -f "${BUILD}/docker-compose.raw" ]; then
  say "Fetching the compose sysext (${COMPOSE_SYSEXT_VERSION})..."
  # Flatcar ships Docker itself as a sysext and does not ship compose at all,
  # so this is the supported way to add it rather than a workaround. Verified
  # on 4081.3.10: `docker compose` does not exist on a stock image.
  curl -fsSL -o "${BUILD}/docker-compose.raw" \
    "https://github.com/flatcar/sysext-bakery/releases/download/docker-compose-${COMPOSE_SYSEXT_VERSION}/docker-compose-${COMPOSE_SYSEXT_VERSION}-${ARCH}.raw"

  say "Fetching SHA256SUMS..."
  curl -fsSL -o "${BUILD}/sysext.SHA256SUMS" \
    "https://github.com/flatcar/sysext-bakery/releases/download/docker-compose-${COMPOSE_SYSEXT_VERSION}/SHA256SUMS"

  # Checked rather than trusted. This blob is merged into /usr on every boot,
  # so it is as privileged as anything on the appliance.
  ( cd "${BUILD}" \
    && grep "docker-compose-${COMPOSE_SYSEXT_VERSION}-${ARCH}.raw" sysext.SHA256SUMS \
       | sed "s|docker-compose-${COMPOSE_SYSEXT_VERSION}-${ARCH}.raw|docker-compose.raw|" \
       | sha256sum -c - )
  ok "sysext verified"
fi

# compose.yaml and arcioctl come from this repo, one directory up. The
# appliance and the Docker install method run the same two files; that is the
# "one artefact, tested once" decision in docs/distribution.md, and copying
# rather than re-authoring them is what keeps it true.
say "Vendoring compose.yaml and arcioctl..."
cp ../compose.yaml "${BUILD}/compose.yaml"
cp ../bin/arcioctl "${BUILD}/arcioctl"

need butane

# A development affordance, and deliberately not a product one.
#
# The shipped appliance has no SSH key in it: a customer reaches it on the
# console with the password first boot generates. That is also unworkable while
# building the thing, because reading a failed unit's journal needs a shell and
# the password lives on a console you cannot paste into.
#
# ARCIO_DEV_SSH_KEY adds one for a build you are about to throw away. It is an
# environment variable rather than a file in the repo so it cannot be committed
# by accident, and the banner below means nobody ships one without seeing it.
SRC=butane.yaml
if [ -n "${ARCIO_DEV_SSH_KEY:-}" ]; then
  printf '\033[0;33m!\033[0m %s\n' "Injecting a development SSH key. DO NOT SHIP THIS IMAGE."
  SRC="${BUILD}/butane-dev.yaml"
  awk -v key="${ARCIO_DEV_SSH_KEY}" '
    /^      groups:$/ && !done { print "      ssh_authorized_keys:"; print "        - " key; done=1 }
    { print }
  ' butane.yaml > "${SRC}"
  grep -q 'ssh_authorized_keys' "${SRC}" || { echo "failed to inject the key" >&2; exit 1; }
fi

say "Transpiling..."
butane --strict --files-dir . "${SRC}" -o "${BUILD}/config.ign"

ok "${BUILD}/config.ign ($(wc -c < "${BUILD}/config.ign") bytes)"
echo
echo "Boot it on Proxmox with:"
echo "  qm set <vmid> --args \"-fw_cfg name=opt/org.flatcar-linux/config,file=\$PWD/${BUILD}/config.ign\""
