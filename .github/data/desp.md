How the images are built:

Each image is built automatically in the
[anyvm-org/alpine-builder](https://github.com/anyvm-org/alpine-builder)
repo's GitHub Actions: it downloads the official Alpine Linux generic
cloud image, customizes it (serial console, ssh, first-boot setup),
boots it in QEMU, pre-installs the packages listed in the conf, and
exports the disk as a compressed qcow2 image. No interactive installer
is run.

cloud-init is switched off in the exported images. Alpine's cloud images
carry their network configuration and let their own sshd service generate
the host keys, so cloud-init has nothing left to do here once the build has
injected the ssh key -- while it occupied roughly the first ten seconds of
every boot and was the source of nearly all the boot-time variance.

Upstream media: the official Alpine cloud images from
https://dl-cdn.alpinelinux.org/alpine/ (overview:
https://alpinelinux.org/cloud/).
