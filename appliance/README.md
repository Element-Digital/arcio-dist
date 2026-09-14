# Arcio OS

Stock Flatcar Container Linux turned into an Arcio appliance by configuration
only. No custom OS image, no package manager, nothing compiled.

```bash
./build.sh --fetch      # transpile butane.yaml into build/config.ign
```

Status: **a baked qcow2 boots into a working Arcio with nothing supplied by the
hypervisor, and does it with no route to any registry.** qcow2, OVA and VHDX
all build. Nothing is published yet. See the
[roadmap](https://arcio.au/docs/roadmap/).

## Building an image

```bash
./build.sh --fetch                                   # config.ign + the sysext
sudo ./bake.sh flatcar_production_qemu_image.img     # -> build/arcio-os-<ver>.qcow2
```

`bake.sh` writes `config.ign` and the compose sysext onto the **OEM partition**,
which is the partition Flatcar provides for this and the only one it touches. It
also strips `flatcar.autologin` from the OEM `grub.cfg`.

That last one is not cosmetic. Flatcar's QEMU image ships autologin, so the
console comes up as a shell with sudo and no password. On a developer image you
booted yourself that is convenient; on an appliance somebody imports it is an
unauthenticated root shell, and it makes the password first boot generates
purely decorative. Found by screendumping the M1 console and seeing a
`core@arcio` prompt nobody had logged into.

Verified on a baked image with no `args` on the VM at all:

```
/oem/config.ign                       12008 bytes
/oem/docker-compose.raw            11063296
/etc/extensions/docker-compose.raw 11063296   (copied at first boot)

flatcar.autologin   not on the kernel command line
firstboot log       0 network calls, sysext came from /oem
update-engine       masked        locksmithd  masked
health              {"ok":true,"version":"0.10.0"}
```

## Offline

```bash
./bundle.sh                                          # -> build/images.tar.gz
./build.sh --fetch
sudo ./bake.sh flatcar_production_qemu_image.img     # picks the bundle up
```

`bundle.sh` saves the three images compose needs. `bake.sh` writes the bundle to
the **root** partition, because OEM is 128 MB and the bundle is about 400 MB
compressed from 1.1 GB of images. `arcio-load-images.service` loads it before
`arcio.service` and deletes it afterwards, since by then it is a duplicate of
what is already in Docker's storage.

The bundle is optional. Without it the appliance pulls from `ghcr.io` like any
other install, and `bake.sh` says so loudly, because an image that quietly needs
a registry is the one that gets handed to an air-gapped customer.

**Verified with egress actually blocked**, on a VM with a Proxmox firewall
policy of `policy_out: DROP` and only local VLANs and DHCP permitted:

```
ghcr.io                       UNREACHABLE
arcio-load-images.service     Loaded image: postgres:16-alpine
                              Loaded image: caddy:2-alpine
                              Loaded image: ghcr.io/element-digital/arcio:edge
                              Finished, 73 seconds
/opt/arcio/images.tar.gz      deleted after load
containers                    arcio-arcio-1  Up (healthy)
                              arcio-db-1     Up (healthy)
health                        {"ok":true,"version":"0.10.0"}
```

Two notes from building that test. The first version of the firewall rule
blocked DHCP as well as egress, so the appliance came up with no address at all
— which is a real scenario on a network without a DHCP server, and it found a
bug where first boot wrote `ARCIO_BASE_URL=http://:3001` and carried on. And
`arcio-load-images` is its own unit rather than part of first boot, because
first boot installs the compose sysext, which re-merges `/usr`, and Docker is
itself delivered as a sysext living in `/usr`.

Caddy is in the bundle despite only running under the `tls` profile. An
air-gapped site that later decides it wants TLS should not find that the one
thing it needs is the one thing it has to download.

## Artefacts

```bash
./package.sh build/arcio-os-4081.3.10.qcow2
```

| | | |
|---|---|---|
| `.qcow2` | Proxmox, KVM, libvirt | **boot-tested** |
| `.ova` | VMware ESXi, vSphere, Workstation | structure only |
| `.vhdx` | Hyper-V **generation 2** | structure only |

There is no ESXi or Hyper-V here, so the OVA and VHDX are validated and not
booted: the tar order is asserted, the manifest checksums are verified against
the files, and `qemu-img` reads both disks back. Only the qcow2 has run.

Two things in the OVA are load-bearing and easy to get wrong. The tar order is
descriptor, manifest, disks, because readers stream it and a misordered archive
fails with a message about a missing descriptor that reads like a corrupt
download. And `firmware=efi` is set, because the image is GPT with an EFI System
Partition and no BIOS bootloader, so a default-firmware VM imports cleanly and
then fails to boot with no obvious cause. **Hyper-V must be generation 2** for
the same reason.

## Sizing

Measured on an idle appliance with a seeded but empty model, not estimated:

| | |
|---|---|
| Memory, whole VM | 791 MB used of 3915 |
| Memory, containers | Arcio 161 MB, PostgreSQL 65 MB |
| Disk | 1.7 GB used of 36 GB |
| Of which images | 1.1 GB |
| Database | 12 MB |
| Load average | 0.08 |

So the floor is **2 vCPU, 4 GB, 40 GB**, which is what the OVA declares.

Read that as a floor and not a sizing guide. It is an empty install doing
nothing: the figures that matter under load are graph walks, report
aggregations and integration syncs, and none of those have been measured. The
database is the part that grows, and it grows with the size of the model and
how much history is kept, not with the number of users.

40 GB is generous on purpose. The disk is sparse, so an unused gigabyte costs
nothing in the artefact or on the datastore, and growing a VMware disk later is
a maintenance window nobody wants for a product whose job is to avoid those.

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
unmasks them.

That creates an obligation, and `arcioctl` meets it:

```bash
arcioctl os-status            # version, channel, what is available, is one staged
sudo arcioctl os-update       # take the current LTS
sudo arcioctl os-update 4081.3.9
```

`os-update` backs up first, then drives `flatcar-update`, which runs a temporary
update service on localhost and writes to the passive partition. Nothing changes
until you reboot, and if the new version does not come up the bootloader returns
to the one that did.

It re-masks both units afterwards and rewrites `update.conf`.
`flatcar-update --disable-afterwards` sets `SERVER=disabled` but leaves
`update-engine` unmasked and says nothing about `locksmithd`, so without that
step a single OS update would quietly restore the reboot manager the appliance
exists without.

Both commands refuse on the Docker install method, where the host is yours.

**Verified end to end**, including the reboot:

```
before     4081.3.10, both units masked
os-update  staged 4081.3.9 to the passive partition
reboot
after      4081.3.9      both units still masked
           update.conf   GROUP=lts, REBOOT_STRATEGY=off
           arcio.service active,  health {"ok":true,"version":"0.10.0"}
           backup timer  active
```

That was also the appliance's first reboot of any kind, so it is the first
evidence that the compose sysext survives one. It does, and it survives an OS
version change with it: `oem-qemu.raw` re-pointed itself at the 4081.3.9 file
while `docker-compose.raw` stayed put.

## Still open

- **Boot-testing the OVA and VHDX.** Both are built and structurally valid;
  neither has been imported into the hypervisor it is for.
- **Publishing.** Images need signing and somewhere to live. Cosign on the blob
  and a GitHub Release is the obvious shape, and `arcioctl import` already
  verifies blob signatures.
