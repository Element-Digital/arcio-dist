#!/usr/bin/env bash
set -euo pipefail

# Turn the baked qcow2 into the artefacts each hypervisor actually accepts.
#
#   ./package.sh build/arcio-os-4081.3.10.qcow2
#
# Emits, beside the input:
#
#   .qcow2    Proxmox, KVM, libvirt          (the input, unchanged)
#   .ova      VMware ESXi, vSphere, Workstation
#   .vhdx     Hyper-V, generation 2
#
# No root needed. This only converts and tars; bake.sh did the part that
# required mounting anything.
#
# ── On the OVA ──────────────────────────────────────────────────────────────
#
# An OVA is a tar with a strict order: the descriptor first, then the manifest,
# then the disks. Readers stream it, so a tar whose entries are in a different
# order fails on import with a message about a missing descriptor, which sounds
# like a corrupt file and is not.
#
# The disk is streamOptimized VMDK, which is the only subformat the OVF spec
# allows inside an OVA, and lsilogic rather than pvscsi because it needs no
# driver the guest might not have.
#
# ── Not boot-tested ─────────────────────────────────────────────────────────
#
# There is no ESXi or Hyper-V here, so these are structurally validated and
# nothing more: the tar order is asserted, the manifest checksums are verified
# against the files, and qemu-img reads both disks back. The qcow2 is the only
# artefact that has been booted. Say so until somebody imports one.

cd "$(dirname "$0")"

SRC="${1:-}"
[ -n "${SRC}" ] || { echo "usage: ./package.sh <baked qcow2>" >&2; exit 1; }
[ -f "${SRC}" ] || { echo "no such image: ${SRC}" >&2; exit 1; }
command -v qemu-img >/dev/null || { echo "needs qemu-img" >&2; exit 1; }

say() { printf '\033[0;36m›\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32m✓\033[0m %s\n' "$*"; }

BASE="${SRC%.qcow2}"
NAME="$(basename "${BASE}")"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Declared to the hypervisor. Measured on an idle appliance, see README > Sizing.
CPUS="${ARCIO_OVA_CPUS:-2}"
MEM_MB="${ARCIO_OVA_MEM_MB:-4096}"

CAPACITY="$(qemu-img info --output=json "${SRC}" | grep -oE '"virtual-size": *[0-9]+' | grep -oE '[0-9]+')"
say "Disk capacity: ${CAPACITY} bytes"

# ── VMDK ────────────────────────────────────────────────────────────────────
say "Converting to streamOptimized VMDK..."
qemu-img convert -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic \
  "${SRC}" "${WORK}/${NAME}-disk1.vmdk"
VMDK_BYTES="$(stat -c %s "${WORK}/${NAME}-disk1.vmdk")"

# ── OVF ─────────────────────────────────────────────────────────────────────
#
# firmware=efi is not optional. The Flatcar image is GPT with an EFI System
# Partition and there is no BIOS bootloader on it, so a VM created with the
# default BIOS firmware imports cleanly and then fails to boot with no obvious
# cause.
say "Writing the descriptor..."
cat > "${WORK}/${NAME}.ovf" <<OVF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
          xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
          xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
          xmlns:vmw="http://www.vmware.com/schema/ovf"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="${NAME}-disk1.vmdk" ovf:id="file1" ovf:size="${VMDK_BYTES}"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${CAPACITY}" ovf:capacityAllocationUnits="byte"
          ovf:diskId="vmdisk1" ovf:fileRef="file1"
          ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="VM Network">
      <Description>The network the appliance will be reachable on</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="Arcio">
    <Info>Arcio OS appliance</Info>
    <Name>Arcio</Name>
    <OperatingSystemSection ovf:id="101" vmw:osType="otherLinux64Guest">
      <Info>The kind of installed guest operating system</Info>
      <Description>Flatcar Container Linux</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>vmx-14</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>${CPUS} virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>${CPUS}</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>${MEM_MB}MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>${MEM_MB}</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:ElementName>SCSI Controller 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>1</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>VM Network</rasd:Connection>
        <rasd:ElementName>Network adapter 1</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="efi"/>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF

# ── manifest ────────────────────────────────────────────────────────────────
say "Writing the manifest..."
( cd "${WORK}" && {
    printf 'SHA256(%s)= %s\n' "${NAME}.ovf" "$(sha256sum "${NAME}.ovf" | cut -d' ' -f1)"
    printf 'SHA256(%s)= %s\n' "${NAME}-disk1.vmdk" "$(sha256sum "${NAME}-disk1.vmdk" | cut -d' ' -f1)"
  } > "${NAME}.mf" )

# ── tar, in the order a reader expects ──────────────────────────────────────
say "Packing the OVA..."
( cd "${WORK}" && tar -cf "${NAME}.ova" \
    "${NAME}.ovf" "${NAME}.mf" "${NAME}-disk1.vmdk" )
mv "${WORK}/${NAME}.ova" "${BASE}.ova"

# Asserted, because getting it wrong produces an import error that reads like a
# corrupt download and sends somebody looking in the wrong place.
FIRST="$(tar -tf "${BASE}.ova" | head -1)"
[ "${FIRST}" = "${NAME}.ovf" ] || { echo "OVA order wrong: ${FIRST} is first" >&2; exit 1; }

# ── VHDX ────────────────────────────────────────────────────────────────────
#
# Hyper-V generation 2 is UEFI and takes VHDX. Generation 1 is BIOS and will
# not boot this image at all, for the same reason the OVA sets firmware=efi.
say "Converting to VHDX..."
qemu-img convert -O vhdx "${SRC}" "${BASE}.vhdx"

say "Verifying..."
qemu-img info "${BASE}.vhdx" >/dev/null
for f in "${BASE}.ova" "${BASE}.vhdx"; do
  sha256sum "${f}" > "${f}.sha256"
done

echo
ok "$(basename "${BASE}").qcow2   $(du -h "${SRC}" | cut -f1)   Proxmox, KVM, libvirt   BOOT-TESTED"
ok "$(basename "${BASE}").ova     $(du -h "${BASE}.ova" | cut -f1)   VMware                  structure only"
ok "$(basename "${BASE}").vhdx    $(du -h "${BASE}.vhdx" | cut -f1)   Hyper-V gen 2           structure only"
echo
echo "Hyper-V must be generation 2. A generation 1 VM is BIOS and will not boot this."
