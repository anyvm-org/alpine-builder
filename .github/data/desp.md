How the images are built:

Each image is built automatically in the
[anyvm-org/alpine-builder](https://github.com/anyvm-org/alpine-builder)
repo's GitHub Actions.

x86_64 and aarch64 start from the official Alpine generic cloud image: the
build customizes it (serial console, ssh, first-boot setup), boots it in
QEMU, pre-installs the packages listed in the conf, and exports the disk as
a compressed qcow2 image. No interactive installer is run.

riscv64 has no cloud image upstream, so it installs from the standard
Alpine installer ISO instead, driven over the serial console. The ISO is
attached as a virtio disk rather than a USB CD-ROM, which lets U-Boot boot
it through its EFI loader; the live system then sees UEFI and installs
grub-efi onto an ESP, so the exported image boots under both the EDK2
firmware and the U-Boot payload that anyvm may use at run time.

cloud-init is switched off in the exported cloud images. Alpine's cloud
images carry their network configuration and let their own sshd service
generate the host keys, so cloud-init has nothing left to do here once the
build has injected the ssh key -- while it occupied roughly the first ten
seconds of every boot and was the source of nearly all the boot-time
variance.

Because cloud-init is also what would normally grow the root filesystem on
first boot, the build now does that explicitly instead, and fails rather
than shipping an image whose root did not grow.

Upstream media: the official Alpine cloud images from
https://dl-cdn.alpinelinux.org/alpine/ (overview:
https://alpinelinux.org/cloud/), and for riscv64 the standard installer ISO
from the same mirror.
