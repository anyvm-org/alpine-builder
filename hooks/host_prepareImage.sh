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

# Make sure qemu can read+write the image on the following steps.
sudo chmod 0666 "${_qcow}" 2>/dev/null || true

echo "Image prepared:"
ls -lh "${_qcow}"
