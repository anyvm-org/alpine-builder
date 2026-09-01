

[![Build](https://github.com/anyvm-org/alpine-builder/actions/workflows/build.yml/badge.svg)](https://github.com/anyvm-org/alpine-builder/actions/workflows/build.yml)

Latest: v2.0.3


The image builder for `alpine`


All the supported releases are here:



| Release | x86_64 | aarch64 | riscv64 |
|---------|---------|---------|---------|
| 3.24 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) |
| 3.23 | ✅ (rsync,scp,sshfs,nfs,tar) | ✅ (rsync,scp,sshfs,nfs,tar) | — |


Alpine publishes cloud images for x86_64 and aarch64 only.

The image URL in each conf pins a full patch version (for example 3.24.1)
even though the release column shows the branch (3.24). Alpine puts the
patch version and an image revision in the filename and publishes no
`latest` alias, but it keeps older patch images in the branch directory --
so the pin is durable, and moving a release to a newer patch is an in-place
URL edit rather than a new release row.

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




How to build:

1. Use the [manual.yml](.github/workflows/manual.yml) to build manually.
   
    Run the workflow manually, you will get a view-only webconsole from the output of the workflow, just open the link in your web browser.
   
    You will also get an interactive VNC connection port from the output, you can connect to the vm by any vnc client.

2. Run the builder locally on your Ubuntu machine.

    Just clone the repo. and run:
    ```bash
    python3 build.py conf/alpine-3.24.conf
    ```
   
