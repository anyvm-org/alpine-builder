#!/bin/bash
# host-side prepareImage hook (runs in main process env after _prep_vhd_disk
# materialized "${VM_OS_NAME}.qcow2" but BEFORE the VM is started).
#
# Alpine cloud images ship with NO console password and NO ssh key, so there
# is no way to log in on first boot. Bake root SSH access straight into the
# qcow2 with virt-customize, so once the VM boots we can just ssh in via the
# slirp hostfwd port (see host_enablessh.sh). Avoids a cloud-init seed disk.

set -e

# build.py writes the working image under build/ (VM_WORK_QCOW); fall back to
# the repo-root name for a standalone hook run.
_qcow="${VM_WORK_QCOW:-${VM_OS_NAME}.qcow2}"

echo "Preparing ${_qcow} with virt-customize"

# Generate the build's SSH keypair now so we can inject its public key into
# the image. build.py would otherwise create the same key later; reuse it.
if [ ! -e "$HOME/.ssh/id_rsa" ]; then
  ssh-keygen -f "$HOME/.ssh/id_rsa" -q -N ""
fi
_pub="$HOME/.ssh/id_rsa.pub"

# libguestfs on a GitHub-hosted runner needs the direct backend.
export LIBGUESTFS_BACKEND=direct
if ! command -v virt-customize >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y libguestfs-tools
fi
# Make the host kernel readable for the libguestfs appliance (harmless if it
# is already readable / not present).
sudo chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

_pw="${VM_ROOT_PASSWORD:-anyvm.org}"

# Everything below is FILESYSTEM-level so the SAME command also works when
# we customize an aarch64 image on this x86 runner. We deliberately avoid
# --run-command, which has to execute a binary INSIDE the guest and fails
# cross-arch with "host cpu (x86_64) and guest arch (aarch64) are not
# compatible". --no-network disables the libguestfs appliance network (newer
# libguestfs defaults it on and tries to start "passt", which fails on the
# GitHub-hosted runner: "libguestfs error: passt exited with status 1").
#
# Access is granted by the injected root key. We append PermitRootLogin etc.
# to the main sshd_config: sshd takes the FIRST value it obtains for a
# keyword, so an appended line only wins if nothing earlier sets it. Nothing
# does here -- Alpine's stock sshd_config leaves PermitRootLogin commented
# out, and the cloud-init drop-in the image ships under sshd_config.d sets
# PasswordAuthentication but not PermitRootLogin. Even if that ever changed,
# the build would still get in: the injected key works under the
# prohibit-password default too. sshd is already enabled on cloud images, so
# no "systemctl enable" is needed here.
sudo -E virt-customize --no-network -a "${_qcow}" \
  --root-password "password:$_pw" \
  --ssh-inject "root:file:$_pub" \
  --append-line '/etc/ssh/sshd_config:PermitRootLogin yes' \
  --append-line '/etc/ssh/sshd_config:PubkeyAuthentication yes' \
  --append-line '/etc/ssh/sshd_config:AcceptEnv *' \
  --write '/etc/cloud/cloud.cfg.d/99-anyvm-ds.cfg:datasource_list: [ NoCloud, None ]'

# --- drop the ten-second bootloader countdown ------------------------------
# Both cloud images sit at a boot menu for ten seconds before the kernel is
# even loaded. That is pure wall clock, and it is paid on EVERY boot of every
# exported image, not just once at build time. Measured on 3.24.1 here:
#   x86_64   syslinux counts 10 -> 1 before "Loading vmlinuz-virt"
#   aarch64  kernel start 19s -> 8s once the grub timeout is gone
#
# The two arches use DIFFERENT bootloaders, and `virt-customize --edit` FAILS
# on a file that is not present -- so the wrong edit does not quietly no-op,
# it breaks that arch's build. Detect the bootloader rather than branching on
# $VM_ARCH: the arch is not what decides this (an x86 UEFI image would use
# grub too), and this repo's rule is not to infer capability from an arch name.
_boot_ls=$(sudo -E virt-ls -a "${_qcow}" /boot 2>/dev/null || true)

if printf '%s\n' "$_boot_ls" | grep -qx 'extlinux.conf'; then
  # BIOS images: syslinux/extlinux.
  #  * DEFAULT menu.c32 loads the MENU module, which runs its own
  #    "MENU AUTOBOOT Alpine will be booted automatically in # seconds."
  #    countdown; PROMPT 0 does NOT suppress it. Pointing DEFAULT at the real
  #    label is what keeps the menu module from loading at all.
  #  * TIMEOUT is in tenths of a second, and `TIMEOUT 0` means WAIT FOREVER in
  #    syslinux -- the one value that must never be used here. 1 = 0.1 s.
  #  * /etc/update-extlinux.conf is the generator's input: without it a kernel
  #    upgrade in the guest re-runs update-extlinux and restores the 10 s.
  echo "Bootloader: extlinux -- removing the boot menu countdown"
  sudo -E virt-customize --no-network -a "${_qcow}" \
    --edit '/boot/extlinux.conf:s/^DEFAULT menu.c32/DEFAULT virt/' \
    --edit '/boot/extlinux.conf:s/^TIMEOUT .*/TIMEOUT 1/' \
    --edit '/etc/update-extlinux.conf:s/^timeout=.*/timeout=1/'
elif printf '%s\n' "$_boot_ls" | grep -qx 'grub'; then
  # UEFI images: grub, whose timeout convention is the OPPOSITE of syslinux --
  # here 0 really does mean "boot immediately".
  #  * grub.cfg carries the value TWICE (the feature_timeout_style branch and
  #    the fallback under it), so the substitution is not anchored to one line.
  #  * grub.cfg is generated and says DO NOT EDIT, but it is what the firmware
  #    actually reads, and grub-mkconfig cannot be re-run from here: this hook
  #    is filesystem-only on purpose so the same code can customize an aarch64
  #    image on an x86 runner. /etc/default/grub is updated too, so a later
  #    grub-mkconfig inside the guest keeps the setting.
  echo "Bootloader: grub -- removing the boot menu countdown"
  sudo -E virt-customize --no-network -a "${_qcow}" \
    --edit '/boot/grub/grub.cfg:s/^\s*set timeout=.*/set timeout=0/' \
    --edit '/etc/default/grub:s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/'
else
  echo "WARNING: no extlinux.conf and no grub/ under /boot in ${_qcow};"
  echo "         leaving the bootloader timeout alone."
fi

# Make sure qemu can read+write the image on the following steps.
sudo chmod 0666 "${_qcow}" 2>/dev/null || true

echo "Image prepared:"
ls -lh "${_qcow}"
