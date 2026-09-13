# Arcio OS

Stock Flatcar Container Linux turned into an Arcio appliance by configuration
only. No custom OS image, no package manager, nothing compiled.

```bash
./build.sh --fetch      # transpile butane.yaml into build/config.ign
```

Status: **the config works and has been booted end to end.** There is no
downloadable image yet. See the [roadmap](https://arcio.au/docs/roadmap/).

## Booting it for development

```bash
export ARCIO_DEV_SSH_KEY="$(cat ~/.ssh/id_ed25519.pub)"   # optional, see below
./build.sh

qm create 900 --name arcio-os --memory 4096 --cores 2 \
  --net0 virtio,bridge=vmbr0 --ostype l26 --scsihw virtio-scsi-single
qm importdisk 900 flatcar_production_qemu_image.img local-lvm --format raw
qm set 900 --scsi0 local-lvm:vm-900-disk-0 --boot order=scsi0
qm resize 900 scsi0 40G
qm set 900 --args "-fw_cfg name=opt/org.flatcar-linux/config,file=$PWD/build/config.ign"
qm start 900
```

The appliance prints its address and a generated console password to
`/etc/issue`, so the console login screen tells you where it is.

`ARCIO_DEV_SSH_KEY` is a development affordance. A shipped appliance carries no
key: you reach it on the console. Building one is impractical that way, because
reading a failed unit's journal needs a shell and the password is on a console
you cannot paste into. The build prints a warning when a key is injected.

## Verified against a real boot

Flatcar LTS **4081.3.10**, 2026-09-14. Everything here was measured, not
assumed, and several of them contradict what the documentation implies.

| | |
|---|---|
| Docker | 26.1.0, shipped as a systemd-sysext |
| `docker compose` | **Not present.** Added as a sysext from the Flatcar bakery |
| `docker-buildx` | Present, in `/usr/libexec/docker/cli-plugins` |
| `/usr` | Read-only, so `arcioctl` goes in `/opt/bin`, not `/usr/local/bin` |
| `/opt` | Writable as root, and a valid sysext hierarchy |
| Root partition | Auto-grows to fill the disk (40 GB gave 37.7 GB) |
| OEM partition | `sda6`, btrfs, mounts at `/oem` |

## Three things that cost a boot each

**Ignition carries configuration, not payload.** Inlining the 14 MB compose
sysext as base64 produced a 14.7 MB `config.ign`, and delivering that through
`fw_cfg` hung `ignition-fetch-offline` indefinitely: four minutes in, no
progress, no timeout, no boot. Anything measured in megabytes belongs in the
image.

**`overwrite: true` on files Flatcar already ships.** `/etc/flatcar/update.conf`
exists, Ignition refuses to replace an existing path by default, and the whole
config fails rather than that one file. The machine reboot-loops into an
emergency shell.

**`head` truncating a pipe kills the producer.** `tr ... | head -c 20` under
`set -o pipefail` makes `tr` die of SIGPIPE with status 141, which failed the
first-boot unit on every boot. `cut` reads to EOF and does not.

## The OS updater ships masked

Stock Flatcar schedules an update check about **two minutes after boot** against
`public.update.flatcar-linux.net` and lets `locksmithd` reboot to apply it.
Verified on the probe.

On an appliance that is two things nobody asked for: an outbound destination
that is not on the [published egress list](https://arcio.au/docs/network/), and
an unannounced reboot of the architecture repository.

Air-gapped mode could not have stopped either. It is an application-level
control and `update_engine` is a host process, so the switch customers are told
stops all outbound traffic would never have reached it.

So `update-engine` and `locksmithd` are **masked**, not merely disabled, since a
disabled unit can still be pulled in by a dependency. `update.conf` keeps
`GROUP=lts` and `REBOOT_STRATEGY=off` to decide what happens if somebody
unmasks them. OS updates are intended to arrive through `arcioctl`, alongside
application updates, where they are visible and scheduled.

## Still open

- **Baking the config into an image** so a customer imports a file rather than
  supplying Ignition. `/oem` is confirmed as the target.
- **Per-hypervisor artefacts.** VMware can take Ignition through OVF guestinfo,
  which also lets a customer override at deploy time; qcow2 and VHD cannot.
- **Disk sizing.** An image forces a number, and the minimum spec is still
  undocumented.
- **Air-gapped OS updates.** The mechanism exists (`arcioctl import` verifies a
  signed bundle); the packaging does not.
