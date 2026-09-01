#!/bin/bash
# Place the Alpine riscv64 installer ISO where createVM() will attach it as a
# VIRTIO DISK rather than a USB CD-ROM.
#
# Gated on VM_ARCH, because that is the actual condition: this is a property
# of the firmware, not of the media. run_hook fires this file for every conf
# in the builder, and the x86_64/aarch64 confs take the cloud-image path
# (VM_VHD_LINK + host_prepareImage.sh), which has nothing to do with any of
# this.
#
# WHY .img AND NOT .iso. build.py's riscv64 ISO path attaches the medium as
# "-device usb-storage" + "media=cdrom". U-Boot's USB storage driver handles
# direct-access devices, not the CD-ROM/MMC profile, so it never sees the
# disc -- measured: "Device 0: unknown device", then a fall-through to TFTP
# and a drop to the u-boot prompt. createVM() attaches an already-present
# <os>.img with if=virtio instead, and u-boot scans virtio without trouble;
# the same ISO then boots to a login prompt with efivarfs mounted, which is
# what makes setup-disk install grub-efi onto an ESP (see the conf).
#
# clearVM() runs BEFORE this hook and removes <os>.img, so the copy is made
# fresh on every run. The download itself is cached under its own name, which
# clearVM does not touch.
set -euo pipefail

if [ "${VM_ARCH:-}" != "riscv64" ] || [ -z "${VM_ISO_LINK:-}" ]; then
  exit 0
fi

WORK="${VM_WORKDIR:-build}"
mkdir -p "$WORK"
CACHE="$WORK/$(basename "$VM_ISO_LINK")"
MEDIA="$WORK/${VM_OS_NAME}.img"

echo "=== alpine riscv64: preparing the installer medium ==="

if [ ! -s "$CACHE" ]; then
  echo "--- fetching $VM_ISO_LINK ---"
  # Segmented when the mirror honours Range, single-stream when it does not:
  # without Range every extra connection restarts at byte 0, so parallelism
  # would waste bandwidth rather than save time.
  if curl -sI --max-time 60 -r 0-99 "$VM_ISO_LINK" 2>/dev/null | grep -qi "206 Partial"; then
    if command -v aria2c >/dev/null 2>&1; then
      aria2c -c -x8 -s8 --console-log-level=warn -d "$WORK" \
        -o "$(basename "$CACHE")" "$VM_ISO_LINK"
    elif command -v axel >/dev/null 2>&1; then
      axel -n 8 -o "$CACHE" "$VM_ISO_LINK"
    else
      curl -fSL --retry 3 --retry-delay 5 -o "$CACHE" "$VM_ISO_LINK"
    fi
  else
    curl -fSL --retry 3 --retry-delay 5 -o "$CACHE" "$VM_ISO_LINK"
  fi
fi
[ -s "$CACHE" ] || { echo "FATAL: installer ISO is empty or missing" >&2; exit 1; }
ls -lh "$CACHE"

cp -f "$CACHE" "$MEDIA"
chmod 0666 "$MEDIA"
ls -lh "$MEDIA"

echo "=== alpine riscv64: installer medium ready at $MEDIA ==="
