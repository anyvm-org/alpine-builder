#!/bin/bash
# Grow the root filesystem to fill the disk, offline, just before export.
#
# WHY HERE AND NOT IN prepareImage. The disk only reaches its final size
# late: _prep_vhd_disk materializes the ~246M upstream cloud image,
# prepareImage runs on THAT, and only then does createVMFromVHD do
# `qemu-img resize +200G`. A first version of this ran in prepareImage and
# failed the build outright --
#     virt-resize: error: You cannot use --expand when there is no surplus
#     space to expand into. You need to make the target disk larger by at
#     least 736.0K.
# -- because at that point there was nothing to expand into. finalizeImage
# runs after shutdown_and_wait() and before the export, with the disk at its
# published size, which is exactly what this needs.
#
# WHY IT IS NEEDED AT ALL. host_prepareImage.sh disables cloud-init to cut
# boot time, and cloud-init's growpart/resizefs was what grew the root on
# the builder's first boot. v2.0.2 shipped without it and every alpine-vm
# job failed with "No space left on device":
#     aarch64  v2.0.1 /dev/sda2 ext4 188G   ->  v2.0.2 223M
#     x86_64   v2.0.1 /dev/sda  ext4 188G   ->  v2.0.2 182M
#
# TWO LAYOUTS, so the root device is DETECTED rather than assumed. Measured
# on the released images:
#     aarch64  GPT: /dev/sda1 vfat EFI + /dev/sda2 ext4 root
#     x86_64   NO partition table at all -- ext4 directly on /dev/sda
#     riscv64  GPT from setup-disk: ESP + swap + ext4 root, already full
set -e

_qcow="${VM_WORK_QCOW:-${VM_OS_NAME}.qcow2}"
[ -s "$_qcow" ] || { echo "FATAL: no image at ${_qcow}" >&2; exit 1; }

export LIBGUESTFS_BACKEND=direct
if ! command -v virt-resize >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y libguestfs-tools
fi
sudo chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

# qemu-img info --output=json prints "virtual-size" TWICE (a nested one for
# the file and the top-level one for the disk); parse it properly rather
# than taking the first grep match, which is the wrong number.
_target_size=$(qemu-img info --output=json "${_qcow}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
[ -n "$_target_size" ] || { echo "FATAL: could not read the virtual size of ${_qcow}" >&2; exit 1; }

_root_dev=$(sudo -E guestfish --ro -a "${_qcow}" -- run : inspect-os 2>/dev/null | head -1)
[ -n "$_root_dev" ] || { echo "FATAL: could not detect the root device in ${_qcow}" >&2; exit 1; }

# Columns end with ... Size Parent, so the size is $(NF-1), in bytes.
_root_size() {
  sudo -E virt-filesystems --long -a "${_qcow}" 2>/dev/null \
    | awk -v d="$_root_dev" '$1 == d { print $(NF-1) }'
}

_before=$(_root_size)
[ -n "$_before" ] || { echo "FATAL: could not read the size of $_root_dev" >&2; exit 1; }
echo "Root ${_root_dev} is ${_before} bytes on a ${_target_size}-byte disk"

if [ "$_before" -ge $((_target_size / 2)) ]; then
  # Already fills the disk -- the riscv64 ISO install partitions the whole
  # thing itself. virt-resize --expand would fail here with "no surplus
  # space", so skipping is required, not merely an optimization.
  echo "Root already fills the disk; nothing to grow."
  exit 0
fi

echo "Before:"
sudo -E virt-filesystems --long -h -a "${_qcow}" 2>/dev/null || true

case "$_root_dev" in
  *[0-9])
    # Root is a PARTITION. virt-resize grows the partition and the filesystem
    # in it and fixes up the GPT backup header -- otherwise the guest kernel
    # reports "Alternate GPT header not at the end of the disk". It writes a
    # NEW image, hence the move afterwards.
    echo "Root is a partition; using virt-resize --expand"
    qemu-img create -f qcow2 -o preallocation=off "${_qcow}.expanded" \
      "$_target_size" >/dev/null
    sudo -E virt-resize --expand "$_root_dev" "${_qcow}" "${_qcow}.expanded"
    mv -f "${_qcow}.expanded" "${_qcow}"
    ;;
  *)
    # Root is the WHOLE DEVICE: no partition table to move, so the filesystem
    # alone is grown, in place. resize2fs with no size fills the device;
    # e2fsck first because resize2fs refuses an unchecked filesystem.
    echo "Root is the whole device; using resize2fs in place"
    sudo -E guestfish -a "${_qcow}" -- run \
      : e2fsck "$_root_dev" forceall:true \
      : resize2fs "$_root_dev"
    ;;
esac

echo "After:"
sudo -E virt-filesystems --long -h -a "${_qcow}" 2>/dev/null || true

# A silent no-op is exactly what shipped in v2.0.2, so make it fatal.
_after=$(_root_size)
[ -n "$_after" ] || { echo "FATAL: could not read the size of $_root_dev after the resize" >&2; exit 1; }
if [ "$_after" -lt $((_target_size / 2)) ]; then
  echo "FATAL: $_root_dev is ${_after} bytes on a ${_target_size}-byte disk" >&2
  echo "       -- the resize did not take. Shipping this image would fill" >&2
  echo "       the moment a workspace is copied into it, which is how" >&2
  echo "       v2.0.2 broke every alpine-vm job." >&2
  exit 1
fi

sudo chmod 0666 "${_qcow}" 2>/dev/null || true
echo "Root filesystem grown to ${_after} bytes."
